------------------------------- MODULE CRead -------------------------------

EXTENDS CMigrate

VARIABLES
    readResult, lastRead

ReadVars == <<readResult, lastRead>>

ReadRecordT == [kind : {"None", "Some"},
                principal : Principals,
                keyspace : Keyspaces,
                level : ReadConsistencyLevels,
                result : SUBSET Records,
                authorized : BOOLEAN,
                executed : BOOLEAN]

InitRead ==
    /\ readResult = {}
    /\ lastRead = [kind |-> "None",
                   principal |-> CHOOSE p \in Principals : TRUE,
                   keyspace |-> CHOOSE ks \in Keyspaces : TRUE,
                   level |-> CHOOSE lvl \in ReadConsistencyLevels : TRUE,
                   result |-> {},
                   authorized |-> FALSE,
                   executed |-> FALSE]

ReadEligibleSet(p, ks, level) ==
    {r \in Records :
        /\ recordKeyspace[r] = ks
        /\ CanAccess(p, ks, "Read")
        /\ r \in applied
        /\ Visible(r, level)
        /\ MigrationSafe(r) }

Read(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ CanAccess(p, ks, "Read")
    /\ readResult' = ReadEligibleSet(p, ks, level)
    /\ lastRead' = [kind |-> "Some", principal |-> p, keyspace |-> ks, level |-> level,
                    result |-> readResult', authorized |-> TRUE, executed |-> TRUE]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData,
                  lastWrite, lastMigrate>>

RejectRead(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ ~CanAccess(p, ks, "Read")
    /\ readResult' = {}
    /\ lastRead' = [kind |-> "Some", principal |-> p, keyspace |-> ks, level |-> level,
                    result |-> readResult', authorized |-> FALSE, executed |-> FALSE]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData,
                  lastWrite, lastMigrate>>

NextRead ==
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        Read(p, ks, level)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        RejectRead(p, ks, level)

ReadTypeOK ==
    /\ readResult \subseteq Records
    /\ lastRead \in ReadRecordT

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
