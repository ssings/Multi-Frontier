------------------------------- MODULE QWrite -------------------------------

EXTENDS QAuth

VARIABLES
    writeState,
    wal,
    applied,
    ackSet,
    replicaHas,
    shardData,
    lastWrite

WriteVars ==
    <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

\* lastWrite records successful or rejected attempts
WriteRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      collection : Collections,
      point      : Points,
      authorized : BOOLEAN ]

WriteTypeOK ==
    /\ writeState \in [Points -> WriteStates]
    /\ wal \subseteq Points
    /\ applied \subseteq Points
    /\ ackSet \in [Points -> SUBSET Replicas]
    /\ replicaHas \in [Replicas -> SUBSET Points]
    /\ shardData \in [Shards -> SUBSET Points]
    /\ lastWrite \in WriteRecordT
    /\ \A pt \in Points : ackSet[pt] \subseteq ReplicasOfPoint(pt)
    /\ \A r \in Replicas : replicaHas[r] \subseteq Points
    /\ \A s \in Shards : shardData[s] \subseteq Points

InitWrite ==
    /\ writeState = [pt \in Points |-> "None"]
    /\ wal = {}
    /\ applied = {}
    /\ ackSet = [pt \in Points |-> {}]
    /\ replicaHas = [r \in Replicas |-> {}]
    /\ shardData = [s \in Shards |-> {}]
    /\ lastWrite =
        [ kind       |-> "None",
          principal  |-> CHOOSE p \in Principals : TRUE,
          collection |-> CHOOSE c \in Collections : TRUE,
          point      |-> CHOOSE pt \in Points : TRUE,
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
    /\ lastWrite' =
        [ kind       |-> "Some",
          principal  |-> p,
          collection |-> pointCollection[pt],
          point      |-> pt,
          authorized |-> TRUE ]
    /\ UNCHANGED permission

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
    /\ UNCHANGED <<lastWrite, permission>>

ReplicaAck(pt, r) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ r \in ReplicasOfPoint(pt)
    /\ ackSet' = [ackSet EXCEPT ![pt] = @ \cup {r}]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ shardData' = shardData
    /\ lastWrite' = lastWrite
    /\ UNCHANGED permission

CommitWrite(pt) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ Cardinality(ackSet[pt]) >= writeConsistencyFactor[pointCollection[pt]]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
    /\ applied' = applied \cup {pt}
    /\ shardData' = [shardData EXCEPT ![pointShard[pt]] = @ \cup {pt}]
    /\ wal' = wal
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ lastWrite' = lastWrite
    /\ UNCHANGED permission

SyncReplica(pt, r) ==
    /\ pt \in applied
    /\ r \in ReplicasOfPoint(pt)
    /\ pt \notin replicaHas[r]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ ackSet' = ackSet
    /\ shardData' = shardData
    /\ lastWrite' = lastWrite
    /\ UNCHANGED permission

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

=============================================================================
