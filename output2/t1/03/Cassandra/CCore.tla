------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals

CONSTANTS
    Nodes,
    Principals,
    Keyspaces,
    Shards,
    Partitions,
    initialReplicas,
    replicationFactor,
    writeConsistencyFactor,
    partitionShard,
    partitionKeyspace,
    shardKeyspace

\* Operation types
Operations == {"Read", "Write", "Manage", "Migrate"}

\* Write states
WriteStates == {"None", "WalLogged", "Applied"}

\* Migrate states
MigrateStates == {"Stable", "Migratering", "Activated"}

\* Read consistency levels
ReadConsistencyLevels == {"One", "Quorum", "All"}

\* Dynamic replica set – declaration only, initialization in CIntegrated
VARIABLES replicas

CoreAssumption ==
    /\ Nodes # {}
    /\ Principals # {}
    /\ Keyspaces # {}
    /\ Shards # {}
    /\ Partitions # {}
    /\ DOMAIN partitionShard = Partitions
    /\ DOMAIN partitionKeyspace = Partitions
    /\ DOMAIN shardKeyspace = Shards
    /\ \A pt \in Partitions : partitionKeyspace[pt] = shardKeyspace[partitionShard[pt]]
    /\ DOMAIN initialReplicas = Shards
    /\ \A s \in Shards : initialReplicas[s] \subseteq Nodes
    /\ DOMAIN replicationFactor = Keyspaces
    /\ \A ks \in Keyspaces : replicationFactor[ks] \in 1..Cardinality(Nodes)
    /\ \A ks \in Keyspaces : 
         \A s \in Shards : 
            shardKeyspace[s] = ks => Cardinality(initialReplicas[s]) = replicationFactor[ks]
    /\ DOMAIN writeConsistencyFactor = Keyspaces
    /\ \A ks \in Keyspaces : 
         writeConsistencyFactor[ks] \in 1..replicationFactor[ks]

CoreTypeOK ==
    /\ replicas \in [Shards -> SUBSET Nodes]
    /\ \A s \in Shards : replicas[s] \subseteq Nodes
    /\ \A s \in Shards : Cardinality(replicas[s]) = replicationFactor[shardKeyspace[s]]

=============================================================================
