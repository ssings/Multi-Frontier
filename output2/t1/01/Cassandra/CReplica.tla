------------------------------- MODULE CReplica --------------------------------

EXTENDS CWrite

RequiredReads(ks, level) ==
    LET rf == replicationFactor[ks] IN
    CASE level = "ONE"     -> 1
      [] level = "QUORUM"   -> rf \div 2 + 1
      [] level = "ALL"      -> rf

ReplicaContains(d) ==
    {r \in replicaSet[TokenRangeOf(d)] : d \in replicaHas[r]}

Visible(d, level) ==
    Cardinality(ReplicaContains(d)) >= RequiredReads(KeyspaceOf(d), level)

ReplicaTypeOK == TRUE

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
