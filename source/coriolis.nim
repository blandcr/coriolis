import irc
import dynlib, os
import tables, strutils
from sequtils import concat

##==--- Module System ------------------------------------------------------==##

import module_interface

##==--- Types
type
    TModuleInfo = object
        CommandKeys  : seq[string]
        ModuleHandle : LibHandle

##==--- Constants
# TODO(blandcr) - get this from a config file
let ModulePath = ""

##==--- Globals
var
    CommandTable = initTable[string, TCommandEntry]()
    ModuleTable  = initTable[string, TModuleInfo]()

##==--- Procs
proc RegisterCommand(Command : TCommandEntry) : bool =
    if not(CommandTable.hasKey(Command.Key)):
        CommandTable[Command.Key] = Command
        return true
    else:
        return false

proc UnregisterCommand(CommandName : string) : bool =
    if CommandTable.hasKey(CommandName):
        CommandTable.del(CommandName)
        return true
    else:
        return false

proc UnloadModule(ModuleName : string) : bool =
    if ModuleTable.hasKey(ModuleName):
        let ModuleInfo = ModuleTable[ModuleName]
        for CommandName in ModuleInfo.CommandKeys:
            discard UnregisterCommand(CommandName)
        unloadLib(ModuleInfo.ModuleHandle)
        ModuleTable.del(ModuleName)
        return true
    else:
        return false

proc LoadModule(ModuleName : string) : LibHandle =
    const ModuleExtension = when defined(win32)  : ".dll"
                            elif defined(macosx) : ".dylib"
                            else                 : ".so"

    if ModuleTable.hasKey(ModuleName):
        return nil

    #var Module = loadLib(ModulePath & "/" & ModuleName & "." & ModuleExtension)
    var Module = loadLib(ModulePath & ModuleName & ModuleExtension)
    if Module == nil:
        return nil

    type
        TGCP = proc() : seq[TCommandEntry] {.cdecl.}

    let GetCommandsProc =
        cast[TGCP](symAddr(Module, "GetCommands"))
    if GetCommandsProc == nil:
        return nil
    
    let Commands = GetCommandsProc()
    
    var ModuleInfo = TModuleInfo(
        CommandKeys  : @[],
        ModuleHandle : Module
    )

    for Command in Commands:
        if RegisterCommand(Command):
            ModuleInfo.CommandKeys.add(Command.Key)
    ModuleTable[ModuleName] = ModuleInfo
    return Module

#==--- Irc Bot Logic -------------------------------------------------------==##

#==--- Constants
#TODO(blandcr) - load this from a file or something

#==--- Globals

var
    AuthorizedNicks : seq[string] = @[]
    
    IrcServer : string
    Channels  : seq[string] = @[]
    Name      : string

    Password : string

    IrcThing : PIrc
#==--- Default Commands

proc GetHelp(Args : TCommandArgs) : TCommandRet =
    proc MakeNotice(Message : string) : TCommandAction =
        return TCommandAction(
            Action    : TActionType.PrivMsg,
            Arguments : @[Args.Source, Message]
        )
    let Tokens = split(Args.Arguments, " ")
    if (len Tokens) == 0:
        var HelpMsgs = @[MakeNotice("Help for " & Name)]
        HelpMsgs.add(MakeNotice("The following commands are available:"))
        for Command in CommandTable.values:
            let Info = if Command.Info != nil : Command.Info
                       else                   : ""
            HelpMsgs.add(
                MakeNotice("    " & Command.Key & " - " & Info)
            )
        return HelpMsgs
    elif (len Tokens) == 1:
        var HelpMsgs : seq[TCommandAction] = @[MakeNotice(
            "Help for command `" & Tokens[0] & "`:"
        )]
        if CommandTable.hasKey(Tokens[0]):
            if CommandTable[Tokens[0]].Help == nil:
                HelpMsgs.add(MakeNotice(
                    "No help available for command `" & Tokens[0] & "`."
                ))
            else:
                for Line in CommandTable[Tokens[0]].Help:
                    HelpMsgs.add(MakeNotice(Line))
        else:
            HelpMsgs.add(
                MakeNotice("Command `" & Tokens[0] & "` does not exist!")
            )
        return HelpMsgs
    else:
        return @[MakeNotice("Incorrect usage. See `!help !help`")]

