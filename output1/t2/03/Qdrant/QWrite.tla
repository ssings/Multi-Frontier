--------------------------- MODULE QWrite ---------------------------
EXTENDS QAuth

VARIABLES
    writeState,
    wal,
    applied,
    ackSet,
    replicaHas,
    shardData,
    lastWrite

WriteVars == <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

WriteRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      collection : Collections,
      authorized : BOOLEAN ]

InitWrite ==
    /\ writeState = [pt \in Points |-> "None"]
    /\ wal = {}
    /\ applied = {}
    /\ ackSet = [pt \in Points |-> {}]
    /\ replicaHas = [r \in Replicas |-> {}]
    /\ shardData = [s \in Shards |-> {}]
    /\ lastWrite = [ kind |-> "None",
                     principal |-> CHOOSE p \in Principals : TRUE,
                     collection |-> CHOOSE c \in Collections : TRUE,
                     authorized |-> FALSE ]

ReceiveWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Points
    /\ CanAccess(p, pointCollection[pt], "Write")
    /\ writeState[pt] = "None"
    /\ writeState' = [writeState EXCEPT ![pt] = "WalLogged"]
    /\ wal' = wal \cup {pt}
    /\ applied' = applied
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ shardData' = shardData
    /\ lastWrite' = [ kind |-> "Some", principal |-> p, collection |-> pointCollection[pt], authorized |-> TRUE ]

RejectWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Points
    /\ ~CanAccess(p, pointCollection[pt], "Write")
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ shardData' = shardData
    /\ lastWrite' = lastWrite

ReplicaAck(pt, r) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ r \in replicas[pointShard[pt]]
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ ackSet' = [ackSet EXCEPT ![pt] = ackSet[pt] \cup {r}]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = replicaHas[r] \cup {pt}]
    /\ shardData' = shardData
    /\ lastWrite' = lastWrite

CommitWrite(pt) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ Cardinality(ackSet[pt]) >= writeConsistencyFactor[pointCollection[pt]]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
    /\ wal' = wal
    /\ applied' = applied \cup {pt}
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ shardData' = [shardData EXCEPT ![pointShard[pt]] = shardData[pointShard[pt]] \cup {pt}]
    /\ lastWrite' = lastWrite

SyncReplica(pt, r) ==
    /\ pt \in applied
    /\ r \in replicas[pointShard[pt]]
    /\ pt \notin replicaHas[r]
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ ackSet' = ackSet
    /\ replicaHas' = [replicaHas EXCEPT ![r] = replicaHas[r] \cup {pt}]
    /\ shardData' = shardData
    /\ lastWrite' = lastWrite

NextWrite ==
    \/ \E p \in Principals, pt \in Points :
        ReceiveWrite(p, pt)
    \/ \E p \in Principals, pt \in Points :
        RejectWrite(p, pt)
    \/ \E pt \in Points, r \in Replicas :
        ReplicaAck(pt, r)
    \/ \E pt \in Points :
        CommitWrite(pt)
    \/ \E pt \in Points, r \in Replicas :
        SyncReplica(pt, r)

WriteTypeOK ==
    /\ writeState \in [Points -> WriteStates]
    /\ wal \subseteq Points
    /\ applied \subseteq Points
    /\ ackSet \in [Points -> SUBSET Replicas]
    /\ replicaHas \in [Replicas -> SUBSET Points]
    /\ shardData \in [Shards -> SUBSET Points]
    /\ lastWrite \in WriteRecordT

WalBeforeApply == applied \subseteq wal
ReplicaNotAheadOfWAL == \A r \in Replicas : replicaHas[r] \subseteq wal

=============================================================================
