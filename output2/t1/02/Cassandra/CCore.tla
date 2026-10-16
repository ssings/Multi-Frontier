------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals, FiniteSets

CONSTANTS
    Principals,
    Keyspaces,
    Records,
    Partitions,
    Replicas,
    Nodes,
    replicaNode,
    replicas,
    recordPartition,
    recordKeyspace,
    partitionKeyspace,
    replicationFactor,
    writeConsistencyFactor,
    ReadConsistencyLevels

Operations == {"Read", "Write", "Manage", "Migrate"}

PartitionRecords(p) == {r \in Records : recordPartition[r] = p}

CoreAssumption ==
    /\ Principals # {}
    /\ Keyspaces # {}
    /\ Records # {}
    /\ Partitions # {}
    /\ Replicas # {}
    /\ Nodes # {}
    /\ ReadConsistencyLevels = {"One", "Quorum", "All"}
    /\ replicaNode \in [Replicas -> Nodes]
    /\ replicas \in [Partitions -> SUBSET Replicas]
    /\ \A p \in Partitions : replicas[p] # {}
    /\ recordPartition \in [Records -> Partitions]
    /\ recordKeyspace \in [Records -> Keyspaces]
    /\ partitionKeyspace \in [Partitions -> Keyspaces]
    /\ \A r \in Records : recordKeyspace[r] = partitionKeyspace[recordPartition[r]]
    /\ replicationFactor \in [Keyspaces -> Nat]
    /\ writeConsistencyFactor \in [Keyspaces -> Nat]
    /\ \A ks \in Keyspaces :
        /\ 1 <= writeConsistencyFactor[ks]
        /\ writeConsistencyFactor[ks] <= replicationFactor[ks]
        /\ replicationFactor[ks] <= Cardinality(Replicas)   \* reasonable bound

CoreTypeOK == TRUE

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
