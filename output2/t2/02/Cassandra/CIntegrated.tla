----------------------------- MODULE CIntegrated -----------------------------

EXTENDS CFrontierInterface, CCfgHelpers

Vars == <<permission,
          writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
          shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
          readResult, lastRead>>

Init ==
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitRead

DoGrantPermission(a, t, ks, op) ==
    /\ GrantPermission(a, t, ks, op)
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                  readResult, lastRead>>

DoRevokePermission(a, t, ks, op) ==
    /\ RevokePermission(a, t, ks, op)
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                  readResult, lastRead>>

DoReceiveWrite(p, r) ==
    /\ ReceiveWrite(p, r)
    /\ UNCHANGED <<permission,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                  readResult, lastRead>>

DoRejectWrite(p, r) ==
    /\ RejectWrite(p, r)
    /\ UNCHANGED <<permission,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                  readResult, lastRead>>

DoReplicaAck(r, rep) ==
    /\ ReplicaAck(r, rep)
    /\ UNCHANGED <<permission,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                  readResult, lastRead>>

DoCommitWrite(r) ==
    /\ CommitWrite(r)
    /\ UNCHANGED <<permission,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                  readResult, lastRead>>

DoSyncReplica(r, rep) ==
    /\ SyncReplica(r, rep)
    /\ UNCHANGED <<permission,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                  readResult, lastRead>>

DoStartMigrate(p, partition, src, dst) ==
    /\ StartMigrate(p, partition, src, dst)
    /\ UNCHANGED <<permission,
                  writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                  readResult, lastRead>>

DoRejectMigrate(p, partition) ==
    /\ RejectMigrate(p, partition)
    /\ UNCHANGED <<permission,
                  writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                  readResult, lastRead>>

DoAdvanceMigrate(partition) ==
    /\ AdvanceMigrate(partition)
    /\ UNCHANGED <<permission,
                  writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                  readResult, lastRead>>

DoActivateMigrate(partition) ==
    /\ ActivateMigrate(partition)
    /\ UNCHANGED <<permission,
                  writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                  readResult, lastRead>>

DoFinishMigrate(partition) ==
    /\ FinishMigrate(partition)
    /\ UNCHANGED <<permission,
                  writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                  readResult, lastRead>>

DoRead(p, ks, level) ==
    /\ Read(p, ks, level)
    /\ UNCHANGED <<permission,
                  writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>

DoRejectRead(p, ks, level) ==
    /\ RejectRead(p, ks, level)
    /\ UNCHANGED <<permission,
                  writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>

Next ==
    \/ \E a \in Principals, t \in Principals, ks \in Keyspaces, op \in Operations : DoGrantPermission(a, t, ks, op)
    \/ \E a \in Principals, t \in Principals, ks \in Keyspaces, op \in Operations : DoRevokePermission(a, t, ks, op)
    \/ \E p \in Principals, r \in Records : DoReceiveWrite(p, r)
    \/ \E p \in Principals, r \in Records : DoRejectWrite(p, r)
    \/ \E r \in Records, rep \in Replicas : DoReplicaAck(r, rep)
    \/ \E r \in Records : DoCommitWrite(r)
    \/ \E r \in Records, rep \in Replicas : DoSyncReplica(r, rep)
    \/ \E p \in Principals, partition \in Partitions, src \in Nodes, dst \in Nodes : DoStartMigrate(p, partition, src, dst)
    \/ \E p \in Principals, partition \in Partitions : DoRejectMigrate(p, partition)
    \/ \E partition \in Partitions : DoAdvanceMigrate(partition)
    \/ \E partition \in Partitions : DoActivateMigrate(partition)
    \/ \E partition \in Partitions : DoFinishMigrate(partition)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels : DoRead(p, ks, level)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels : DoRejectRead(p, ks, level)

Spec == Init /\ [][Next]_Vars

GlobalTypeInvariant ==
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ MigrateTypeOK
    /\ ReadTypeOK

AuthSafety ==
    /\ (lastWrite.authorized /\ lastWrite.kind # "None") => CanAccess(lastWrite.principal, recordKeyspace[lastWrite.record], "Write")
    /\ (lastRead.authorized /\ lastRead.kind # "None") => CanAccess(lastRead.principal, lastRead.keyspace, "Read")
    /\ (lastMigrate.authorized /\ lastMigrate.kind = "Start") => CanAccess(lastMigrate.principal, partitionKeyspace[lastMigrate.partition], "Migrate")

WalBeforeCommit ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A rep \in Replicas : replicaHas[rep] \subseteq wal

MigrateSafety ==
    /\ \A p \in Partitions : shardOwner[p] \in shardLocation[p]
    /\ \A p \in Partitions : migrateState[p] # "Stable" => (migrateSrc[p] = shardOwner[p] /\ migrateDst[p] # migrateSrc[p])
    /\ \A p \in Partitions : migrateState[p] = "Migratering" =>
        (\A r \in Records : recordPartition[r] = p /\ r \in applied => r \in copiedData[p])
    /\ \A p \in Partitions : migrateState[p] = "Activated" => shardData[p] = copiedData[p]

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ AuthSafety
    /\ WalBeforeCommit
    /\ ReplicaNotAheadOfWAL
    /\ MigrateSafety
    /\ FrontierSafety

=============================================================================
