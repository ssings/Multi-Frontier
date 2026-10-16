------------------------------- MODULE CReplica -------------------------------

EXTENDS CWrite

ReplicaContains(r) ==
    {rep \in replicas[recordPartition[r]] : r \in replicaHas[rep]}

Visible(r, level) ==
    CASE level = "One" ->
        Cardinality(ReplicaContains(r)) >= 1
    [] level = "Quorum" ->
        LET reps == replicas[recordPartition[r]] IN
        2 * Cardinality(ReplicaContains(r)) > Cardinality(reps)
    [] level = "All" ->
        ReplicaContains(r) = replicas[recordPartition[r]]

=============================================================================
