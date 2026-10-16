------------------------------- MODULE CQuery -------------------------------

EXTENDS CReplica

SearchEligibleSet(p, ks, level) ==
    {pt \in Partitions :
        /\ partitionKeyspace[pt] = ks
        /\ CanAccess(p, ks, "Read")
        /\ pt \in applied
        /\ Visible(pt, level)}

Query(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ CanAccess(p, ks, "Read")
    /\ LET resultSet == SearchEligibleSet(p, ks, level) IN
        /\ lastQuery' = [authorized |-> TRUE, principal |-> p, keyspace |-> ks, level |-> level, result |-> resultSet]
    /\ UNCHANGED <<permission, writeState, wal, applied, replicaHas, replicas, lastWrite, lastMigrate>>

QuerySafetyInv ==
    /\ lastQuery.authorized = TRUE =>
           lastQuery.result = SearchEligibleSet(lastQuery.principal,
                                                lastQuery.keyspace,
                                                lastQuery.level)
    /\ lastQuery.result \subseteq
           {pt \in Partitions :
                /\ partitionKeyspace[pt] = lastQuery.keyspace
                /\ CanAccess(lastQuery.principal, lastQuery.keyspace, "Read")
                /\ pt \in applied
                /\ Visible(pt, lastQuery.level)}

=============================================================================
