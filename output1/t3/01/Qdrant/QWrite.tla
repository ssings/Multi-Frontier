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

WriteVars == <<writeState, wal, applied, ackSet, replicaHas,
               shardData, lastWrite>>

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
                    authorized |-> FALSE]

ReceiveWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Points
    /\ CanAccess(p, pointCollection[pt], "Write")
    /\ writeState[pt] = "None"
    /\ writeState' = [writeState EXCEPT ![pt] = "WalLogged"]
    /\ wal' = wal \cup {pt}
    /\ lastWrite' = [kind       |-> "Some",
                     principal  |-> p,
                     collection |-> pointCollection[pt],
                     point      |-> pt,
                     authorized |-> TRUE]
    /\ UNCHANGED <<applied, ackSet, replicaHas, shardData>>

RejectWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Points
    /\ ~CanAccess(p, pointCollection[pt], "Write")
    /\ writeState[pt] = "None"
    /\ lastWrite' = [kind       |-> "Some",
                     principal  |-> p,
                     collection |-> pointCollection[pt],
                     point      |-> pt,
                     authorized |-> FALSE]
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData>>

ReplicaAck(pt, r) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ r \in ReplicasOfPoint(pt)
    /\ ackSet' = [ackSet EXCEPT ![pt] = ackSet[pt] \cup {r}]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = replicaHas[r] \cup {pt}]
    /\ UNCHANGED <<writeState, wal, applied, shardData, lastWrite>>

CommitWrite(pt) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ Cardinality(ackSet[pt]) >= writeConsistencyFactor[pointCollection[pt]]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
    /\ applied' = applied \cup {pt}
    /\ shardData' = [shardData EXCEPT ![pointShard[pt]] =
                        shardData[pointShard[pt]] \cup {pt}]
    /\ UNCHANGED <<wal, ackSet, replicaHas, lastWrite>>

SyncReplica(pt, r) ==
    /\ pt \in applied
    /\ r \in ReplicasOfPoint(pt)
    /\ pt \notin replicaHas[r]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = replicaHas[r] \cup {pt}]
    /\ UNCHANGED <<writeState, wal, applied, ackSet, shardData, lastWrite>>

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
    /\ lastWrite \in [kind       : {"None","Some"},
                      principal  : Principals,
                      collection : Collections,
                      point      : Points,
                      authorized : BOOLEAN]

WalBeforeApply == applied \subseteq wal

ReplicaNotAheadOfWAL == \A r \in Replicas : replicaHas[r] \subseteq wal

=============================================================================
