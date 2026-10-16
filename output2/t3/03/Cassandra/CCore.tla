------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals, FiniteSets

CONSTANTS
    Nodes,
    Principals,
    Keyspaces,
    Shards,
    Partitions,
    writeConsistencyFactor,
    initialReplicas,
    partitionShard,
    partitionKeyspace,
    shardKeyspace

ReadConsistencyLevels == {"One", "Quorum", "All"}
Operations == {"Read", "Write", "Manage", "Migrate"}

CoreAssumption ==
    /\ Nodes # {}
    /\ Principals # {}
    /\ Keyspaces # {}
    /\ Shards # {}
    /\ Partitions # {}
    /\ \A ks \in Keyspaces : writeConsistencyFactor[ks] \in Nat \ {0}
    /\ \A sh \in Shards : initialReplicas[sh] \subseteq Nodes
    /\ \A sh \in Shards : initialReplicas[sh] # {}
    /\ \A pt \in Partitions : partitionShard[pt] \in Shards
    /\ \A pt \in Partitions : partitionKeyspace[pt] \in Keyspaces
    /\ \A sh \in Shards : shardKeyspace[sh] \in Keyspaces
    /\ \A pt \in Partitions : partitionKeyspace[pt] = shardKeyspace[partitionShard[pt]]

CoreTypeOK == CoreAssumption

=============================================================================
