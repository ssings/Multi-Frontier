------------------------------- MODULE CCfgHelpers -------------------------------
CONSTANTS
    KS1, S1, N1, N2, N3, PT1, PT2

WriteConsistencyFactorCfg == [ks \in {KS1} |-> 2]
InitialReplicasCfg == [sh \in {S1} |-> {N1, N2, N3}]
PartitionShardCfg == [pt \in {PT1, PT2} |-> S1]
PartitionKeyspaceCfg == [pt \in {PT1, PT2} |-> KS1]
ShardKeyspaceCfg == [sh \in {S1} |-> KS1]
=============================================================================
