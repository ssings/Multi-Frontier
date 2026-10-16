------------------------------- MODULE CIntegrated -------------------------------

EXTENDS CFrontierInterface, CCfgHelpers

GlobalVars ==
    << writeState, wal, applied, replicaHas, replicas,
       permission, lastWrite, lastQuery, lastMigrate,
       searchResult,
       migrateState, migrateSrc, migrateDst, copiedData >>

Init ==
    /\ CoreAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitQuery
    /\ InitMigrate

DoGrantPermission(admin, target, ks, op) ==
    /\ GrantPermission(admin, target, ks, op)
    /\ UNCHANGED << writeState, wal, applied, replicaHas, replicas,
                    searchResult, lastWrite, lastQuery, lastMigrate,
                    migrateState, migrateSrc, migrateDst, copiedData >>

DoRevokePermission(admin, target, ks, op) ==
    /\ RevokePermission(admin, target, ks, op)
    /\ UNCHANGED << writeState, wal, applied, replicaHas, replicas,
                    searchResult, lastWrite, lastQuery, lastMigrate,
                    migrateState, migrateSrc, migrateDst, copiedData >>

DoRejectWrite(p, pt) ==
    /\ RejectWrite(p, pt)
    /\ UNCHANGED << writeState, wal, applied, replicaHas, replicas,
                    searchResult, lastQuery, lastMigrate,
                    migrateState, migrateSrc, migrateDst, copiedData >>

DoRejectMigrate(p, sh) ==
    /\ RejectMigrate(p, sh)
    /\ UNCHANGED << writeState, wal, applied, replicaHas, replicas,
                    searchResult, lastWrite, lastQuery,
                    migrateState, migrateSrc, migrateDst, copiedData >>

DoReceiveWrite(p, pt) ==
    /\ ReceiveWrite(p, pt)
    /\ UNCHANGED << permission, lastQuery, lastMigrate,
                    searchResult,
                    migrateState, migrateSrc, migrateDst, copiedData >>

DoReplicateToNode(pt, node) ==
    /\ ReplicateToNode(pt, node)
    /\ UNCHANGED << permission, lastWrite, lastQuery, lastMigrate,
                    searchResult,
                    migrateState, migrateSrc, migrateDst, copiedData >>

DoCommitIfReady(pt) ==
    /\ CommitIfReady(pt)
    /\ UNCHANGED << permission, lastWrite, lastQuery, lastMigrate,
                    searchResult,
                    migrateState, migrateSrc, migrateDst, copiedData >>

DoQuery(p, ks, level) ==
    /\ Query(p, ks, level)
    /\ UNCHANGED << permission, lastWrite, lastMigrate,
                    writeState, wal, applied, replicaHas, replicas,
                    migrateState, migrateSrc, migrateDst, copiedData >>

DoRejectQuery(p, ks, level) ==
    /\ RejectQuery(p, ks, level)
    /\ UNCHANGED << permission, lastWrite, lastMigrate,
                    writeState, wal, applied, replicaHas, replicas,
                    migrateState, migrateSrc, migrateDst, copiedData >>

DoStartMigrate(p, sh, src, dst) ==
    /\ StartMigrate(p, sh, src, dst)
    /\ UNCHANGED << permission, lastWrite, lastQuery,
                    searchResult,
                    writeState, wal, applied, replicaHas >>

DoAdvanceMigrate(sh) ==
    /\ AdvanceMigrate(sh)
    /\ UNCHANGED << permission, lastWrite, lastQuery, lastMigrate,
                    searchResult,
                    writeState, wal, applied, replicaHas, replicas,
                    migrateState, migrateSrc, migrateDst >>

DoActivateMigrate(sh) ==
    /\ ActivateMigrate(sh)
    /\ UNCHANGED << permission, lastWrite, lastQuery, lastMigrate,
                    searchResult,
                    writeState, wal, applied >>

DoFinishMigrate(sh) ==
    /\ FinishMigrate(sh)
    /\ UNCHANGED << permission, lastWrite, lastQuery, lastMigrate,
                    searchResult,
                    writeState, wal, applied, replicaHas, replicas >>

Next ==
    \/ \E admin \in Principals :
        \E target \in Principals :
            \E ks \in Keyspaces :
                \E op \in Operations :
                    DoGrantPermission(admin, target, ks, op)
    \/ \E admin \in Principals :
        \E target \in Principals :
            \E ks \in Keyspaces :
                \E op \in Operations :
                    DoRevokePermission(admin, target, ks, op)
    \/ \E p \in Principals :
        \E pt \in Partitions :
            DoRejectWrite(p, pt)
    \/ \E p \in Principals :
        \E sh \in Shards :
            DoRejectMigrate(p, sh)
    \/ \E p \in Principals :
        \E pt \in Partitions :
            DoReceiveWrite(p, pt)
    \/ \E pt \in Partitions :
        \E node \in Nodes :
            DoReplicateToNode(pt, node)
    \/ \E pt \in Partitions :
            DoCommitIfReady(pt)
    \/ \E p \in Principals :
        \E ks \in Keyspaces :
            \E level \in ReadConsistencyLevels :
                DoQuery(p, ks, level)
    \/ \E p \in Principals :
        \E ks \in Keyspaces :
            \E level \in ReadConsistencyLevels :
                DoRejectQuery(p, ks, level)
    \/ \E p \in Principals :
        \E sh \in Shards :
            \E src \in Nodes :
                \E dst \in Nodes :
                    DoStartMigrate(p, sh, src, dst)
    \/ \E sh \in Shards : DoAdvanceMigrate(sh)
    \/ \E sh \in Shards : DoActivateMigrate(sh)
    \/ \E sh \in Shards : DoFinishMigrate(sh)

Spec == Init /\ [][Next]_GlobalVars

GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ QueryTypeOK
    /\ MigrateTypeOK

AuthSafety ==
    /\ lastWrite.authorized = TRUE => CanAccess(lastWrite.principal, lastWrite.keyspace, "Write")
    /\ lastQuery.authorized = TRUE => CanAccess(lastQuery.principal, lastQuery.keyspace, "Read")
    /\ lastMigrate.authorized = TRUE => CanAccess(lastMigrate.principal, lastMigrate.keyspace, "Migrate")

WalBeforeApply == applied \subseteq wal

ReplicaNotAheadOfWAL == \A node \in Nodes : replicaHas[node] \subseteq wal

QuerySafety ==
    /\ \/ lastQuery.kind = "None"
       \/ (lastQuery.authorized = TRUE /\ searchResult = FinalQueryFrontier(lastQuery.principal, lastQuery.keyspace, lastQuery.level))
       \/ (lastQuery.authorized = FALSE /\ searchResult = {})

NoCommittedDataLoss ==
    \A sh \in Shards, pt \in applied :
        partitionShard[pt] = sh =>
            \E n \in replicas[sh] : pt \in replicaHas[n]

MigrateSafety ==
    /\ NoCommittedDataLoss
    /\ \A sh \in Shards :
        migrateState[sh] = "Migratering" =>
            /\ migrateSrc[sh] \in replicas[sh]
            /\ migrateDst[sh] \notin replicas[sh]
    /\ \A sh \in Shards :
        migrateState[sh] = "Activated" =>
            /\ migrateDst[sh] \in replicas[sh]
            /\ migrateSrc[sh] \notin replicas[sh]
            /\ \A pt \in applied \cap {pt \in Partitions : partitionShard[pt] = sh} : pt \in replicaHas[migrateDst[sh]]

=============================================================================
