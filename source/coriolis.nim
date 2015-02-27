import iRc, sTrUtIlS, mATH

import dynlib, os, tables, sets


###############

##==--- Module System ------------------------------------------------------==##

##==--- Types
type
    TCommandRet   = proc(IrcConnection : PIrc)
    TCommandProc  = proc(Event : TIrcEvent) : TCommandRet
    TCommandEntry = object
        Proc : TCommandProc
        Key  : string

##==--- Constants
# TODO(blandcr) - get this from a config file
let ModulePath = "./modules"

##==--- Globals
var
    CommandTable = initTable[string, TCommandProc]()

##==--- Procs
proc RegisterCommands(Commands : seq[TCommandEntry]) : bool =
    for Command in Commands:
        if not(CommandTable.hasKey(Command.Key)):
            CommandTable[Command.Key] = Command.Proc
    return true

proc LoadModule(ModuleName : string) : LibHandle =
    const ModuleExtension = when defined(win32)  : ".dll"
                            elif defined(macosx) : ".dylib"
                            else                 : ".so"
    var Module = loadLib(ModulePath & "/" & ModuleName & "." & ModuleExtension)
    if Module == nil:
        return Module
    
    type
        TGCP = proc() : seq[TCommandEntry] {.cdecl}

    let GetCommandsProc =
        cast[TGCP](symAddr(Module, "GetCommands"))
    let Commands = GetCommandsProc()
    
    discard RegisterCommands(Commands)
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

proc TokenizeMessage(Event : TIrcEvent) : seq[string] =
    let Message = Event.params[Event.params.high]
    
    if (len Message) < 1:
        echo "(II) TokenizeMessage : nil message, no tokens"
        return nil
    else:
        return split(Message, " ")

proc Authenticate(Event : TIrcEvent) : TCommandRet =
    let Tokens = TokenizeMessage(Event)
    var Message = "User " & Event.nick
    if (len Tokens) >= 2 and Tokens[1] == Password:
        AuthorizedNicks.add(Event.nick)
        Message &= " authorized for me!"
    else:
        Message &= " doesn't know how to type ;_;"
    return proc(IrcConnection : PIrc) =
        IrcConnection.privmsg(Event.origin, Message)

proc LoadModule(Event : TIrcEvent) : TCommandRet =
    let Tokens = TokenizeMessage(Event)
    if (len Tokens) == 2:
        let ModuleName = Tokens[1]
        let Module = LoadModule(ModuleName)
        let Message = if Module == nil: "No module '" & ModuleName & "' exists!"
                      else:             "Module '" & ModuleName & "' loaded!"
        return proc(IrcConnection : PIrc) =
            IrcConnection.privmsg(Event.origin, Message)
    else:
        return proc(IrcConnection : PIrc) =
            IrcConnection.privmsg(
                Event.origin, "Incorrect syntax. Syntax is: '!load ModuleName'"
            )

proc JoinChannel(Event : TIrcEvent) : TCommandRet =
    let Tokens = TokenizeMessage(Event)
    if (len Tokens) < 2:
        echo "(EE) JoinChannel : Improper format"
        return proc(IrcConnection : PIrc) =
            IrcConnection.privmsg(Event.origin, "SQL JOIN QUERIES NOT ACCEPTED")

    let Channel = Tokens[1]
    
    let Key =
            if (len Tokens) > 2 :
                Tokens[2]
            else :
                ""

    if Channel in Channels:
        echo "(II) JoinChannel : Already in this channel!"
        return proc(IrcConnection : PIrc) =
            IrcConnection.privmsg(Event.origin, "Already there, bub.")
    else:
        echo "(II) JoinChannel : " & Channel
        return proc(IrcConnection : PIrc) =
            IrcConnection.privmsg(Event.origin, "ACKNOWLEDGED, COMMANDER")
            IrcConnection.join(Channel, Key)

proc PartChannel(Event : TIrcEvent) : TCommandRet =
    let Tokens = TokenizeMessage(Event)
    if (len Tokens) < 2:
        echo "(EE) PartChannel : Improper format"
        return proc(IrcConnection : PIrc) =
            IrcConnection.privmsg(Event.origin, "Gotta gotta type 'em all")

    let Channel = Tokens[1]

    if Channel in Channels:
        echo "(II) PartChannel : " & Channel
        return proc(IrcConnection : PIrc) =
            IrcConnection.privmsg(Event.origin, "HI-YO SILVER! AWAY!")
            IrcConnection.part(Channel, "Some berk told me to leave")
    else:
        return proc(IrcConnection : PIrc) =
            IrcConnection.privmsg(Event.origin, "Can't leave whatcha don't got")

#TODO(blandcr) - move this garbage out into a module
proc LoADJErKS() : seq[string] =
    var res : seq[string] = @[]
    let JerkXml = reADfIlE("source/jerkcity.xml")
    for lInE in JeRkxML.sPlItLINeS:
        if line[0] != '<':
            let segs = split(line, ":")
            if segs.len > 1:
                let jstr = strip segs[1]
                res.add(jstr)
            else:
                let jstr = strip line
                res.add(jstr)
    return res

let JerkLines = LoadJerks()
        
proc JErKOff(Event : TIrcEvent) : TCommandRet =
    return proc(IrcConnection : PIrc) =
        IrcConnection.privmsg(Event.origin, JeRkLiNEs[random(JerKLiNes.high)])

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


discard RegisterCommands(@[
    TCommandEntry(Key : "!auth", Proc : Authenticate),
    TCommandEntry(Key : "@load", Proc : LoadModule),
    TCommandEntry(Key : "@part", Proc : PartChannel),
    TCommandEntry(Key : "@join", Proc : JoinChannel),
    TCommandEntry(Key : "!jerk", Proc : JerkOff)
])

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

proc HandlePrivMsg(Event : TIrcEvent) =
    
    let Message = Event.params[Event.params.high]

    if (len Message) < 1:
        echo "(II) HandlePrivMsg : nil message, doing nothing"
        return

    let Tokens = TokenizeMessage(Event)

    if Message[0] == '!':
        if (len Tokens) < 1:
            echo "(EE) HandlePrivMsg : nil command, doing nothing"
            return

        let Command = Tokens[0]
        if CommandTable.hasKey(Command):
            echo "(II) HandlePrivMsg : Command is '" & Command & "'"
            var CommandProc = CommandTable[Command]
            #TODO(blandcr) - We might need to pass a ref to IrcThing into the
            #                module if there are more complicated operates to
            #                perform...
            let Action = CommandProc(Event)
            if Action != nil:
                Action(IrcThing)
        else:
            echo "(II) HandlePrivMsg : Command '" & Command & "' doesn't exist."
    elif Message[0] == '@':
        if (len Tokens) < 1:
            echo "(EE) HandlePrivMsg : nil command, doing nothing"
            return

        let Command = Tokens[0]
        if Event.nick in AuthorizedNicks and CommandTable.hasKey(Command):
            echo "(II) HandlePrivMsg : Command is '" & Command & "'"
            var CommandProc = CommandTable[Command]
            let Action = CommandProc(Event)
            if Action != nil:
                Action(IrcThing)
        else:
            echo "(II) Unauthorized attempt for command '" & Command & "'"
            return

