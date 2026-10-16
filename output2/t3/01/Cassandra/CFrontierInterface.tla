------------------------------- MODULE CFrontierInterface -------------------------------

EXTENDS CQuery

WriteFrontier == writeRequested

CommitFrontier == committed

ReplicaFrontier(r) == replicaHas[r]

QueryFrontier(level) ==
    {d \in CommitFrontier : Visible(d, level)}

MigrateFrontier ==
    {d \in CommitFrontier : MigrationSafe(d)}

FinalQueryFrontier(principal, keyspace, level) ==
    {d \in QueryFrontier(level) :
        /\ dataItemKeyspace(d) = keyspace
        /\ CanAccess(principal, keyspace, "Read")
        /\ d \in MigrateFrontier}

FrontierSafety ==
    /\ CommitFrontier \subseteq WriteFrontier
    /\ \A r \in Replicas : ReplicaFrontier(r) \subseteq WriteFrontier
    /\ \A l \in {"ONE", "QUORUM", "ALL"} : QueryFrontier(l) \subseteq CommitFrontier
    /\ MigrateFrontier \subseteq CommitFrontier
    /\ \A p \in Principals, k \in Keyspaces, l \in {"ONE", "QUORUM", "ALL"} :
        FinalQueryFrontier(p, k, l) \subseteq QueryFrontier(l)
        /\ FinalQueryFrontier(p, k, l) \subseteq MigrateFrontier

=============================================================================
