------------------------------- MODULE CHelpers -------------------------------

EXTENDS CCore

InitialReplicasCfg == [sh \in Shards |-> Nodes]
ReplicationFactorCfg == [ks \in Keyspaces |-> 3]
WriteConsistencyFactorCfg == [ks \in Keyspaces |-> 2]
PartitionShardCfg == [pt \in Partitions |-> (CHOOSE sh \in Shards : TRUE)]
PartitionKeyspaceCfg == [pt \in Partitions |-> (CHOOSE ks \in Keyspaces : TRUE)]
ShardKeyspaceCfg == [sh \in Shards |-> (CHOOSE ks \in Keyspaces : TRUE)]

=============================================================================
