------------------------------- MODULE CFrontierInterface -------------------------------

EXTENDS CMigrate

WriteFrontier == wal

CommitFrontier == applied

ReplicaFrontier(node) == replicaHas[node]

QueryFrontier(level) == {pt \in CommitFrontier : Visible(pt, level)}

MigrateFrontier == CommitFrontier

FinalQueryFrontier(p, ks, level) == SearchEligibleSet(p, ks, level)

FrontierSafety ==
    /\ CommitFrontier \subseteq WriteFrontier
    /\ \A node \in Nodes : ReplicaFrontier(node) \subseteq WriteFrontier
    /\ \A level \in ReadConsistencyLevels : QueryFrontier(level) \subseteq CommitFrontier
    /\ \A p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        FinalQueryFrontier(p, ks, level) = SearchEligibleSet(p, ks, level)

=============================================================================
