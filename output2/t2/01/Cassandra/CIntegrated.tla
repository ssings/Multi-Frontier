---------------------------- MODULE CIntegrated ----------------------------

EXTENDS CFrontierInterface

ASSUME CoreAssumption

Vars ==
    << permission,
       writeRequested, writeLevel, ackCount, committed, replicaHas, lastWrite,
       tokenReplicas, migrateState, migrateSrcNodes, migrateDstNodes,
       copiedData, lastMigrate,
       queryResult, lastQuery >>

Init ==
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitQuery

\* Wrappers for actions to ensure UNCHANGED other variables
DoGrant(a, t, k, o) ==
    /\ GrantPermission(a, t, k, o)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas, lastWrite,
                   tokenReplicas, migrateState, migrateSrcNodes, migrateDstNodes,
                   copiedData, lastMigrate,
                   queryResult, lastQuery>>

DoRevoke(a, t, k, o) ==
    /\ RevokePermission(a, t, k, o)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas, lastWrite,
                   tokenReplicas, migrateState, migrateSrcNodes, migrateDstNodes,
                   copiedData, lastMigrate,
                   queryResult, lastQuery>>

DoReceiveWrite(p, d, lv) ==
    /\ ReceiveWrite(p, d, lv)
    /\ UNCHANGED <<permission,
                   tokenReplicas, migrateState, migrateSrcNodes, migrateDstNodes,
                   copiedData, lastMigrate,
                   queryResult, lastQuery>>

DoRejectWrite(p, d) ==
    /\ RejectWrite(p, d)
    /\ UNCHANGED <<permission,
                   tokenReplicas, migrateState, migrateSrcNodes, migrateDstNodes,
                   copiedData, lastMigrate,
                   queryResult, lastQuery>>

DoReplicaAck(r, d) ==
    /\ ReplicaAck(r, d)
    /\ UNCHANGED <<permission,
                   tokenReplicas, migrateState, migrateSrcNodes, migrateDstNodes,
                   copiedData, lastMigrate,
                   queryResult, lastQuery>>

DoStartMigrate(p, tr, dst) ==
    /\ StartMigrate(p, tr, dst)
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas, lastWrite,
                   queryResult, lastQuery>>

DoRejectMigrate(p, tr) ==
    /\ RejectMigrate(p, tr)
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas, lastWrite,
                   queryResult, lastQuery>>

DoAdvanceMigrate(tr) ==
    /\ AdvanceMigrate(tr)
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas, lastWrite,
                   queryResult, lastQuery>>

DoActivateMigrate(tr) ==
    /\ ActivateMigrate(tr)
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, lastWrite,
                   queryResult, lastQuery>>

DoFinishMigrate(tr) ==
    /\ FinishMigrate(tr)
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas, lastWrite,
                   queryResult, lastQuery>>

DoQuery(p, k, level) ==
    /\ Query(p, k, level)
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas, lastWrite,
                   tokenReplicas, migrateState, migrateSrcNodes, migrateDstNodes,
                   copiedData, lastMigrate>>

DoRejectQuery(p, k, level) ==
    /\ RejectQuery(p, k, level)
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas, lastWrite,
                   tokenReplicas, migrateState, migrateSrcNodes, migrateDstNodes,
                   copiedData, lastMigrate>>

Next ==
    \/ \E a, t, k, o : DoGrant(a, t, k, o)
    \/ \E a, t, k, o : DoRevoke(a, t, k, o)
    \/ \E p, d, lv : DoReceiveWrite(p, d, lv)
    \/ \E p, d : DoRejectWrite(p, d)
    \/ \E r, d : DoReplicaAck(r, d)
    \/ \E p, tr, dst : DoStartMigrate(p, tr, dst)
    \/ \E p, tr : DoRejectMigrate(p, tr)
    \/ \E tr : DoAdvanceMigrate(tr)
    \/ \E tr : DoActivateMigrate(tr)
    \/ \E tr : DoFinishMigrate(tr)
    \/ \E p, k, level : DoQuery(p, k, level)
    \/ \E p, k, level : DoRejectQuery(p, k, level)

Spec ==
    /\ Init
    /\ [][Next]_Vars

\* Safety invariants
GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeInvariant
    /\ WriteTypeInvariant
    /\ ReplicaTypeInvariant
    /\ MigrateTypeInvariant
    /\ QueryTypeInvariant

AuthSafety ==
    /\ (lastWrite.kind = "Some" /\ lastWrite.authorized)
        => CanAccess(lastWrite.principal, lastWrite.keyspace, "Write")
    /\ (lastWrite.kind = "Some" /\ ~lastWrite.authorized)
        => ~CanAccess(lastWrite.principal, lastWrite.keyspace, "Write")
    /\ (lastQuery.kind = "Some" /\ lastQuery.authorized)
        => CanAccess(lastQuery.principal, lastQuery.keyspace, "Read")
    /\ (lastQuery.kind = "Some" /\ ~lastQuery.authorized)
        => ~CanAccess(lastQuery.principal, lastQuery.keyspace, "Read")
    /\ (lastMigrate.kind = "Some" /\ lastMigrate.authorized)
        => CanMigrate(lastMigrate.principal)
    /\ (lastMigrate.kind = "Some" /\ ~lastMigrate.authorized)
        => ~CanMigrate(lastMigrate.principal)

WriteSafety ==
    /\ committed \subseteq writeRequested

ReplicaSafety ==
    /\ \A r \in Replicas : replicaHas[r] \subseteq writeRequested

QuerySafety ==
    /\ lastQuery.kind = "Some" =>
        queryResult = SearchEligibleSet(lastQuery.principal, lastQuery.keyspace, lastQuery.level)

MigrateSafety ==
    /\ \A tr \in TokenRanges :
        IF migrateState[tr] = "Activated"
        THEN {d \in committed : TokenRangeOf(d) = tr}
                \subseteq {d \in replicaHas[r] : r \in tokenReplicas[tr]}
        ELSE TRUE
    /\ \A tr \in TokenRanges :
        migrateState[tr] = "Migratering" =>
            {d \in committed : TokenRangeOf(d) = tr} \subseteq copiedData[tr]
    /\ \A tr \in TokenRanges :
        migrateState[tr] = "Activated" =>
            tokenReplicas[tr] = {r \in Replicas : replicaNode[r] \in migrateDstNodes[tr]}

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ AuthSafety
    /\ WriteSafety
    /\ ReplicaSafety
    /\ QuerySafety
    /\ MigrateSafety
    /\ FrontierSafety

=============================================================================
