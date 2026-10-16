------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals, FiniteSets

CONSTANTS
    Principals,
    Keyspaces,
    Partitions,
    Records,
    Replicas,
    Nodes,
    recordPartition,   \* Records -> Partitions
    recordKeyspace,    \* Records -> Keyspaces
    partitionKeyspace, \* Partitions -> Keyspaces
    replicaNode,       \* Replicas -> Nodes
    replicas,          \* Partitions -> SUBSET Replicas
    replicationFactor, \* Keyspaces -> Nat
    writeConsistencyFactor \* Keyspaces -> Nat

Operations == {"Read", "Write", "Manage", "Migrate"}

MigrateStates == {"Stable", "Migratering", "Activated"}

ReadConsistencyLevels == {"One", "Quorum", "All"}

WriteStates == {"None", "CommitLogged", "Applied"}

PointsOfPartition(partition) ==
    {r \in Records : recordPartition[r] = partition}

CoreAssumption ==
    /\ Principals # {}
    /\ Keyspaces # {}
    /\ Partitions # {}
    /\ Records # {}
    /\ Replicas # {}
    /\ Nodes # {}
    /\ DOMAIN recordPartition = Records
    /\ \A r \in Records : recordPartition[r] \in Partitions
    /\ DOMAIN recordKeyspace = Records
    /\ \A r \in Records : recordKeyspace[r] \in Keyspaces
    /\ DOMAIN partitionKeyspace = Partitions
    /\ \A p \in Partitions : partitionKeyspace[p] \in Keyspaces
    /\ \A r \in Records : recordKeyspace[r] = partitionKeyspace[recordPartition[r]]
    /\ DOMAIN replicaNode = Replicas
    /\ \A r \in Replicas : replicaNode[r] \in Nodes
    /\ DOMAIN replicas = Partitions
    /\ \A p \in Partitions : replicas[p] \subseteq Replicas
    /\ \A p \in Partitions : replicas[p] # {}
    /\ DOMAIN replicationFactor = Keyspaces
    /\ \A ks \in Keyspaces : replicationFactor[ks] \in Nat
    /\ DOMAIN writeConsistencyFactor = Keyspaces
    /\ \A ks \in Keyspaces : writeConsistencyFactor[ks] \in Nat
    /\ \A ks \in Keyspaces : writeConsistencyFactor[ks] <= replicationFactor[ks]

CoreTypeOK ==
    /\ recordPartition \in [Records -> Partitions]
    /\ recordKeyspace \in [Records -> Keyspaces]
    /\ partitionKeyspace \in [Partitions -> Keyspaces]
    /\ replicaNode \in [Replicas -> Nodes]
    /\ replicas \in [Partitions -> SUBSET Replicas]
    /\ replicationFactor \in [Keyspaces -> Nat]
    /\ writeConsistencyFactor \in [Keyspaces -> Nat]

=============================================================================
