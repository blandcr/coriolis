import iRc, sTrUtIlS, mATH

import dynlib, os, tables, sets


###############

##==--- Module System ------------------------------------------------------==##

##==--- Types
type
    TCommandProc  = proc(Event : TIrcEvent) : string
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
const
    Password = "CORGIFREEZER!"

#==--- Globals

var
    AuthorizedNicks : seq[string] = @[]
    
    IrcServer = "irc.efnet.net"
    Channels  = @["#corgifreezer"]
    Name      = "coriolis"

    IrcThing = newIrc(
        address   = IrcServer,
        nick      = Name,
        user      = Name,
        realname  = Name,
        joinChans = Channels
    )

#==--- Default Commands

proc TokenizeMessage(Event : TIrcEvent) : seq[string] =
    let Message = Event.params[Event.params.high]
    
    if (len Message) < 1:
        echo "(II) TokenizeMessage : nil message, no tokens"
        return nil
    else:
        return split(Message, " ")

proc Authenticate(Event : TIrcEvent) : string =
    let Tokens = TokenizeMessage(Event)
    if (len Tokens) >= 2 and Tokens[1] == Password:
        AuthorizedNicks.add(Event.nick)
        return "User " & Event.nick & " authorized for me!"
    else:
        return "User " & Event.nick & " does not know shit."

proc LoadModule(Event : TIrcEvent) : string =
    let Tokens = TokenizeMessage(Event)
    if (len Tokens) == 2:
        let ModuleName = Tokens[1]
        let Module = LoadModule(ModuleName)
        if Module == nil:
            return "Module '" & ModuleName & "' cannot be found!!!"
        else:
            return "Module '" & ModuleName & "' loaded!"
    else:
        return "Incorrect syntax. Syntax is: '!load ModuleName'"

proc JoinChannel(Event : TIrcEvent) : string =
    let Tokens = TokenizeMessage(Event)
    if (len Tokens) < 2:
        echo "(EE) JoinChannel : Improper format"
        return nil

    let Channel = Tokens[1]
    
    let Key =
            if (len Tokens) > 2 :
                Tokens[2]
            else :
                ""

    if Channel in Channels:
        echo "(II) JoinChannel : Already in this channel!"
    else:
        echo "(II) JoinChannel : " & Channel
        Channels.add(Channel)
        IrcThing.join(Channel, Key)
    return nil

proc PartChannel(Event : TIrcEvent) : string =
    let Tokens = TokenizeMessage(Event)
    if (len Tokens) < 2:
        echo "(EE) PartChannel : Improper format"
        return nil

    let Channel = Tokens[1]

    if Channel in Channels:
        echo "(II) PartChannel : " & Channel
        IrcThing.part(Channel, "")
        Channels.delete(find(Channels, Channel))
    return

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
        
proc JErKOff(Event : TIrcEvent) : string =
    return JeRkLiNEs[random(JerKLiNes.high)]

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
            if Event.cmd == MPrivMsg:
                HandlePrivMsg(Event)
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
            let OutputMessage = CommandProc(Event)
            if OutputMessage != nil:
                IrcThing.send(
                    "PRIVMSG " & Event.origin & " :" & CommandProc(Event)
                )
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
            let OutputMessage = CommandProc(Event)
            if OutputMessage != nil:
                IrcThing.send(
                    "PRIVMSG " & Event.origin & " :" & CommandProc(Event)
                )
        else:
            echo "(II) Unauthorized attempt for command '" & Command & "'"
            return

