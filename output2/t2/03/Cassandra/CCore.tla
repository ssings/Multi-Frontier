------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals, FiniteSets

CONSTANTS
    Nodes,
    Principals,
    Keyspaces,
    Shards,
    Partitions,
    initialReplicas,
    replicationFactor,
    writeConsistencyFactor,
    partitionShard,
    partitionKeyspace,
    shardKeyspace

ReadConsistencyLevels == {"One", "Quorum", "All"}

CoreAssumption ==
    /\ Nodes # {}
    /\ Principals # {}
    /\ Keyspaces # {}
    /\ Shards # {}
    /\ Partitions # {}
    /\ DOMAIN initialReplicas = Shards
    /\ \A sh \in Shards : initialReplicas[sh] \in SUBSET Nodes
    /\ \A sh \in Shards : initialReplicas[sh] # {}
    /\ \A ks \in Keyspaces :
        /\ replicationFactor[ks] \in Nat \ {0}
        /\ writeConsistencyFactor[ks] \in Nat \ {0}
        /\ writeConsistencyFactor[ks] <= replicationFactor[ks]
    /\ DOMAIN partitionShard = Partitions
    /\ \A pt \in Partitions : partitionShard[pt] \in Shards
    /\ DOMAIN partitionKeyspace = Partitions
    /\ \A pt \in Partitions : partitionKeyspace[pt] \in Keyspaces
    /\ DOMAIN shardKeyspace = Shards
    /\ \A sh \in Shards : shardKeyspace[sh] \in Keyspaces
    /\ \A pt \in Partitions : partitionKeyspace[pt] = shardKeyspace[partitionShard[pt]]
    /\ \A sh \in Shards : Cardinality(initialReplicas[sh]) = replicationFactor[shardKeyspace[sh]]

PartitionsOfShard(sh) ==
    {pt \in Partitions : partitionShard[pt] = sh}

PartitionsOfKeyspace(ks) ==
    {pt \in Partitions : partitionKeyspace[pt] = ks}

CoreTypeOK ==
    CoreAssumption

=============================================================================
