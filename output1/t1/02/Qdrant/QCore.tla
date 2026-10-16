--------------------------- MODULE QCore ---------------------------

EXTENDS Naturals

(********************************************
 * Qdrant Core: Constants, sets, and helpers.
 ********************************************)

CONSTANTS
    Principals,
    Nodes,
    Shards,
    Collections,
    Points,
    Replicas,
    writeConsistencyFactor,
    replicas,
    replicaNode,
    pointShard,
    pointCollection,
    shardCollection

Operations == {"Read", "Write", "Manage", "Migrate"}
ReadConsistencyLevels == {"One", "Majority", "All"}
WriteStates == {"None", "WalLogged", "Applied"}
MigrateStates == {"Stable", "Migratering", "Activated"}

CollectionOfShard(s) == shardCollection[s]
PointsOfShard(s) == {pt \in Points : pointShard[pt] = s}
ReplicasOfPoint(pt) == replicas[pointShard[pt]]

HasMajority(owned, all) ==
    2 * Cardinality(owned) > Cardinality(all)

CoreAssumption ==
    /\ Principals # {}
    /\ Nodes # {}
    /\ Shards # {}
    /\ Collections # {}
    /\ Points # {}
    /\ Replicas # {}
    /\ writeConsistencyFactor \in [Collections -> Nat]
    /\ \A c \in Collections : writeConsistencyFactor[c] >= 1
    /\ replicas \in [Shards -> SUBSET Replicas]
    /\ \A s \in Shards : replicas[s] # {}
    /\ replicaNode \in [Replicas -> Nodes]
    /\ pointShard \in [Points -> Shards]
    /\ pointCollection \in [Points -> Collections]
    /\ shardCollection \in [Shards -> Collections]
    /\ \A pt \in Points : pointCollection[pt] = shardCollection[pointShard[pt]]

CoreTypeOK ==
    CoreAssumption

=============================================================================
