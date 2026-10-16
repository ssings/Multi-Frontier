------------------------------- MODULE CWrite -------------------------------

EXTENDS CAuth

WriteStates == {"None", "WalLogged", "Applied"}

VARIABLES
    writeState,
    wal,
    applied,
    replicaHas,
    replicas

ReceiveWrite(p, pt, node) ==
    LET ks == partitionKeyspace[pt] IN
    LET sh == partitionShard[pt] IN
    /\ p \in Principals
    /\ pt \in Partitions
    /\ node \in replicas[sh]
    /\ CanAccess(p, ks, "Write")
    /\ writeState[pt] = "None"
    /\ writeState' = [writeState EXCEPT ![pt] = "WalLogged"]
    /\ wal' = wal \cup {pt}
    /\ replicaHas' = [replicaHas EXCEPT ![node] = @ \cup {pt}]
    /\ lastWrite' = [authorized |-> TRUE, principal |-> p, keyspace |-> ks, partition |-> pt]
    /\ UNCHANGED <<applied, replicas, permission, lastQuery, lastMigrate>>

ReplicateToNode(pt, node) ==
    /\ pt \in wal
    /\ node \in replicas[partitionShard[pt]]
    /\ pt \notin replicaHas[node]
    /\ replicaHas' = [replicaHas EXCEPT ![node] = @ \cup {pt}]
    /\ UNCHANGED <<writeState, wal, applied, replicas, permission, lastWrite, lastQuery, lastMigrate>>

CommitIfReady(pt) ==
    /\ writeState[pt] = "WalLogged"
    /\ LET sh == partitionShard[pt] IN
        LET ncopies == Cardinality({n \in replicas[sh] : pt \in replicaHas[n]}) IN
        ncopies >= writeConsistencyFactor[partitionKeyspace[pt]]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
    /\ applied' = applied \cup {pt}
    /\ UNCHANGED <<wal, replicaHas, replicas, permission, lastWrite, lastQuery, lastMigrate>>

WriteTypeInvariant ==
    /\ writeState \in [Partitions -> WriteStates]
    /\ wal \subseteq Partitions
    /\ applied \subseteq Partitions
    /\ replicaHas \in [Nodes -> SUBSET Partitions]
    /\ replicas \in [Shards -> SUBSET Nodes]
    /\ \A sh \in Shards : Cardinality(replicas[sh]) = replicationFactor[shardKeyspace[sh]]

WalBeforeApply ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A n \in Nodes : replicaHas[n] \subseteq wal

=============================================================================
