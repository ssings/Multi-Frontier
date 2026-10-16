------------------------------- MODULE CReplica -------------------------------

EXTENDS CWrite

ReplicaContains(pt) == {n \in Nodes : pt \in replicaHas[n]}

replicasOfShard(sh) == replicas[sh]

Visible(pt, level) ==
    CASE level = "One" ->
        Cardinality(ReplicaContains(pt)) >= 1
    [] level = "Quorum" ->
        2 * Cardinality(ReplicaContains(pt)) > Cardinality(replicas[recordPartition[pt]])
    [] level = "All" ->
        ReplicaContains(pt) = replicas[recordPartition[pt]

=============================================================================
