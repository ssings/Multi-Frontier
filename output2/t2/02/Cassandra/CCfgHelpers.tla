----------------------------- MODULE CCfgHelpers -----------------------------

EXTENDS CCore

OnlyKeyspace ==
    CHOOSE ks \in Keyspaces : TRUE

OnlyPartition ==
    CHOOSE p \in Partitions : TRUE

WriteConsistencyFactorCfg ==
    [ks \in Keyspaces |-> 2]

ReplicationFactorCfg ==
    [ks \in Keyspaces |-> 3]

ReplicasCfg ==
    [p \in Partitions |-> Replicas]

IsInjectiveOn(f, domainSet) ==
    \A x \in domainSet :
        \A y \in domainSet :
            f[x] = f[y] => x = y

ReplicaNodeCfg ==
    CHOOSE f \in [Replicas -> Nodes] :
        IsInjectiveOn(f, Replicas)

RecordPartitionCfg ==
    [r \in Records |-> OnlyPartition]

RecordKeyspaceCfg ==
    [r \in Records |-> OnlyKeyspace]

PartitionKeyspaceCfg ==
    [p \in Partitions |-> OnlyKeyspace]

=============================================================================
