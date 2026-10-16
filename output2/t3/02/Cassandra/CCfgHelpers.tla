---------------------------- MODULE CCfgHelpers ----------------------------

EXTENDS CCore

\* This is a fixed experiment-support module.
\* It is not generated or modified by the LLM.

OnlyPartition ==
    CHOOSE p \in Partitions : TRUE

OnlyKeyspace ==
    CHOOSE ks \in Keyspaces : TRUE

IsInjectiveOn(f, domainSet) ==
    \A x \in domainSet :
        \A y \in domainSet :
            f[x] = f[y] => x = y

RecordPartitionCfg ==
    [r \in Records |-> OnlyPartition]

RecordKeyspaceCfg ==
    [r \in Records |-> OnlyKeyspace]

PartitionKeyspaceCfg ==
    [p \in Partitions |-> OnlyKeyspace]

ReplicationFactorCfg ==
    [ks \in Keyspaces |-> 2]

WriteConsistencyFactorCfg ==
    [ks \in Keyspaces |-> 2]

ReplicasCfg ==
    [p \in Partitions |-> Replicas]

ReplicaNodeCfg ==
    LET n1 == CHOOSE n \in Nodes : TRUE
        n2 == CHOOSE n \in Nodes \ {n1} : TRUE
        n3 == CHOOSE n \in Nodes \ {n1, n2} : TRUE
    IN [Rep1 |-> n1, Rep2 |-> n2, Rep3 |-> n3]
====