proc Authenticate(Args : TCommandArgs) : TCommandRet =
    let Tokens = split(Args.Arguments, " ")
    var Message = "User " & Args.Source
    
    if (len Tokens) == 1 and Tokens[0] == Password:
        AuthorizedNicks.add(Args.Source)
        Message &= " authorized for me!"
    else:
        Message &= " doesn't know how to type ;_;"
    return @[TCommandAction(
        Action    : TActionType.PrivMsg,
        Arguments : @[Args.Channel, Message]
    )]

proc LoadModule(Args : TCommandArgs) : TCommandRet =
    let Tokens = split(Args.Arguments, " ")
    if (len Tokens) == 1:
        let ModuleName = Tokens[0]
        let Module = LoadModule(ModuleName)
        let Message = if Module == nil: "No module '" & ModuleName & "' exists!"
                      else:             "Module '" & ModuleName & "' loaded!"
        return @[TCommandAction(
            Action    : TActionType.PrivMsg,
            Arguments : @[Args.Channel, Message]
        )]
    else:
        return @[TCommandAction(
            Action    : TActionType.PrivMsg,
            Arguments : @[
                Args.Channel,
                "Incorrect syntax. Syntax is: `!load ModuleName`"
            ]
        )]

proc UnloadModule(Args : TCommandArgs) : TCommandRet =
    let Tokens = split(Args.Arguments, " ")
    if (len Tokens) == 1:
        let ModuleName = Tokens[0]
        if UnloadModule(ModuleName):
            return @[TCommandAction(
                Action    : TActionType.PrivMsg,
                Arguments : @[
                    Args.Channel,
                    "Module `" & ModuleName & "` successfully unloaded!"
                ]
            )]
        else:
            return @[TCommandAction(
                Action    : TActionType.PrivMsg,
                Arguments : @[
                    Args.Channel,
                    "Unload of module `" & ModuleName & "` was unsuccessful."
                ]
            )]
    else:
        return @[TCommandAction(
            Action    : TActionType.PrivMsg,
            Arguments : @[
                Args.Channel,
                "Invalid formatting for command `UnloadModule`"
            ]
        )]

proc ReloadModule(Args : TCommandArgs) : TCommandRet =
    # todo(blandcr) implement correct exception behavior here:
    #   if the unload fails for some reason then ignore the output from unload
    #   and only return the output from load
    let UnloadMsgs = UnloadModule(Args)
    let LoadMsgs = LoadModule(Args)
    return concat(UnloadMsgs, LoadMsgs)

proc JoinChannel(Args : TCommandArgs) : TCommandRet =
    let Tokens = split(Args.Arguments, " ")
    if (len Tokens) < 1:
        echo "(EE) JoinChannel : Improper format"
        return @[TCommandAction(
            Action    : TActionType.PrivMsg,
            Arguments : @[Args.Channel, "SQL JOIN QUERIES NOT ACCEPTED"]
        )]

    let Channel = Tokens[0]
    
    let Key =
            if (len Tokens) > 1 :
                Tokens[1]
            else :
                ""

    if Channel in Channels:
        echo "(II) JoinChannel : Already in this channel!"
        return @[TCommandAction(
            Action    : TActionType.PrivMsg,
            Arguments : @[Args.Channel, "Already there, bub."]
        )]
    else:
        return @[
            TCommandAction(
                Action    : TActionType.PrivMsg,
                Arguments : @[Args.Channel, "ACKNOWLEDGED, COMMANDER"]
            ),
            TCommandAction(
                Action    : TActionType.Join,
                Arguments : @[Channel, Key]
            )
        ]

proc PartChannel(Args : TCommandArgs) : TCommandRet =
    let Tokens = split(Args.Arguments, " ")
    if (len Tokens) < 1:
        echo "(EE) PartChannel : Improper format"
        return @[TCommandAction(
            Action    : TActionType.PrivMsg,
            Arguments : @[Args.Channel, "Gotta gotta type 'em all"]
        )]

    let Channel = Tokens[0]

    if Channel in Channels:
        echo "(II) PartChannel : " & Channel
        return @[
            TCommandAction(
                Action    : TActionType.PrivMsg,
                Arguments : @[Args.Channel, "HI-YO SILVER! AWAY!"]
            ),
            TCommandAction(
                Action    : TActionType.Part,
                Arguments : @[Channel, "Some berk told me to leave"]
            )
        ]
    else:
        return @[TCommandAction(
            Action    : TActionType.PrivMsg,
            Arguments : @[Args.Channel, "Can't leave whatcha don't got"]
        )]

