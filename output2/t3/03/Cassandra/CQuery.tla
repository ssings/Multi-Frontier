------------------------------- MODULE CQuery -------------------------------

EXTENDS CReplica

VARIABLES searchResult

QueryVars == <<searchResult>>

SearchEligibleSet(p, ks, level) ==
    {pt \in Partitions :
        /\ partitionKeyspace[pt] = ks
        /\ CanAccess(p, ks, "Read")
        /\ pt \in applied
        /\ Visible(pt, level)}

QueryTypeOK ==
    /\ searchResult \in SUBSET Partitions

InitQuery ==
    /\ searchResult = {}

Query(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ CanAccess(p, ks, "Read")
    /\ LET eligible == SearchEligibleSet(p, ks, level) IN
        searchResult' = eligible
    /\ lastQuery' = [ kind |-> "Query", principal |-> p, keyspace |-> ks, op |-> "Read", level |-> level, authorized |-> TRUE ]
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas, lastWrite, lastMigrate>>

RejectQuery(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ ~CanAccess(p, ks, "Read")
    /\ searchResult' = {}
    /\ lastQuery' = [ kind |-> "Query", principal |-> p, keyspace |-> ks, op |-> "Read", level |-> level, authorized |-> FALSE ]
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas, lastWrite, lastMigrate>>

NextQuery ==
    \/ \E p \in Principals :
        \E ks \in Keyspaces :
            \E level \in ReadConsistencyLevels :
                Query(p, ks, level)
    \/ \E p \in Principals :
        \E ks \in Keyspaces :
            \E level \in ReadConsistencyLevels :
                RejectQuery(p, ks, level)

=============================================================================
