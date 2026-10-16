------------------------------- MODULE CIntegrated -------------------------------

EXTENDS CFrontierInterface, CassandraCfgHelpers

Vars ==
    << permission, lastWrite, lastQuery, lastMigrate,
       writeRequested, writeLevel, ackCount, committed, replicaHas,
       currentReplicas, migrateState, migrateSrc, migrateDst, copiedData >>

Init ==
    /\ CoreAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate

\* wrappers
DoGrantPermission(admin, target, k, op) ==
    /\ GrantPermission(admin, target, k, op)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas,
                   currentReplicas, migrateState, migrateSrc, migrateDst, copiedData>>

DoRevokePermission(admin, target, k, op) ==
    /\ RevokePermission(admin, target, k, op)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas,
                   currentReplicas, migrateState, migrateSrc, migrateDst, copiedData>>

DoReceiveWrite(p, d, l) ==
    /\ ReceiveWrite(p, d, l)
    /\ UNCHANGED <<currentReplicas, migrateState, migrateSrc, migrateDst, copiedData>>

DoRejectWrite(p, d, l) ==
    /\ RejectWrite(p, d, l)
    /\ UNCHANGED <<currentReplicas, migrateState, migrateSrc, migrateDst, copiedData>>

DoReplicaAck(r, d) ==
    /\ ReplicaAck(r, d)
    /\ UNCHANGED <<currentReplicas, migrateState, migrateSrc, migrateDst, copiedData>>

DoStartMigrate(p, k, tr, dst) ==
    /\ StartMigrate(p, k, tr, dst)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas>>

DoRejectMigrate(p, k, tr, dst) ==
    /\ RejectMigrate(p, k, tr, dst)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas>>

DoAdvanceMigrate(p, tr) ==
    /\ AdvanceMigrate(p, tr)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas>>

DoActivateMigrate(p, tr) ==
    /\ ActivateMigrate(p, tr)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed>>

DoFinishMigrate(p, tr) ==
    /\ FinishMigrate(p, tr)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas>>

DoQuery(p, k, l) ==
    /\ Query(p, k, l)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas,
                   currentReplicas, migrateState, migrateSrc, migrateDst, copiedData>>

DoRejectQuery(p, k, l) ==
    /\ RejectQuery(p, k, l)
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas,
                   currentReplicas, migrateState, migrateSrc, migrateDst, copiedData>>

Next ==
    \/ \E admin, target \in Principals, k \in Keyspaces, op \in Operations :
            DoGrantPermission(admin, target, k, op)
    \/ \E admin, target \in Principals, k \in Keyspaces, op \in Operations :
            DoRevokePermission(admin, target, k, op)
    \/ \E p \in Principals, d \in DataItems, l \in {"ONE","QUORUM","ALL"} :
            DoReceiveWrite(p, d, l)
    \/ \E p \in Principals, d \in DataItems, l \in {"ONE","QUORUM","ALL"} :
            DoRejectWrite(p, d, l)
    \/ \E r \in Replicas, d \in DataItems :
            DoReplicaAck(r, d)
    \/ \E p \in Principals, k \in Keyspaces, tr \in TokenRanges, dst \in SUBSET Nodes :
            DoStartMigrate(p, k, tr, dst)
    \/ \E p \in Principals, k \in Keyspaces, tr \in TokenRanges, dst \in SUBSET Nodes :
            DoRejectMigrate(p, k, tr, dst)
    \/ \E p \in Principals, tr \in TokenRanges :
            DoAdvanceMigrate(p, tr)
    \/ \E p \in Principals, tr \in TokenRanges :
            DoActivateMigrate(p, tr)
    \/ \E p \in Principals, tr \in TokenRanges :
            DoFinishMigrate(p, tr)
    \/ \E p \in Principals, k \in Keyspaces, l \in {"ONE","QUORUM","ALL"} :
            DoQuery(p, k, l)
    \/ \E p \in Principals, k \in Keyspaces, l \in {"ONE","QUORUM","ALL"} :
            DoRejectQuery(p, k, l)

Spec == Init /\ [][Next]_Vars

GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ ReplicaTypeOK
    /\ MigrateTypeOK

AuthSafety ==
    /\ (lastWrite.kind = "Some") => lastWrite.authorized = TRUE
    /\ (lastQuery.kind = "Some") => lastQuery.authorized = TRUE
    /\ (lastMigrate.kind = "Some") => lastMigrate.authorized = TRUE

WriteSafety ==
    committed \subseteq writeRequested

ReplicaSafety ==
    \A r \in Replicas : replicaHas[r] \subseteq writeRequested

QuerySafety ==
    (lastQuery.kind = "Some") =>
        lastQuery.result = SearchEligibleSet(lastQuery.principal, lastQuery.keyspace, lastQuery.level)

MigrateSafety ==
    \A tr \in TokenRanges :
        /\ (migrateState[tr] = "Migratering") => currentReplicas[tr] = migrateSrc[tr]
        /\ (migrateState[tr] = "Activated") => currentReplicas[tr] = migrateDst[tr]
        /\ (migrateState[tr] = "Activated") =>
            \A d \in committed : dataItemTokenRange[d] = tr => \E r \in currentReplicas[tr] : d \in replicaHas[r]

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ AuthSafety
    /\ WriteSafety
    /\ ReplicaSafety
    /\ QuerySafety
    /\ MigrateSafety
    /\ FrontierSafety

=============================================================================
