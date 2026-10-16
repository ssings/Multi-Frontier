------------------------------- MODULE CWrite -------------------------------

EXTENDS CAuth

VARIABLES
    writeRequested,
    writeLevel,
    ackCount,
    committed,
    replicaHas

WriteThreshold(level, rf) ==
    CASE level = "ONE"     -> 1
      [] level = "QUORUM"  -> (rf \div 2) + 1
      [] level = "ALL"     -> rf

InitWrite ==
    /\ writeRequested = {}
    /\ writeLevel = [d \in DataItems |-> "ONE"]
    /\ ackCount = [d \in DataItems |-> 0]
    /\ committed = {}
    /\ replicaHas = [r \in Replicas |-> {}]

ReceiveWrite(principal, dataItem, level) ==
    LET keyspace == dataItemKeyspace(dataItem) IN
    /\ principal \in Principals
    /\ dataItem \in DataItems
    /\ level \in {"ONE", "QUORUM", "ALL"}
    /\ CanAccess(principal, keyspace, "Write")
    /\ dataItem \notin writeRequested
    /\ writeRequested' = writeRequested \cup {dataItem}
    /\ writeLevel' = [writeLevel EXCEPT ![dataItem] = level]
    /\ ackCount' = [ackCount EXCEPT ![dataItem] = 0]
    /\ committed' = committed
    /\ replicaHas' = replicaHas
    /\ lastWrite' = [ kind |-> "Some",
                      principal |-> principal,
                      keyspace |-> keyspace,
                      dataItem |-> dataItem,
                      authorized |-> TRUE,
                      accepted |-> TRUE ]
    /\ UNCHANGED <<permission, lastQuery, lastMigrate>>

RejectWrite(principal, dataItem, level) ==
    LET keyspace == dataItemKeyspace(dataItem) IN
    /\ principal \in Principals
    /\ dataItem \in DataItems
    /\ level \in {"ONE", "QUORUM", "ALL"}
    /\ ~CanAccess(principal, keyspace, "Write")
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas, permission>>
    /\ lastWrite' = [ kind |-> "None",
                      principal |-> principal,
                      keyspace |-> keyspace,
                      dataItem |-> dataItem,
                      authorized |-> FALSE,
                      accepted |-> FALSE ]
    /\ UNCHANGED <<lastQuery, lastMigrate>>

ReplicaAck(replica, dataItem) ==
    LET tokenRange == dataItemTokenRange[dataItem] IN
    LET rf == Cardinality(replicaSet[tokenRange]) IN
    LET level == writeLevel[dataItem] IN
    LET threshold == WriteThreshold(level, rf) IN
    /\ replica \in Replicas
    /\ dataItem \in writeRequested
    /\ replica \in replicaSet[tokenRange]
    /\ dataItem \notin replicaHas[replica]
    /\ replicaHas' = [replicaHas EXCEPT ![replica] = @ \cup {dataItem}]
    /\ ackCount' = [ackCount EXCEPT ![dataItem] = ackCount[dataItem] + 1]
    /\ IF ackCount[dataItem] + 1 >= threshold
         THEN committed' = committed \cup {dataItem}
         ELSE committed' = committed
    /\ UNCHANGED <<writeRequested, writeLevel, permission, lastWrite, lastQuery, lastMigrate>>

WriteTypeOK ==
    /\ writeRequested \subseteq DataItems
    /\ writeLevel \in [DataItems -> {"ONE", "QUORUM", "ALL"}]
    /\ ackCount \in [DataItems -> Nat]
    /\ committed \subseteq DataItems
    /\ replicaHas \in [Replicas -> SUBSET DataItems]
    /\ \A d \in DataItems : ackCount[d] <= Cardinality(replicaSet[dataItemTokenRange[d]])

=============================================================================