#TODO(blandcr) - LoadConfig should return the config options. for now we'll just
#                use a hack.
var InitialChannels : seq[string] = @[]
proc LoadConfig(ConfigFile : string) : bool =
    let Config = readFile(ConfigFile)
    proc ProcessConfigLine(ConfigLine : string) : seq[string] =
        let Tokens = ConfigLine.split(":")
        let OptionName = if (len Tokens) > 0 : toLower strip Tokens[0]
                         else                : nil
        let SeparatorIndex = ConfigLine.find(":")
        if OptionName == nil or SeparatorIndex == -1:
            return nil
        else:
            return @[
                OptionName, strip ConfigLine[SeparatorIndex+1 .. ConfigLine.high]
            ]

    for Line in (splitlines Config):
        let OptionInfo = ProcessConfigLine(Line)
        if OptionInfo == nil:
            continue
        let OptionName  = OptionInfo[0]
        let OptionValue = OptionInfo[1]
        
        echo "(II) Config : Option is '" &
             OptionName                  &
             "' and value is '"          &
             OptionValue                 &
             "'"

        case OptionName
        of "nick"     : Name      = OptionValue
        of "server"   : IrcServer = OptionValue
        of "channels" :
            for Channel in split(OptionValue, ","):
                InitialChannels.add(strip(Channel))
        of "password" : Password  = OptionValue
        else          : discard
    return true


for CommandEntry in @[
    TCommandEntry(
        Key  : "!auth",
        Proc : Authenticate,
        Info : "Authorizes a user for access to elevated commands.",
        Help : @[
            "This command is used to gain access to elevated commands such as",
            "joining and parting channels. Usage is as follows:",
            "    `!auth <PASSWORD>`",
            "where <PASSWORD> is the password you have been provided. Once",
            "authenticated your user name will remain authenticated for as",
            "long as the bot remains alive. This is a bad thing and will be",
            "changed so that your authentication will remain only as long as",
            "the bot is aware of you."
        ]
    ),
    TCommandEntry(
        Key  : "!help",
        Proc : GetHelp,
        Info : "Displays help information.",
        Help : @[
            "This command is used to gain help regarding various other",
            "commands. It has two usage modes:",
            "    `!help`",
            "    `!help <COMMAND>`",
            "The first usage will display a listing of all available commands",
            "and a short description for each. The second usage will display",
            "detailed help for a given command."
        ]
    ),
    TCommandEntry(
        Key  : "@load",
        Proc : LoadModule,
        Info : "Loads a module.",
        Help : @[
            "This command is used to load a module into the bot. Usage:",
            "    `@load <MODULENAME>`"
        ]
    ),
    TCommandEntry(
        Key  : "@reload",
        Proc : ReloadModule,
        Info : "Reloads a module.",
        Help : @[
            "This command is used to reload a module into the bot. Usage:",
            "    `@reload <MODULENAME>`"
        ]
    ),
    TCommandEntry(
        Key  : "@unload",
        Proc : UnloadModule,
        Info : "Unloads a module.",
        Help : @[
            "This command is used to unload a module from the bot. Usage:",
            "    `@unload <MODULENAME>`"
        ]
    ),
    TCommandEntry(
        Key  : "@part",
        Proc : PartChannel,
        Info : "Leaves a channel.",
        Help : @[
            "This command is used to leave a given channel. Usage:",
            "    `@part <#CHANNEL>`"
        ]
    ),
    TCommandEntry(
        Key  : "@join",
        Proc : JoinChannel,
        Info : "Joins a channel.",
        Help : @[
            "This command is used to join a given channel. Usage:",
            "    `@join <#CHANNEL>`"
        ]
    ),
]:
    discard RegisterCommand(CommandEntry)

proc HandleExit(Tokens : seq[string]) =
    send(IrcThing, "QUIT  :snerf borf", sendImmediately=true)
    close(IrcThing)
    quit(0)

proc HandlePrivMsg(Event : TIrcEvent)

#==--- This stuff should be in a function somewhere or something. ugh. -----==##
import parseopt
var ConfigSpecified = false
for Kind, Key, Value in getopt():
    case Key
    of "file":
        echo Value
        if existsFile(Value):
            ConfigSpecified = LoadConfig(Value)
        else:
            echo "(EE) Invalid configuration file specified. Exiting."
            quit(0)
    else:
        discard

if not ConfigSpecified:
    echo "(EE) No config file specified!!! Exiting."
    quit(0)

