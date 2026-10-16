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

WriteVars == <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

WriteRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      collection : Collections,
      point      : Points,
      authorized : BOOLEAN,
      executed   : BOOLEAN ]

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
    /\ lastWrite = [kind       |-> "None",
                    principal  |-> CHOOSE p \in Principals : TRUE,
                    collection |-> CHOOSE c \in Collections : TRUE,
                    point      |-> CHOOSE pt \in Points : TRUE,
                    authorized |-> FALSE,
                    executed   |-> FALSE]

ReceiveWrite(p, pt) ==
    LET c == pointCollection[pt] IN
    /\ p \in Principals
    /\ pt \in Points
    /\ CanAccess(p, c, "Write")
    /\ writeState[pt] = "None"
    /\ writeState' = [writeState EXCEPT ![pt] = "WalLogged"]
    /\ wal' = wal \cup {pt}
    /\ lastWrite' = [kind       |-> "Some",
                     principal  |-> p,
                     collection |-> c,
                     point      |-> pt,
                     authorized |-> TRUE,
                     executed   |-> TRUE]
    /\ UNCHANGED <<permission, applied, ackSet, replicaHas, shardData>>

RejectWrite(p, pt) ==
    LET c == pointCollection[pt] IN
    /\ p \in Principals
    /\ pt \in Points
    /\ ~CanAccess(p, c, "Write")
    /\ lastWrite' = [kind       |-> "Some",
                     principal  |-> p,
                     collection |-> c,
                     point      |-> pt,
                     authorized |-> FALSE,
                     executed   |-> FALSE]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData>>

ReplicaAck(pt, r) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ r \in ReplicasOfPoint(pt)
    /\ ackSet' = [ackSet EXCEPT ![pt] = @ \cup {r}]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ UNCHANGED <<permission, writeState, wal, applied, shardData, lastWrite>>

CommitWrite(pt) ==
    LET c == pointCollection[pt] IN
    LET s == pointShard[pt] IN
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ Cardinality(ackSet[pt]) >= writeConsistencyFactor[c]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
    /\ applied' = applied \cup {pt}
    /\ shardData' = [shardData EXCEPT ![s] = @ \cup {pt}]
    /\ UNCHANGED <<permission, wal, ackSet, replicaHas, lastWrite>>

SyncReplica(pt, r) ==
    /\ pt \in applied
    /\ r \in ReplicasOfPoint(pt)
    /\ pt \notin replicaHas[r]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, shardData, lastWrite>>

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
