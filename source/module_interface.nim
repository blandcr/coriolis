#==--- Coriolis Module Interface -------------------------------------------==##

##==--- Types

type
    TActionType* {.pure.} = enum
        PrivMsg,
        Notice,
        Join,
        Part,
        Close,
        Connect,
        Reconnect,
        SendRaw

    TCommandAction* = object
        Action*    : TActionType
        Arguments* : seq[string]
        Immediate* : bool
    
    TCommandRet* = seq[TCommandAction]

    TCommandArgs* = object
        Source*    : string
        Channel*   : string
        Arguments* : string

    TCommandProc* = proc(Args : TCommandArgs) : TCommandRet

    TCommandEntry* = object
        Proc* : TCommandProc
        Key*  : string
        Info* : string
        Help* : seq[string]