IrcThing = newIrc(
    address   = IrcServer,
    nick      = Name,
    user      = Name,
    realname  = Name,
    joinChans = InitialChannels
)

#==--- The part that does stuff --------------------------------------------==##

IrcThing.connect()

while true:
    var Event: TIRCEvent
    if IrcThing.poll(Event):
        case Event.typ
        of EvConnected:
            discard
        of EvDisconnected, EvTimeout:
            IrcThing.connect()
        of EvMsg:
            case Event.cmd
            of MPrivMsg:
                echo "(II) Seeing MPrivMsg..."
                HandlePrivMsg(Event)
            of MJoin:
                echo "(II) Seeing MJoin... " & Event.origin
                Channels.add(Event.origin)
                echo Channels
            of MPart:
                echo "(II) Seeing MPart... " & Event.origin
                Channels.delete(find(Channels, Event.origin))
                echo Channels
            of MKick:
                echo "(II) Seeimg MKick... " & Event.origin
                Channels.delete(find(Channels, Event.origin))
                echo Channels
            else:
                discard
            echo(Event.raw)

proc BindAction(IrcThing : PIRC, Action : TCommandAction) : proc() =
    case Action.Action
    of TActionType.PrivMsg:
        if (len Action.Arguments) != 2:
            echo "(EE) Invalid number of arguments for binding PrivMsg"
            return proc() = discard
        return proc() =
            IrcThing.privmsg(Action.Arguments[0], Action.Arguments[1])
    of TActionType.Notice:
        if (len Action.Arguments) != 2:
            echo "(EE) Invalid number of arguments for binding Notice"
            return proc() = discard
        return proc() =
            IrcThing.notice(Action.Arguments[0], Action.Arguments[1])
    of TActionType.Join:
        if (len Action.Arguments) != 2:
            echo "(EE) Invalid number of arguments for binding Join"
            return proc() = discard
        return proc() =
            IrcThing.join(Action.Arguments[0], Action.Arguments[1])
    of TActionType.Part:
        if (len Action.Arguments) != 2:
            echo "(EE) Invalid number of arguments for binding Part"
            return proc() = discard
        return proc() =
            IrcThing.part(Action.Arguments[0], Action.Arguments[1])
    of TActionType.Close:
        return proc() = discard
    of TActionType.Connect:
        return proc() = discard
    of TActionType.Reconnect:
        return proc() = discard
    of TActionType.SendRaw:
        if (len Action.Arguments) != 1:
            echo "(EE) Invalid number of arguments for binding SendRaw"
        return proc() =
            IrcThing.send(Action.Arguments[0])

proc HandlePrivMsg(Event : TIrcEvent) =
    
    let Message = Event.params[Event.params.high]

    if (len Message) < 1:
        echo "(II) HandlePrivMsg : nil message, doing nothing"
        return
    
    let Tokens = split(Message, " ")

    if Message[0] == '!' and (len Message) > 1:
        if (len Tokens) < 1:
            echo "(EE) HandlePrivMsg : nil command, doing nothing"
            return

        let Command = Tokens[0]
        if CommandTable.hasKey(Command):
            echo "(II) HandlePrivMsg : Command is '" & Command & "'"
            var CommandProc = CommandTable[Command].Proc
            #TODO(blandcr) - We might need to pass a ref to IrcThing into the
            #                module if there are more complicated operates to
            #                perform...
            let Actions = CommandProc(TCommandArgs(
                Source    : Event.nick,
                Channel   : Event.origin,
                Arguments : join(Tokens[1..Tokens.high])
            ))
            for Action in Actions:
                BindAction(IrcThing, Action)()
        else:
            echo "(II) HandlePrivMsg : Command '" & Command & "' doesn't exist."
    elif Message[0] == '@':
        if (len Tokens) < 1:
            echo "(EE) HandlePrivMsg : nil command, doing nothing"
            return

        let Command = Tokens[0]
        if Event.nick in AuthorizedNicks and CommandTable.hasKey(Command):
            echo "(II) HandlePrivMsg : Command is '" & Command & "'"
            var CommandProc = CommandTable[Command].Proc
            let Actions = CommandProc(TCommandArgs(
                Source    : Event.nick,
                Channel   : Event.origin,
                Arguments : join(Tokens[1..Tokens.high])
            ))
            for Action in Actions:
                BindAction(IrcThing, Action)()
        else:
            echo "(II) Unauthorized attempt for command '" & Command & "'"
            return

