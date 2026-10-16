------------------------------ MODULE CReplica ------------------------------

EXTENDS CWrite

ReplicaContains(pt) ==
    {n \in replicas[partitionShard[pt]] : pt \in replicaHas[n]}

Visible(pt, "One") ==
    Cardinality(ReplicaContains(pt)) >= 1

Visible(pt, "Quorum") ==
    LET repCount == Cardinality(replicas[partitionShard[pt]]) IN
    2 * Cardinality(ReplicaContains(pt)) > repCount

Visible(pt, "All") ==
    ReplicaContains(pt) = replicas[partitionShard[pt]]

=============================================================================
