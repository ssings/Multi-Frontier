------------------------- MODULE CFrontierInterface -------------------------

EXTENDS CQuery

WriteFrontier == writeRequested

CommitFrontier == committed

ReplicaFrontier(r) == replicaHas[r]

QueryFrontier(level) ==
    {d \in CommitFrontier : Visible(d, level)}

MigrateFrontier ==
    {d \in CommitFrontier : MigrationSafe(d)}

FinalQueryFrontier(p, ks, level) ==
    SearchEligibleSet(p, ks, level)

FrontierSafety ==
    /\ CommitFrontier \subseteq WriteFrontier
    /\ \A r \in Replicas : ReplicaFrontier(r) \subseteq WriteFrontier
    /\ \A level \in ReadConsistencyLevels :
        QueryFrontier(level) \subseteq CommitFrontier
    /\ MigrateFrontier \subseteq CommitFrontier
    /\ \A p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        FinalQueryFrontier(p, ks, level) \subseteq
            QueryFrontier(level) \cap MigrateFrontier
    /\ \A p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        FinalQueryFrontier(p, ks, level) =
        {d \in CommitFrontier :
            /\ tableKeyspace[dataItemTable[d]] = ks
            /\ CanAccess(p, ks, "Read")
            /\ d \in QueryFrontier(level)
            /\ d \in MigrateFrontier}

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
