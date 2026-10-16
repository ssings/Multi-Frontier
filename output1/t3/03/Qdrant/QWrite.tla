------------------------------ MODULE QWrite ------------------------------

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

\* Record for lastWrite history
WriteRecordT ==
    [ kind       : {"None", "Some"},
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
          authorized |-> FALSE ]

\* ReceiveWrite: authorized write moves point into WAL
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
          point      |-> pt,
          authorized |-> TRUE ]

\* RejectWrite: unauthorized write attempt records refusal only
RejectWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Points
    /\ ~CanAccess(p, pointCollection[pt], "Write")
    /\ writeState[pt] = "None"
    /\ UNCHANGED writeState
    /\ UNCHANGED wal
    /\ UNCHANGED applied
    /\ UNCHANGED ackSet
    /\ UNCHANGED replicaHas
    /\ UNCHANGED shardData
    /\ lastWrite' =
        [ kind       |-> "Some",
          principal  |-> p,
          point      |-> pt,
          authorized |-> FALSE ]

\* ReplicaAck: a replica acknowledges a point currently in WAL
ReplicaAck(pt, r) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ r \in replicas[pointShard[pt]]
    /\ ackSet' = [ackSet EXCEPT ![pt] = @ \cup {r}]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ UNCHANGED writeState
    /\ UNCHANGED wal
    /\ UNCHANGED applied
    /\ UNCHANGED shardData
    /\ UNCHANGED lastWrite

\* CommitWrite: point becomes applied when write consistency is met
CommitWrite(pt) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ Cardinality(ackSet[pt]) >= writeConsistencyFactor[pointCollection[pt]]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
    /\ applied' = applied \cup {pt}
    /\ shardData' = [shardData EXCEPT ![pointShard[pt]] = @ \cup {pt}]
    /\ UNCHANGED wal
    /\ UNCHANGED ackSet
    /\ UNCHANGED replicaHas
    /\ UNCHANGED lastWrite

\* SyncReplica: after commit, remaining replicas can catch up
SyncReplica(pt, r) ==
    /\ pt \in applied
    /\ r \in replicas[pointShard[pt]]
    /\ pt \notin replicaHas[r]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ UNCHANGED writeState
    /\ UNCHANGED wal
    /\ UNCHANGED applied
    /\ UNCHANGED ackSet
    /\ UNCHANGED shardData
    /\ UNCHANGED lastWrite

\* Local next for Write module
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
