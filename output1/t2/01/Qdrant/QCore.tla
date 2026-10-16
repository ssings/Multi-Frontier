-------------------------------- MODULE QCore --------------------------------

EXTENDS Naturals, FiniteSets

\*  model constants (values provided by QCfgHelpers and Qdrant.cfg)
CONSTANTS
    Principals,    \* Set of principals
    Nodes,         \* Set of nodes
    Shards,        \* Set of shards
    Collections,   \* Set of collections
    Points,        \* Set of points
    Replicas,      \* Set of replica identifiers (objects)
    writeConsistencyFactor, \* [Collections -> Nat]
    replicas,               \* [Shards -> SUBSET Replicas]
    replicaNode,            \* [Replicas -> Nodes]
    pointShard,             \* [Points -> Shards]
    pointCollection,        \* [Points -> Collections]
    shardCollection          \* [Shards -> Collections]


Operations == {"Read", "Write", "Manage", "Migrate"}
ReadConsistencyLevels == {"One", "Majority", "All"}
WriteStates == {"None", "WalLogged", "Applied"}
MigrateStates == {"Stable", "Migratering", "Activated"}

\* Derived helper operators
CollectionOfShard(s) ==
    shardCollection[s]

PointsOfShard(s) ==
    {pt \in Points : pointShard[pt] = s}

ReplicasOfPoint(pt) ==
    replicas[pointShard[pt]]

HasMajority(owned, all) ==
    2 * Cardinality(owned) > Cardinality(all)

\* Core assumptions that must hold in every state
CoreAssumption ==
    /\ Principals # {}
    /\ Nodes # {}
    /\ Shards # {}
    /\ Collections # {}
    /\ Points # {}
    /\ Replicas # {}
    /\ \A pt \in Points : pointCollection[pt] = shardCollection[pointShard[pt]]
    /\ \A s \in Shards : replicas[s] # {}
    /\ \A c \in Collections : writeConsistencyFactor[c] >= 1
    /\ \A pt \in Points : \A r \in replicas[pointShard[pt]] : r \in Replicas
    /\ \A r \in Replicas : replicaNode[r] \in Nodes

\* Type invariant covering static model objects
CoreTypeOK ==
    /\ writeConsistencyFactor \in [Collections -> Nat]
    /\ replicas \in [Shards -> SUBSET Replicas]
    /\ replicaNode \in [Replicas -> Nodes]
    /\ pointShard \in [Points -> Shards]
    /\ pointCollection \in [Points -> Collections]
    /\ shardCollection \in [Shards -> Collections]

=============================================================================
