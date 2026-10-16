------------------------------- MODULE CWrite -------------------------------

EXTENDS CAuth

VARIABLES
    writeRequested,
    writeLevel,
    ackCount,
    committed,
    replicaHas,
    lastWrite

WriteRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      dataItem   : DataItems,
      keyspace   : Keyspaces,
      level      : ConsistencyLevels,
      authorized : BOOLEAN ]

WriteTypeInvariant ==
    /\ writeRequested \subseteq DataItems
    /\ writeLevel \in [DataItems -> ConsistencyLevels]
    /\ ackCount \in [DataItems -> Nat]
    /\ committed \subseteq DataItems
    /\ replicaHas \in [Replicas -> SUBSET DataItems]
    /\ lastWrite \in WriteRecordT

ReqAcks(d) ==
    LET tr == TokenRangeOf(d)
        rf == Cardinality(replicaSet[tr])
    IN CASE writeLevel[d] = "ONE"     -> 1
       [] writeLevel[d] = "QUORUM"   -> (rf \div 2) + 1
       [] writeLevel[d] = "ALL"      -> rf

InitWrite ==
    /\ writeRequested = {}
    /\ writeLevel = [d \in DataItems |-> "ONE"]
    /\ ackCount = [d \in DataItems |-> 0]
    /\ committed = {}
    /\ replicaHas = [r \in Replicas |-> {}]
    /\ lastWrite =
        [ kind       |-> "None",
          principal  |-> CHOOSE p \in Principals : TRUE,
          dataItem   |-> CHOOSE d \in DataItems : TRUE,
          keyspace   |-> CHOOSE k \in Keyspaces : TRUE,
          level      |-> "ONE",
          authorized |-> FALSE ]

ReceiveWrite(p, d, lv) ==
    /\ p \in Principals
    /\ d \in DataItems
    /\ lv \in ConsistencyLevels
    /\ d \notin writeRequested
    /\ CanAccess(p, DataItemKeyspace(d), "Write")
    /\ writeRequested' = writeRequested \cup {d}
    /\ writeLevel' = [writeLevel EXCEPT ![d] = lv]
    /\ ackCount' = [ackCount EXCEPT ![d] = 0]
    /\ committed' = committed
    /\ replicaHas' = replicaHas
    /\ lastWrite' =
        [ kind       |-> "Some",
          principal  |-> p,
          dataItem   |-> d,
          keyspace   |-> DataItemKeyspace(d),
          level      |-> lv,
          authorized |-> TRUE ]

RejectWrite(p, d) ==
    /\ p \in Principals
    /\ d \in DataItems
    /\ ~CanAccess(p, DataItemKeyspace(d), "Write")
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas>>
    /\ lastWrite' =
        [ kind       |-> "Some",
          principal  |-> p,
          dataItem   |-> d,
          keyspace   |-> DataItemKeyspace(d),
          level      |-> "ONE",
          authorized |-> FALSE ]

ReplicaAck(r, d) ==
    /\ r \in Replicas
    /\ d \in DataItems
    /\ d \in writeRequested
    /\ r \in replicaSet[TokenRangeOf(d)]
    /\ d \notin replicaHas[r]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {d}]
    /\ LET newAckCount == ackCount[d] + 1
       IN ackCount' = [ackCount EXCEPT ![d] = newAckCount]
    /\ IF newAckCount >= ReqAcks(d)
       THEN committed' = committed \cup {d}
       ELSE committed' = committed
    /\ UNCHANGED <<writeRequested, writeLevel, lastWrite>>

NextWriteOnly ==
    \/ \E p, d, lv : ReceiveWrite(p, d, lv)
    \/ \E p, d : RejectWrite(p, d)
    \/ \E r, d : ReplicaAck(r, d)

=============================================================================
