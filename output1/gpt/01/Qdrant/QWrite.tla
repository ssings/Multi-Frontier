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

LastWriteT ==
    [ kind       : {"None", "Write"},
      principal  : Principals,
      point      : Points,
      authorized : BOOLEAN,
      accepted   : BOOLEAN ]

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
          point      |-> CHOOSE pt \in Points : TRUE,
          authorized |-> FALSE,
          accepted   |-> FALSE ]

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
        [ kind       |-> "Write",
          principal  |-> p,
          point      |-> pt,
          authorized |-> TRUE,
          accepted   |-> TRUE ]

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
        [ kind       |-> "Write",
          principal  |-> p,
          point      |-> pt,
          authorized |-> FALSE,
          accepted   |-> FALSE ]

ReplicaAck(pt, r) ==
    /\ pt \in Points
    /\ r \in Replicas
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ r \in ReplicasOfPoint(pt)
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ ackSet' = [ackSet EXCEPT ![pt] = @ \cup {r}]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ shardData' = shardData
    /\ lastWrite' = lastWrite

CommitWrite(pt) ==
    /\ pt \in Points
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ Cardinality(ackSet[pt]) >=
        writeConsistencyFactor[pointCollection[pt]]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
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
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
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

WriteTypeOK ==
    /\ writeState \in [Points -> WriteStates]
    /\ wal \subseteq Points
    /\ applied \subseteq Points
    /\ ackSet \in [Points -> SUBSET Replicas]
    /\ replicaHas \in [Replicas -> SUBSET Points]
    /\ shardData \in [Shards -> SUBSET Points]
    /\ lastWrite \in LastWriteT
    /\ \A pt \in Points :
        ackSet[pt] \subseteq ReplicasOfPoint(pt)
    /\ \A s \in Shards :
        shardData[s] \subseteq PointsOfShard(s)
    /\ \A s \in Shards :
        applied \cap PointsOfShard(s) \subseteq shardData[s]

=============================================================================
