------------------------------- MODULE CFrontierInterface -------------------------------

EXTENDS CRead

WriteFrontier == wal

CommitFrontier == applied

ReplicaFrontier(rep) == replicaHas[rep]

QueryFrontier(level) ==
    {r \in CommitFrontier : Visible(r, level)}

MigrateFrontier ==
    {r \in CommitFrontier : MigrationSafe(r)}

ReadFrontier(p, ks, level) == ReadEligibleSet(p, ks, level)

FrontierSafety ==
    /\ CommitFrontier \subseteq WriteFrontier
    /\ \A rep \in Replicas : ReplicaFrontier(rep) \subseteq WriteFrontier
    /\ \A level \in ReadConsistencyLevels : QueryFrontier(level) \subseteq CommitFrontier
    /\ MigrateFrontier \subseteq CommitFrontier
    /\ \A p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        ReadFrontier(p, ks, level) = ReadEligibleSet(p, ks, level)
    /\ (lastRead.authorized /\ lastRead.executed) =>
        lastRead.result = ReadFrontier(lastRead.principal, lastRead.keyspace, lastRead.level)

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
