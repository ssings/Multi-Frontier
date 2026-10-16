------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals, FiniteSets

CONSTANTS
    Principals,
    Keyspaces,
    Partitions,
    Records,
    Replicas,
    Nodes,
    replicaNode,
    replicas,
    recordPartition,
    recordKeyspace,
    partitionKeyspace,
    replicationFactor,
    writeConsistencyFactor

Operations == {"Read", "Write", "Manage", "Migrate"}

WriteStates == {"None", "CommitLogged", "Applied"}

ReadConsistencyLevels == {"One", "Quorum", "All"}

MigrateStates == {"Stable", "Migratering", "Activated"}

ReplicasOfPartition(partition) == replicas[partition]

CoreAssumption ==
    /\ Principals # {}
    /\ Keyspaces # {}
    /\ Partitions # {}
    /\ Records # {}
    /\ Replicas # {}
    /\ Nodes # {}
    /\ DOMAIN replicaNode = Replicas
    /\ DOMAIN replicas = Partitions
    /\ \A p \in Partitions : replicas[p] # {}
    /\ DOMAIN recordPartition = Records
    /\ \A r \in Records : recordPartition[r] \in Partitions
    /\ DOMAIN recordKeyspace = Records
    /\ \A r \in Records : recordKeyspace[r] \in Keyspaces
    /\ DOMAIN partitionKeyspace = Partitions
    /\ \A p \in Partitions : partitionKeyspace[p] \in Keyspaces
    /\ \A r \in Records : recordKeyspace[r] = partitionKeyspace[recordPartition[r]]
    /\ DOMAIN replicationFactor = Keyspaces
    /\ \A ks \in Keyspaces : replicationFactor[ks] \in Nat \ {0}
    /\ DOMAIN writeConsistencyFactor = Keyspaces
    /\ \A ks \in Keyspaces : writeConsistencyFactor[ks] \in 1..replicationFactor[ks]

CoreTypeOK == TRUE

=============================================================================
