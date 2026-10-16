------------------------------- MODULE CQuery -------------------------------

EXTENDS CMigrate

SearchEligibleSet(principal, keyspace, level) ==
    {d \in DataItems :
        /\ dataItemKeyspace(d) = keyspace
        /\ CanAccess(principal, keyspace, "Read")
        /\ d \in committed
        /\ Visible(d, level)
        /\ MigrationSafe(d)}

Query(principal, keyspace, level) ==
    /\ principal \in Principals
    /\ keyspace \in Keyspaces
    /\ level \in {"ONE", "QUORUM", "ALL"}
    /\ CanAccess(principal, keyspace, "Read")
    /\ lastQuery' = [ kind |-> "Some",
                      principal |-> principal,
                      keyspace |-> keyspace,
                      level |-> level,
                      result |-> SearchEligibleSet(principal, keyspace, level),
                      authorized |-> TRUE,
                      executed |-> TRUE ]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas,
                   currentReplicas, migrateState, migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastMigrate>>

RejectQuery(principal, keyspace, level) ==
    /\ principal \in Principals
    /\ keyspace \in Keyspaces
    /\ level \in {"ONE", "QUORUM", "ALL"}
    /\ ~CanAccess(principal, keyspace, "Read")
    /\ lastQuery' = [ kind |-> "None",
                      principal |-> principal,
                      keyspace |-> keyspace,
                      level |-> level,
                      result |-> {},
                      authorized |-> FALSE,
                      executed |-> FALSE ]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas,
                   currentReplicas, migrateState, migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastMigrate>>

=============================================================================
