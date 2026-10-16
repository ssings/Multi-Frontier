------------------------------- MODULE CWrite ------------------------------

EXTENDS CAuth

VARIABLES writeState, wal, applied, replicaHas

WriteTypeInvariant ==
    /\ writeState \in [Partitions -> WriteStates]
    /\ wal \subseteq Partitions
    /\ applied \subseteq Partitions
    /\ replicaHas \in [Nodes -> SUBSET Partitions]

InitWrite ==
    /\ writeState = [pt \in Partitions |-> "None"]
    /\ wal = {}
    /\ applied = {}
    /\ replicaHas = [n \in Nodes |-> {}]

ReceiveWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Partitions
    /\ CanAccess(p, partitionKeyspace[pt], "Write")
    /\ writeState[pt] = "None"
    /\ writeState' = [writeState EXCEPT ![pt] = "WalLogged"]
    /\ wal' = wal \cup {pt}
    /\ replicaHas' = replicaHas
    /\ applied' = applied
    /\ lastWrite' = [principal |-> p, partition |-> pt, authorized |-> TRUE]
    /\ UNCHANGED <<permission, lastQuery, lastMigrate, replicas>>

ReplicateToNode(pt, node) ==
    /\ pt \in wal
    /\ node \in replicas[partitionShard[pt]]
    /\ pt \notin replicaHas[node]
    /\ replicaHas' = [replicaHas EXCEPT ![node] = @ \cup {pt}]
    /\ UNCHANGED <<writeState, wal, applied, permission, lastWrite, lastQuery, lastMigrate, replicas>>

CommitIfReady(pt) ==
    /\ writeState[pt] = "WalLogged"
    /\ LET ks == partitionKeyspace[pt]
           sh == partitionShard[pt]
       IN Cardinality({n \in replicas[sh] : pt \in replicaHas[n]}) >= writeConsistencyFactor[ks]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
    /\ applied' = applied \cup {pt}
    /\ UNCHANGED <<wal, replicaHas, permission, lastWrite, lastQuery, lastMigrate, replicas>>

WalBeforeApply ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A n \in Nodes : replicaHas[n] \subseteq wal

WriteSafety ==
    /\ WalBeforeApply
    /\ ReplicaNotAheadOfWAL

=============================================================================
