----------------------------- MODULE CReplica ------------------------------

EXTENDS CWrite

ReplicaContains(pt) ==
    {n \in replicas[partitionShard[pt]] : pt \in replicaHas[n]}

Visible(pt, level) ==
    CASE level = "One"     -> Cardinality(ReplicaContains(pt)) >= 1
      [] level = "Quorum"  -> 2 * Cardinality(ReplicaContains(pt)) > Cardinality(replicas[partitionShard[pt]])
      [] level = "All"     -> ReplicaContains(pt) = replicas[partitionShard[pt]]

=============================================================================
