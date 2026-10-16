------------------------ MODULE CFrontierInterface -------------------------

EXTENDS CMigrate

WriteFrontier == wal

CommitFrontier == applied

ReplicaFrontier(node) == replicaHas[node]

QueryFrontier(level) ==
    {pt \in CommitFrontier : Visible(pt, level)}

FinalQueryFrontier(p, ks, level) ==
    {pt \in Partitions :
        /\ CanAccess(p, ks, "Read")
        /\ pt \in QueryFrontier(level)
        /\ partitionKeyspace[pt] = ks}

SearchEligibleSetFromCore(p, ks, level) ==
    {pt \in Partitions :
        /\ partitionKeyspace[pt] = ks
        /\ CanAccess(p, ks, "Read")
        /\ pt \in applied
        /\ Visible(pt, level)}

FrontierSafety ==
    /\ CommitFrontier \subseteq WriteFrontier
    /\ \A n \in Nodes : ReplicaFrontier(n) \subseteq WriteFrontier
    /\ \A level \in ReadConsistencyLevels : QueryFrontier(level) \subseteq CommitFrontier
    /\ \A p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
          FinalQueryFrontier(p, ks, level) = SearchEligibleSetFromCore(p, ks, level)

=============================================================================
