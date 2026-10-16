------------------------------- MODULE QWrite --------------------------------

EXTENDS QAuth

VARIABLES
    writeState,   \* [Points -> WriteStates]
    wal,          \* SUBSET Points : points whose write has been accepted
    applied,      \* SUBSET Points : points that reached commit condition
    ackSet,       \* [Points -> SUBSET Replicas] : who acknowledged this point
    replicaHas,   \* [Replicas -> SUBSET Points] : points held by a replica
    shardData,    \* [Shards -> SUBSET Points]   : committed points per shard
    lastWrite     \* Record of the last write attempt

WriteVars ==
    <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

\* Record for write attempts
WriteRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      pt         : Points,
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
    /\ lastWrite = [ kind |-> "None",
                     principal |-> CHOOSE p \in Principals : TRUE,
                     pt |-> CHOOSE pt \in Points : TRUE,
                     authorized |-> FALSE ]

\* Authorized write request
ReceiveWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Points
    /\ CanAccess(p, pointCollection[pt], "Write")
    /\ writeState[pt] = "None"
    /\ writeState' = [writeState EXCEPT ![pt] = "WalLogged"]
    /\ wal' = wal \cup {pt}
    /\ ackSet' = ackSet
    /\ applied' = applied
    /\ replicaHas' = replicaHas
    /\ shardData' = shardData
    /\ lastWrite' = [ kind |-> "Some",
                      principal |-> p,
                      pt |-> pt,
                      authorized |-> TRUE ]

\* Unauthorized write is rejected without changing database state
RejectWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Points
    /\ ~CanAccess(p, pointCollection[pt], "Write")
    /\ writeState[pt] = "None"
    /\ writeState' = writeState
    /\ wal' = wal
    /\ ackSet' = ackSet
    /\ applied' = applied
    /\ replicaHas' = replicaHas
    /\ shardData' = shardData
    /\ lastWrite' = [ kind |-> "Some",
                      principal |-> p,
                      pt |-> pt,
                      authorized |-> FALSE ]

\* A replica acknowledges a point that is still in WAL
ReplicaAck(pt, r) ==
    /\ pt \in wal
    /\ writeState[pt] = "WalLogged"
    /\ r \in ReplicasOfPoint(pt)
    /\ r \notin ackSet[pt]
    /\ ackSet' = [ackSet EXCEPT ![pt] = @ \cup {r}]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ UNCHANGED <<writeState, wal, applied, shardData, lastWrite>>

\* A point reaches the required write consistency factor
CommitWrite(pt) ==
    /\ writeState[pt] = "WalLogged"
    /\ Cardinality(ackSet[pt]) >= writeConsistencyFactor[pointCollection[pt]]
    /\ writeState' = [writeState EXCEPT ![pt] = "Applied"]
    /\ applied' = applied \cup {pt}
    /\ shardData' = [shardData EXCEPT ![pointShard[pt]] = @ \cup {pt}]
    /\ UNCHANGED <<wal, ackSet, replicaHas, lastWrite>>

\* After commit, remaining replicas can obtain the point
SyncReplica(pt, r) ==
    /\ pt \in applied
    /\ r \in ReplicasOfPoint(pt)
    /\ pt \notin replicaHas[r]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {pt}]
    /\ UNCHANGED <<writeState, wal, applied, ackSet, shardData, lastWrite>>

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
