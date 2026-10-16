------------------------------- MODULE CRead -------------------------------

EXTENDS CMigrate

VARIABLES
    readResult,
    lastRead

ReadVars == <<readResult, lastRead>>

LastReadT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      keyspace   : Keyspaces,
      level      : ReadConsistencyLevels,
      result     : SUBSET Records,
      authorized : BOOLEAN,
      executed   : BOOLEAN ]

ReadTypeOK ==
    /\ readResult \in SUBSET Records
    /\ lastRead \in LastReadT

InitRead ==
    /\ readResult = {}
    /\ lastRead = [kind |-> "None",
                   principal |-> CHOOSE p \in Principals : TRUE,
                   keyspace |-> CHOOSE ks \in Keyspaces : TRUE,
                   level |-> "One",
                   result |-> {},
                   authorized |-> FALSE,
                   executed |-> FALSE]

ReadEligibleSet(p, ks, level) ==
    {r \in Records :
        /\ recordKeyspace[r] = ks
        /\ CanAccess(p, ks, "Read")
        /\ r \in applied
        /\ Visible(r, level)
        /\ MigrationSafe(r)}

Read(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ CanAccess(p, ks, "Read")
    /\ readResult' = ReadEligibleSet(p, ks, level)
    /\ lastRead' = [kind |-> "Some", principal |-> p, keyspace |-> ks,
                    level |-> level, result |-> ReadEligibleSet(p, ks, level),
                    authorized |-> TRUE, executed |-> TRUE]
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>

RejectRead(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ ~CanAccess(p, ks, "Read")
    /\ readResult' = {}
    /\ UNCHANGED <<lastRead>>
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>

NextRead ==
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        Read(p, ks, level)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        RejectRead(p, ks, level)

=============================================================================
