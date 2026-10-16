------------------------------- MODULE CWrite -------------------------------

EXTENDS CAuth

VARIABLES
    writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite

WriteVars == <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

WriteRecordT == [kind : {"None", "Some"}, principal : Principals, record : Records, authorized : BOOLEAN]

wFactor(ks) == writeConsistencyFactor[ks]

InitWrite ==
    /\ writeState = [r \in Records |-> "None"]
    /\ wal = {}
    /\ applied = {}
    /\ ackSet = [r \in Records |-> {}]
    /\ replicaHas = [rep \in Replicas |-> {}]
    /\ shardData = [p \in Partitions |-> {}]
    /\ lastWrite = [kind |-> "None",
                    principal |-> CHOOSE p \in Principals : TRUE,
                    record |-> CHOOSE r \in Records : TRUE,
                    authorized |-> FALSE]

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
    /\ lastWrite' = [kind |-> "Some", principal |-> p, record |-> r, authorized |-> TRUE]
    /\ UNCHANGED permission

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
    /\ lastWrite' = [kind |-> "Some", principal |-> p, record |-> r, authorized |-> FALSE]
    /\ UNCHANGED permission

ReplicaAck(r, rep) ==
    /\ r \in wal
    /\ writeState[r] = "CommitLogged"
    /\ rep \in replicas[recordPartition[r]]
    /\ ackSet' = [ackSet EXCEPT ![r] = @ \cup {rep}]
    /\ replicaHas' = [replicaHas EXCEPT ![rep] = @ \cup {r}]
    /\ UNCHANGED <<permission, writeState, wal, applied, shardData, lastWrite>>

CommitWrite(r) ==
    /\ writeState[r] = "CommitLogged"
    /\ Cardinality(ackSet[r]) >= wFactor(recordKeyspace[r])
    /\ writeState' = [writeState EXCEPT ![r] = "Applied"]
    /\ wal' = wal
    /\ applied' = applied \cup {r}
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ shardData' = [shardData EXCEPT ![recordPartition[r]] = @ \cup {r}]
    /\ lastWrite' = lastWrite
    /\ UNCHANGED permission

SyncReplica(r, rep) ==
    /\ r \in applied
    /\ rep \in replicas[recordPartition[r]]
    /\ r \notin replicaHas[rep]
    /\ replicaHas' = [replicaHas EXCEPT ![rep] = @ \cup {r}]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, shardData, lastWrite>>

NextWrite ==
    \/ \E p \in Principals, r \in Records :
        ReceiveWrite(p, r)
    \/ \E p \in Principals, r \in Records :
        RejectWrite(p, r)
    \/ \E r \in Records, rep \in Replicas :
        ReplicaAck(r, rep)
    \/ \E r \in Records :
        CommitWrite(r)
    \/ \E r \in Records, rep \in Replicas :
        SyncReplica(r, rep)

WriteTypeOK ==
    /\ writeState \in [Records -> {"None", "CommitLogged", "Applied"}]
    /\ wal \subseteq Records
    /\ applied \subseteq Records
    /\ ackSet \in [Records -> SUBSET Replicas]
    /\ replicaHas \in [Replicas -> SUBSET Records]
    /\ shardData \in [Partitions -> SUBSET Records]
    /\ lastWrite \in WriteRecordT

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
