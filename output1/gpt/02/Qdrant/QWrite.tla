------------------------------ MODULE QWrite -------------------------------

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

InitialPoint ==
    CHOOSE pt \in Points : TRUE

WriteRecordT ==
    [ kind       : {"None", "Receive", "Reject"},
      principal  : Principals,
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
    /\ \A pt \in Points :
        ackSet[pt] \subseteq ReplicasOfPoint(pt)
    /\ \A r \in Replicas :
        replicaHas[r] \subseteq
            {pt \in Points : r \in ReplicasOfPoint(pt)}
    /\ \A s \in Shards :
        shardData[s] \subseteq PointsOfShard(s)
    /\ \A pt \in Points :
        writeState[pt] = "None" <=> pt \notin wal
    /\ \A pt \in Points :
        writeState[pt] = "Applied" <=> pt \in applied
    /\ \A s \in Shards :
        shardData[s] = applied \cap PointsOfShard(s)

InitWrite ==
    /\ writeState = [pt \in Points |-> "None"]
    /\ wal = {}
    /\ applied = {}
    /\ ackSet = [pt \in Points |-> {}]
    /\ replicaHas = [r \in Replicas |-> {}]
    /\ shardData = [s \in Shards |-> {}]
    /\ lastWrite =
        [ kind       |-> "None",
          principal  |-> InitialAdmin,
          point      |-> InitialPoint,
          authorized |-> FALSE ]

ReceiveWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Points
    /\ CanAccess(p, pointCollection[pt], "Write")
    /\ writeState[pt] = "None"
    /\ writeState' =
        [writeState EXCEPT ![pt] = "WalLogged"]
    /\ wal' = wal \cup {pt}
    /\ applied' = applied
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ shardData' = shardData
    /\ lastWrite' =
        [ kind       |-> "Receive",
          principal  |-> p,
          point      |-> pt,
          authorized |-> TRUE ]

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
    /\ lastWrite' =
        [ kind       |-> "Reject",
          principal  |-> p,
          point      |-> pt,
          authorized |-> FALSE ]

ReplicaAck(pt, r) ==
    /\ pt \in Points
    /\ r \in Replicas
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ r \in ReplicasOfPoint(pt)
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ ackSet' =
        [ackSet EXCEPT ![pt] = @ \cup {r}]
    /\ replicaHas' =
        [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ shardData' = shardData
    /\ lastWrite' = lastWrite

CommitWrite(pt) ==
    /\ pt \in Points
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ Cardinality(ackSet[pt])
        >= writeConsistencyFactor[pointCollection[pt]]
    /\ writeState' =
        [writeState EXCEPT ![pt] = "Applied"]
    /\ wal' = wal
    /\ applied' = applied \cup {pt}
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ shardData' =
        [shardData EXCEPT ![pointShard[pt]] = @ \cup {pt}]
    /\ lastWrite' = lastWrite

SyncReplica(pt, r) ==
    /\ pt \in Points
    /\ r \in Replicas
    /\ pt \in applied
    /\ r \in ReplicasOfPoint(pt)
    /\ pt \notin replicaHas[r]
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ ackSet' = ackSet
    /\ replicaHas' =
        [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ shardData' = shardData
    /\ lastWrite' = lastWrite

NextWrite ==
    \/ \E p \in Principals :
        \E pt \in Points :
            ReceiveWrite(p, pt)
    \/ \E p \in Principals :
        \E pt \in Points :
            RejectWrite(p, pt)
    \/ \E pt \in Points :
        \E r \in Replicas :
            ReplicaAck(pt, r)
    \/ \E pt \in Points :
        CommitWrite(pt)
    \/ \E pt \in Points :
        \E r \in Replicas :
            SyncReplica(pt, r)

=============================================================================
