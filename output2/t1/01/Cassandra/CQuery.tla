------------------------------- MODULE CQuery --------------------------------

EXTENDS CMigrate

SearchEligibleSet(p, ks, level) ==
    {d \in committed :
        /\ tableKeyspace[dataItemTable[d]] = ks
        /\ CanAccess(p, ks, "Read")
        /\ Visible(d, level)
        /\ MigrationSafe(d)}

Query(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ CanAccess(p, ks, "Read")
    /\ lastQuery' = [kind |-> "Some", principal |-> p,
                     keyspace |-> ks, level |-> level,
                     result |-> SearchEligibleSet(p, ks, level),
                     authorized |-> TRUE]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastMigrate>>

RejectQuery(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ ~CanAccess(p, ks, "Read")
    /\ lastQuery' = [kind |-> "Some", principal |-> p,
                     keyspace |-> ks, level |-> level,
                     result |-> {},
                     authorized |-> FALSE]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastMigrate>>

QueryTypeOK ==
    lastQuery \in [kind: {"None","Some"}, principal: Principals,
                   keyspace: Keyspaces, level: ReadConsistencyLevels,
                   result: SUBSET DataItems, authorized: BOOLEAN]

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
