------------------------------- MODULE QCore -------------------------------

EXTENDS Naturals

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

\* Fixed enumerations
Operations == {"Read", "Write", "Manage", "Migrate"}
ReadConsistencyLevels == {"One", "Majority", "All"}
WriteStates == {"None", "WalLogged", "Applied"}
MigrateStates == {"Stable", "Migratering", "Activated"}

\* Helper operators
CollectionOfShard(s) == shardCollection[s]
PointsOfShard(s) == {pt \in Points : pointShard[pt] = s}
ReplicasOfPoint(pt) == replicas[pointShard[pt]]

HasMajority(owned, totalSet) ==
    2 * Cardinality(owned) > Cardinality(totalSet)

\* Type and structural assumptions
CoreAssumption ==
    /\ Principals # {}
    /\ Nodes # {}
    /\ Shards # {}
    /\ Collections # {}
    /\ Points # {}
    /\ Replicas # {}
    /\ DOMAIN writeConsistencyFactor = Collections
    /\ \A c \in Collections : writeConsistencyFactor[c] \in Nat /\ writeConsistencyFactor[c] >= 1
    /\ DOMAIN replicas = Shards
    /\ \A s \in Shards : replicas[s] \subseteq Replicas /\ replicas[s] # {}
    /\ DOMAIN replicaNode = Replicas
    /\ \A r \in Replicas : replicaNode[r] \in Nodes
    /\ DOMAIN pointShard = Points
    /\ \A pt \in Points : pointShard[pt] \in Shards
    /\ DOMAIN pointCollection = Points
    /\ \A pt \in Points : pointCollection[pt] \in Collections
    /\ DOMAIN shardCollection = Shards
    /\ \A s \in Shards : shardCollection[s] \in Collections
    /\ \A pt \in Points : pointCollection[pt] = shardCollection[pointShard[pt]]

CoreTypeOK == CoreAssumption

=============================================================================
