------------------------- MODULE CFrontierInterface -------------------------

EXTENDS CQuery

WriteFrontier ==
    writeRequested

CommitFrontier ==
    committed

ReplicaFrontier(r) ==
    replicaHas[r]

QueryFrontier(level) ==
    {d \in committed : Visible(d, level)}

MigrateFrontier ==
    {d \in committed : MigrationSafe(d)}

FinalQueryFrontier(p, k, level) ==
    SearchEligibleSet(p, k, level)

FrontierSafety ==
    /\ CommitFrontier \subseteq WriteFrontier
    /\ \A r \in Replicas : ReplicaFrontier(r) \subseteq WriteFrontier
    /\ \A level \in ConsistencyLevels : QueryFrontier(level) \subseteq CommitFrontier
    /\ MigrateFrontier \subseteq CommitFrontier
    /\ \A p \in Principals, k \in Keyspaces, level \in ConsistencyLevels :
        FinalQueryFrontier(p, k, level) = SearchEligibleSet(p, k, level)

=============================================================================
