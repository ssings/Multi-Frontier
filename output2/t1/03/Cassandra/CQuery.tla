------------------------------- MODULE CQuery -------------------------------

EXTENDS CReplica

SearchEligibleSet(p, ks, lv) ==
    { pt \in Partitions :
        /\ partitionKeyspace[pt] = ks
        /\ CanAccess(p, ks, "Read")
        /\ pt \in applied
        /\ Visible(pt, lv) }

Query(p, ks, lv) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ lv \in ReadConsistencyLevels
    /\ CanAccess(p, ks, "Read")
    /\ LET res == SearchEligibleSet(p, ks, lv) IN
       lastQuery' = [principal |-> p, keyspace |-> ks, level |-> lv, result |-> res, authorized |-> TRUE]
    /\ UNCHANGED <<permission, lastWrite, lastMigrate, writeState, wal, applied, replicaHas, replicas>>

RejectQuery(p, ks, lv) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ lv \in ReadConsistencyLevels
    /\ ~CanAccess(p, ks, "Read")
    /\ lastQuery' = [principal |-> p, keyspace |-> ks, level |-> lv, result |-> {}, authorized |-> FALSE]
    /\ UNCHANGED <<permission, lastWrite, lastMigrate, writeState, wal, applied, replicaHas, replicas>>

QueryResultComplete ==
    \/ lastQuery.authorized = FALSE
    \/ lastQuery.result = SearchEligibleSet(lastQuery.principal, lastQuery.keyspace, lastQuery.level)

=============================================================================
