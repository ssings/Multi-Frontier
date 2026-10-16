----------------------------- MODULE CCfgHelpers -----------------------------

EXTENDS CCore

\* Helper definitions for Cassandra model constants.
\* This module is referenced by CIntegrated and provides deterministic
\* assignments for all function-typed constants.

\* Replicas to Node mapping: one injective assignment.
ReplicaNodeCfg ==
    [ r \in Replicas |->
        CASE r = "Rep1" -> "Node1"
          [] r = "Rep2" -> "Node2"
          [] r = "Rep3" -> "Node3"
    ]

\* Every partition uses all replicas.
ReplicasCfg ==
    [ p \in Partitions |-> Replicas ]

\* Every record belongs to the single partition.
RecordPartitionCfg ==
    [ r \in Records |-> "Part1" ]

\* Every record belongs to the single keyspace.
RecordKeyspaceCfg ==
    [ r \in Records |-> "KS1" ]

\* The only partition is owned by the only keyspace.
PartitionKeyspaceCfg ==
    [ p \in Partitions |-> "KS1" ]

\* Replication factor for the keyspace.
ReplicationFactorCfg ==
    [ ks \in Keyspaces |-> 3 ]

\* Write consistency factor: quorum needs 2 out of 3 replicas.
WriteConsistencyFactorCfg ==
    [ ks \in Keyspaces |-> 2 ]

=============================================================================
