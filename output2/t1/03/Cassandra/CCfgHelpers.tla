------------------------------- MODULE CCfgHelpers -------------------------------

EXTENDS CCore

WriteConsistencyFactorCfg ==
    [ks \in Keyspaces |-> 2]

ReplicationFactorCfg ==
    [ks \in Keyspaces |-> 3]

InitialReplicasCfg ==
    [s \in Shards |-> Nodes]

PartitionShardCfg ==
    [pt \in Partitions |-> CHOOSE s \in Shards : TRUE]

PartitionKeyspaceCfg ==
    [pt \in Partitions |-> CHOOSE ks \in Keyspaces : TRUE]

ShardKeyspaceCfg ==
    [s \in Shards |-> CHOOSE ks \in Keyspaces : TRUE]

=============================================================================
