---------------------------- MODULE CIntegrated ----------------------------

EXTENDS CFrontierInterface, CCfgHelpers

Vars == <<permission, lastWrite, lastQuery, lastMigrate,
          writeRequested, writeLevel, ackCount, committed, replicaHas,
          currentReplicas, migrateState, migrateSrc, migrateDst,
          copiedData>>

Init ==
    /\ CoreAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate

DoGrantPermission(admin, target, ks, op) ==
    /\ GrantPermission(admin, target, ks, op)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData>>

DoRevokePermission(admin, target, ks, op) ==
    /\ RevokePermission(admin, target, ks, op)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData>>

DoReceiveWrite(p, d, level) ==
    /\ ReceiveWrite(p, d, level)
    /\ UNCHANGED <<permission, lastQuery, lastMigrate,
                   currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData>>

DoRejectWrite(p, d, level) ==
    /\ RejectWrite(p, d, level)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, permission, lastQuery, lastMigrate,
                   currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData>>

DoReplicaAck(r, d) ==
    /\ ReplicaAck(r, d)
    /\ UNCHANGED <<permission, lastWrite, lastQuery, lastMigrate,
                   currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData>>

DoStartMigrate(p, tr, dst) ==
    /\ StartMigrate(p, tr, dst)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, permission, lastWrite, lastQuery>>

DoRejectMigrate(p, tr, dst) ==
    /\ RejectMigrate(p, tr, dst)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastQuery>>

DoAdvanceMigrate(tr) ==
    /\ AdvanceMigrate(tr)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst,
                   permission, lastWrite, lastQuery>>

DoActivateMigrate(tr) ==
    /\ ActivateMigrate(tr)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastQuery>>

DoFinishMigrate(tr) ==
    /\ FinishMigrate(tr)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst,
                   permission, lastWrite, lastQuery>>

DoQuery(p, ks, level) ==
    /\ Query(p, ks, level)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastMigrate>>

DoRejectQuery(p, ks, level) ==
    /\ RejectQuery(p, ks, level)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastMigrate>>

Next ==
    \/ \E admin,target \in Principals, ks \in Keyspaces, op \in Operations :
        DoGrantPermission(admin, target, ks, op)
    \/ \E admin,target \in Principals, ks \in Keyspaces, op \in Operations :
        DoRevokePermission(admin, target, ks, op)
    \/ \E p \in Principals, d \in DataItems, level \in WriteConsistencyLevels :
        DoReceiveWrite(p, d, level)
    \/ \E p \in Principals, d \in DataItems, level \in WriteConsistencyLevels :
        DoRejectWrite(p, d, level)
    \/ \E r \in Replicas, d \in DataItems :
        DoReplicaAck(r, d)
    \/ \E p \in Principals, tr \in TokenRanges, dst \in SUBSET Nodes :
        DoStartMigrate(p, tr, dst)
    \/ \E p \in Principals, tr \in TokenRanges, dst \in SUBSET Nodes :
        DoRejectMigrate(p, tr, dst)
    \/ \E tr \in TokenRanges :
        DoAdvanceMigrate(tr)
    \/ \E tr \in TokenRanges :
        DoActivateMigrate(tr)
    \/ \E tr \in TokenRanges :
        DoFinishMigrate(tr)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        DoQuery(p, ks, level)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        DoRejectQuery(p, ks, level)

Spec == Init /\ [][Next]_Vars

GlobalTypeInvariant ==
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ MigrateTypeOK
    /\ QueryTypeOK

AuthSafety ==
    /\ lastWrite.kind # "None" => lastWrite.authorized = TRUE =>
        CanAccess(lastWrite.principal, lastWrite.keyspace, "Write")
    /\ lastQuery.kind # "None" => lastQuery.authorized = TRUE =>
        CanAccess(lastQuery.principal, lastQuery.keyspace, "Read")
    /\ lastMigrate.kind # "None" => lastMigrate.authorized = TRUE =>
        CanMigrate(lastMigrate.principal)

WriteSafety ==
    /\ committed \subseteq writeRequested
    /\ \A r \in Replicas : replicaHas[r] \subseteq writeRequested
    /\ \A d \in writeRequested :
        \A r \in Replicas :
            d \in replicaHas[r] => r \in replicaSet[TokenRangeOf(d)]

ReplicaSafety ==
    \A r \in Replicas, d \in DataItems :
        d \in replicaHas[r] => d \in writeRequested

QuerySafety ==
    lastQuery.kind # "None" =>
        lastQuery.result = FinalQueryFrontier(lastQuery.principal,
                                              lastQuery.keyspace,
                                              lastQuery.level)

MigrateSafety ==
    /\ \A tr \in TokenRanges :
        LET targetData == {d \in committed : TokenRangeOf(d) = tr}
        IN
        (migrateState[tr] = "Migratering")
            => targetData \subseteq copiedData[tr]
    /\ \A tr \in TokenRanges :
        migrateState[tr] # "Stable" =>
            currentReplicas[tr] = migrateSrc[tr]
    /\ \A tr \in TokenRanges :
        migrateState[tr] = "Activated" =>
            currentReplicas[tr] = migrateDst[tr]

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ AuthSafety
    /\ WriteSafety
    /\ ReplicaSafety
    /\ QuerySafety
    /\ MigrateSafety
    /\ FrontierSafety

=============================================================================
