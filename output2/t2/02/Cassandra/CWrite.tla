------------------------------- MODULE CWrite -------------------------------

EXTENDS CAuth

VARIABLES
    writeState,
    wal,
    applied,
    ackSet,
    replicaHas,
    shardData,
    lastWrite

WriteVars == <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

WriteRecordT == [
    kind       : {"None", "Write"},
    principal  : Principals,
    record     : Records,
    authorized : BOOLEAN
]

InitWrite ==
    /\ writeState = [r \in Records |-> "None"]
    /\ wal = {}
    /\ applied = {}
    /\ ackSet = [r \in Records |-> {}]
    /\ replicaHas = [rep \in Replicas |-> {}]
    /\ shardData = [p \in Partitions |-> {}]
    /\ lastWrite = [kind |-> "None", principal |-> CHOOSE p \in Principals : TRUE, record |-> CHOOSE r \in Records : TRUE, authorized |-> FALSE]

ReceiveWrite(p, r) ==
    /\ p \in Principals
    /\ r \in Records
    /\ CanAccess(p, recordKeyspace[r], "Write")
    /\ writeState[r] = "None"
    /\ writeState' = [writeState EXCEPT ![r] = "CommitLogged"]
    /\ wal' = wal \cup {r}
    /\ applied' = applied
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ shardData' = shardData
    /\ lastWrite' = [kind |-> "Write", principal |-> p, record |-> r, authorized |-> TRUE]

RejectWrite(p, r) ==
    /\ p \in Principals
    /\ r \in Records
    /\ ~CanAccess(p, recordKeyspace[r], "Write")
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ shardData' = shardData
    /\ lastWrite' = [kind |-> "Write", principal |-> p, record |-> r, authorized |-> FALSE]

ReplicaAck(r, rep) ==
    /\ r \in wal
    /\ writeState[r] = "CommitLogged"
    /\ rep \in replicas[recordPartition[r]]
    /\ ackSet' = [ackSet EXCEPT ![r] = @ \cup {rep}]
    /\ replicaHas' = [replicaHas EXCEPT ![rep] = @ \cup {r}]
    /\ UNCHANGED <<writeState, wal, applied, shardData, lastWrite>>

CommitWrite(r) ==
    LET ks == recordKeyspace[r] IN
    /\ writeState[r] = "CommitLogged"
    /\ Cardinality(ackSet[r]) >= writeConsistencyFactor[ks]
    /\ writeState' = [writeState EXCEPT ![r] = "Applied"]
    /\ applied' = applied \cup {r}
    /\ shardData' = [shardData EXCEPT ![recordPartition[r]] = @ \cup {r}]
    /\ UNCHANGED <<wal, ackSet, replicaHas, lastWrite>>

SyncReplica(r, rep) ==
    /\ r \in applied
    /\ rep \in replicas[recordPartition[r]]
    /\ r \notin replicaHas[rep]
    /\ replicaHas' = [replicaHas EXCEPT ![rep] = @ \cup {r}]
    /\ UNCHANGED <<writeState, wal, applied, ackSet, shardData, lastWrite>>

WriteTypeOK ==
    /\ writeState \in [Records -> WriteStates]
    /\ wal \subseteq Records
    /\ applied \subseteq Records
    /\ ackSet \in [Records -> SUBSET Replicas]
    /\ replicaHas \in [Replicas -> SUBSET Records]
    /\ shardData \in [Partitions -> SUBSET Records]
    /\ lastWrite \in WriteRecordT

=============================================================================
