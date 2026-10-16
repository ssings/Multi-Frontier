--------------------------- MODULE QCfgHelpers ---------------------------

EXTENDS QCore

\* This is a fixed experiment-support module.
\* It is not generated or modified by the LLM.

OnlyShard ==
    CHOOSE s \in Shards : TRUE

OnlyCollection ==
    CHOOSE c \in Collections : TRUE

WriteConsistencyFactorCfg ==
    [c \in Collections |-> 2]

ReplicasCfg ==
    [s \in Shards |-> Replicas]

IsInjectiveOn(f, domainSet) ==
    \A x \in domainSet :
        \A y \in domainSet :
            f[x] = f[y] => x = y

ReplicaNodeCfg ==
    CHOOSE f \in [Replicas -> Nodes] :
        IsInjectiveOn(f, Replicas)

PointShardCfg ==
    [pt \in Points |-> OnlyShard]

PointCollectionCfg ==
    [pt \in Points |-> OnlyCollection]

ShardCollectionCfg ==
    [s \in Shards |-> OnlyCollection]

=============================================================================
