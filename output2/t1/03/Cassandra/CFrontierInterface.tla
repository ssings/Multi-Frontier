------------------------- MODULE CFrontierInterface -------------------------

EXTENDS CMigrate

WriteFrontier ==
    wal

CommitFrontier ==
    applied

ReplicaFrontier(n) ==
    replicaHas[n]

QueryFrontier(lv) ==
    {pt \in CommitFrontier : Visible(pt, lv)}

MigrateFrontier ==
    CommitFrontier

FinalQueryFrontier(p, ks, lv) ==
    {pt \in Partitions :
        /\ CanAccess(p, ks, "Read")
        /\ pt \in QueryFrontier(lv)
        /\ partitionKeyspace[pt] = ks}

FrontierSafety ==
    /\ CommitFrontier \subseteq WriteFrontier
    /\ \A n \in Nodes : ReplicaFrontier(n) \subseteq WriteFrontier
    /\ \A lv \in ReadConsistencyLevels : QueryFrontier(lv) \subseteq CommitFrontier
    /\ \A p \in Principals, ks \in Keyspaces, lv \in ReadConsistencyLevels :
        FinalQueryFrontier(p, ks, lv) \subseteq QueryFrontier(lv)

SearchFrontierEquivalence ==
    \A p \in Principals, ks \in Keyspaces, lv \in ReadConsistencyLevels :
        FinalQueryFrontier(p, ks, lv) = SearchEligibleSet(p, ks, lv)

QuerySafety ==
    /\ (lastQuery.authorized = TRUE) =>
        lastQuery.result = SearchEligibleSet(lastQuery.principal, lastQuery.keyspace, lastQuery.level)
    /\ QueryResultComplete

=============================================================================
