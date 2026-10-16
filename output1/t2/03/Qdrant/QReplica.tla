--------------------------- MODULE QReplica ---------------------------
EXTENDS QWrite

ReplicaContains(pt) ==
    {r \in replicas[pointShard[pt]] : pt \in replicaHas[r]}

ReplicaSelections ==
    {sel \in [Shards -> Replicas] :
        \A s \in Shards :
            sel[s] \in replicas[s]}

Visible(pt, level, sel) ==
    CASE level = "One" ->
        pt \in replicaHas[sel[pointShard[pt]]]
    [] level = "Majority" ->
        HasMajority(ReplicaContains(pt), ReplicasOfPoint(pt))
    [] level = "All" ->
        ReplicaContains(pt) = ReplicasOfPoint(pt)

ReplicaTypeOK == TRUE

=============================================================================
