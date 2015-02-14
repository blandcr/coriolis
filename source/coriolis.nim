import iRc, sTrUtIlS, mATH

# TODO(blandcr) - accept these as command line arguments

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

proc HandlePrivMsg(Event : TIrcEvent)
proc HandleAuth(Tokens : seq[string], Nick : string)
proc JErKOff(Tokens : seq[string], Channel : string)
proc HandleExit(Tokens : seq[string])
proc JoinChannel(Tokens : seq[string])
proc PartChannel(Tokens : seq[string])

var
    IrcServer = "irc.efnet.net"
    Channels  = @["#corgifreezer"]
    Name      = "coriolis"

var IrcThing = newIrc(
    address   = IrcServer,
    nick      = Name,
    user      = Name,
    realname  = Name,
    joinChans = Channels
)

IrcThing.connect()

var AuthorizedNicks : seq[string] = @[]

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
    
    let ElevatedCommands : seq[string] = @[ "!quit",
                                            "!join",
                                            "!part"  ]

    let Message = Event.params[Event.params.high]

    if (len Message) < 1:
        echo "(II) HandleMessage : nil message handled"
        return

    if Message[0] == '!':
        let Tokens = split(Message, " ")

        if (len Tokens) < 1:
            echo "(EE) HandleMessage : nil command!"
            return

        let Command = Tokens[0]
        echo "(II) HandleMessage : Command : " & Command

        if Command in ElevatedCommands and not(Event.nick in AuthorizedNicks):
            echo "(II) HandleMessage : Unauthorized access!"
            return

        case Command
        of "!auth":
            HandleAuth(Tokens, Event.nick)
        of "!jerk":
            JeRKoFf(Tokens, Event.origin)
        of "!quit":
            HandleExit(Tokens)
        of "!join":
            JoinChannel(Tokens)
        of "!part":
            PartChannel(Tokens)
        else:
            echo "(II) Invalid command."
    return

proc JoinChannel(Tokens : seq[string]) =
    if (len Tokens) < 2:
        echo "(EE) JoinChannel : Improper format"
        return

    let Channel = Tokens[1]
    
    var Key = ""
    if (len Tokens) > 2:
        Key = Tokens[2]

    if Channel in Channels:
        echo "(II) JoinChannel : Already in this channel!"
    else:
        echo "(II) JoinChannel : " & Channel
        Channels.add(Channel)
        IrcThing.join(Channel, Key)
    return

proc PartChannel(Tokens : seq[string]) =
    if (len Tokens) < 2:
        echo "(EE) PartChannel : Improper format"
        return

    let Channel = Tokens[1]

    if Channel in Channels:
        echo "(II) PartChannel : " & Channel
        IrcThing.part(Channel, "")
        Channels.delete(find(Channels, Channel))
    return

proc HandleAuth(Tokens : seq[string], Nick : string) =
    if Tokens[1] == "CORGIFREEZER!":
        AuthorizedNicks.add(Nick)
    return

proc JErKOff(Tokens : seq[string], Channel : string) =
    send(IrCThinG, "PRIVMSG " & Channel & " :" & JeRkLiNEs[random(JerKLiNes.high)])
    return

proc HandleExit(Tokens : seq[string]) =
    send(IrcThing, "QUIT  :snerf borf", sendImmediately=true)
    close(IrcThing)
    quit(0)

