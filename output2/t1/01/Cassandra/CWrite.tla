------------------------------- MODULE CWrite -------------------------------

EXTENDS CAuth

VARIABLES
    writeRequested,
    writeLevel,
    ackCount,
    committed,
    replicaHas

WriteVars == <<writeRequested, writeLevel, ackCount, committed, replicaHas>>

WriteThreshold(ks, level) ==
    LET rf == replicationFactor[ks] IN
    CASE level = "ONE"     -> 1
      [] level = "QUORUM"   -> rf \div 2 + 1
      [] level = "ALL"      -> rf

InitWrite ==
    /\ writeRequested = {}
    /\ writeLevel = [d \in DataItems |-> "ONE"]
    /\ ackCount = [d \in DataItems |-> 0]
    /\ committed = {}
    /\ replicaHas = [r \in Replicas |-> {}]

ReceiveWrite(p, d, level) ==
    LET ks == KeyspaceOf(d) IN
    /\ p \in Principals
    /\ d \in DataItems
    /\ level \in WriteConsistencyLevels
    /\ CanAccess(p, ks, "Write")
    /\ d \notin writeRequested
    /\ writeRequested' = writeRequested \cup {d}
    /\ writeLevel' = [writeLevel EXCEPT ![d] = level]
    /\ ackCount' = [ackCount EXCEPT ![d] = 0]
    /\ lastWrite' = [kind |-> "Some", principal |-> p,
                     keyspace |-> ks, dataItem |-> d,
                     level |-> level, authorized |-> TRUE]
    /\ UNCHANGED <<committed, replicaHas, permission,
                   lastQuery, lastMigrate>>

RejectWrite(p, d, level) ==
    LET ks == KeyspaceOf(d) IN
    /\ p \in Principals
    /\ d \in DataItems
    /\ level \in WriteConsistencyLevels
    /\ ~CanAccess(p, ks, "Write")
    /\ lastWrite' = [kind |-> "Some", principal |-> p,
                     keyspace |-> ks, dataItem |-> d,
                     level |-> level, authorized |-> FALSE]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, permission, lastQuery, lastMigrate>>

ReplicaAck(r, d) ==
    LET tr == TokenRangeOf(d)
        ks == KeyspaceOf(d)
    IN
    /\ r \in Replicas
    /\ d \in writeRequested
    /\ r \in replicaSet[tr]
    /\ d \notin replicaHas[r]
    /\ replicaHas' = [replicaHas EXCEPT ![r] = @ \cup {d}]
    /\ ackCount' = [ackCount EXCEPT ![d] = @ + 1]
    /\ IF ackCount'[d] >= WriteThreshold(ks, writeLevel[d])
        THEN committed' = committed \cup {d}
        ELSE committed' = committed
    /\ UNCHANGED <<writeRequested, writeLevel,
                   permission, lastWrite, lastQuery, lastMigrate>>

WriteTypeOK ==
    /\ writeRequested \subseteq DataItems
    /\ writeLevel \in [DataItems -> WriteConsistencyLevels]
    /\ ackCount \in [DataItems -> Nat]
    /\ committed \subseteq DataItems
    /\ replicaHas \in [Replicas -> SUBSET DataItems]

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
