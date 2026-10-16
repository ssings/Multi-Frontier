------------------------------ MODULE QReplica ------------------------------

EXTENDS QWrite

\* This module introduces no new variables.
\* It defines replica-level visibility operators.

\* Replicas that currently hold point pt
ReplicaContains(pt) ==
    {r \in ReplicasOfPoint(pt) : pt \in replicaHas[r]}

\* Visibility predicates for read consistency levels
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

ReplicaTypeOK ==
    TRUE   \* no extra state variables to check

=============================================================================
