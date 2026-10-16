------------------------------ MODULE CReplica ------------------------------

EXTENDS CWrite

ReplicaContains(r) ==
    {rep \in replicas[recordPartition[r]] : r \in replicaHas[rep]}

Visible(r, "One") ==
    Cardinality(ReplicaContains(r)) >= 1

Visible(r, "Quorum") ==
    2 * Cardinality(ReplicaContains(r)) > Cardinality(replicas[recordPartition[r]])

Visible(r, "All") ==
    ReplicaContains(r) = replicas[recordPartition[r]]

ReplicaTypeOK == TRUE

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
