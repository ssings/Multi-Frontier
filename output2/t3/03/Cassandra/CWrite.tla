------------------------------- MODULE CWrite -------------------------------

EXTENDS CAuth

VARIABLES
    writeState,
    wal,
    applied,
    replicaHas,
    replicas

WriteVars == <<writeState, wal, applied, replicaHas, replicas>>

WriteStates == {"None", "WalLogged", "Applied"}

WriteTypeOK ==
    /\ writeState \in [Partitions -> WriteStates]
    /\ wal \subseteq Partitions
    /\ applied \subseteq Partitions
    /\ replicaHas \in [Nodes -> SUBSET Partitions]
    /\ replicas \in [Shards -> SUBSET Nodes]

InitWrite ==
    /\ writeState = [pt \in Partitions |-> "None"]
    /\ wal = {}
    /\ applied = {}
    /\ replicaHas = [n \in Nodes |-> {}]
    /\ replicas = initialReplicas

ReceiveWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Partitions
    /\ CanAccess(p, partitionKeyspace[pt], "Write")
    /\ writeState[pt] = "None"
    /\ writeState' = [writeState EXCEPT ![pt] = "WalLogged"]
    /\ wal' = wal \cup {pt}
    /\ applied' = applied
    /\ replicaHas' = replicaHas
    /\ replicas' = replicas
    /\ lastWrite' = [ kind |-> "Write", principal |-> p, keyspace |-> partitionKeyspace[pt], op |-> "Write", level |-> "None", authorized |-> TRUE ]
    /\ UNCHANGED <<lastQuery, lastMigrate>>

ReplicateToNode(pt, node) ==
    /\ pt \in wal
    /\ node \in Nodes
    /\ node \in replicas[partitionShard[pt]]
    /\ pt \notin replicaHas[node]
    /\ replicaHas' = [replicaHas EXCEPT ![node] = @ \cup {pt}]
    /\ UNCHANGED <<writeState, wal, applied, replicas, lastWrite, lastQuery, lastMigrate>>

CommitIfReady(pt) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ LET ks == partitionKeyspace[pt] IN
       LET sh == partitionShard[pt] IN
       LET count == Cardinality({n \in replicas[sh] : pt \in replicaHas[n]}) IN
       count >= writeConsistencyFactor[ks]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
    /\ applied' = applied \cup {pt}
    /\ UNCHANGED <<wal, replicaHas, replicas, lastWrite, lastQuery, lastMigrate>>

NextWrite ==
    \/ \E p \in Principals :
        \E pt \in Partitions :
            ReceiveWrite(p, pt)
    \/ \E pt \in Partitions :
        \E node \in Nodes :
            ReplicateToNode(pt, node)
    \/ \E pt \in Partitions :
            CommitIfReady(pt)

=============================================================================
