------------------------------- MODULE CRead -------------------------------

EXTENDS CMigrate

VARIABLES
    readResult,
    lastRead

ReadVars == <<readResult, lastRead>>

ReadRecordT == [
    kind       : {"None", "Read"},
    principal  : Principals,
    keyspace   : Keyspaces,
    level      : ReadConsistencyLevels,
    result     : SUBSET Records,
    authorized : BOOLEAN,
    executed   : BOOLEAN
]

InitRead ==
    /\ readResult = {}
    /\ lastRead = [
        kind |-> "None",
        principal |-> CHOOSE p \in Principals : TRUE,
        keyspace |-> CHOOSE ks \in Keyspaces : TRUE,
        level |-> CHOOSE l \in ReadConsistencyLevels : TRUE,
        result |-> {},
        authorized |-> FALSE,
        executed |-> FALSE
        ]

ReadEligibleSet(p, ks, level) ==
    {r \in Records : (recordKeyspace[r] = ks) /\ (CanAccess(p, ks, "Read")) /\ (r \in applied) /\ (Visible(r, level)) /\ (MigrationSafe(r))}

Read(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ CanAccess(p, ks, "Read")
    /\ readResult' = ReadEligibleSet(p, ks, level)
    /\ lastRead' = [
        kind |-> "Read",
        principal |-> p,
        keyspace |-> ks,
        level |-> level,
        result |-> readResult',
        authorized |-> TRUE,
        executed |-> TRUE
        ]

RejectRead(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ ~CanAccess(p, ks, "Read")
    /\ readResult' = {}
    /\ lastRead' = [
        kind |-> "Read",
        principal |-> p,
        keyspace |-> ks,
        level |-> level,
        result |-> {},
        authorized |-> FALSE,
        executed |-> TRUE
        ]

ReadTypeOK ==
    /\ readResult \subseteq Records
    /\ lastRead \in ReadRecordT

=============================================================================
