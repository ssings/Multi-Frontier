------------------------- MODULE CIntegrated -------------------------

EXTENDS CFrontierInterface, CCfgHelpers

GlobalVars ==
    <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
      shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
      readResult, lastRead>>

Init ==
    /\ CoreAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitRead

DoGrantPermission(admin, target, ks, op) ==
    /\ GrantPermission(admin, target, ks, op)
    /\ UNCHANGED <<WriteVars, MigrateVars, ReadVars>>

DoRevokePermission(admin, target, ks, op) ==
    /\ RevokePermission(admin, target, ks, op)
    /\ UNCHANGED <<WriteVars, MigrateVars, ReadVars>>

DoReceiveWrite(p, r) ==
    /\ ReceiveWrite(p, r)
    /\ UNCHANGED <<AuthVars, MigrateVars, ReadVars>>

DoRejectWrite(p, r) ==
    /\ RejectWrite(p, r)
    /\ UNCHANGED <<AuthVars, MigrateVars, ReadVars>>

DoReplicaAck(r, rep) ==
    /\ ReplicaAck(r, rep)
    /\ UNCHANGED <<AuthVars, MigrateVars, ReadVars>>

DoCommitWrite(r) ==
    /\ CommitWrite(r)
    /\ UNCHANGED <<AuthVars, MigrateVars, ReadVars>>

DoSyncReplica(r, rep) ==
    /\ SyncReplica(r, rep)
    /\ UNCHANGED <<AuthVars, MigrateVars, ReadVars>>

DoStartMigrate(p, pt, src, dst) ==
    /\ StartMigrate(p, pt, src, dst)
    /\ UNCHANGED <<AuthVars, ReadVars>>

DoRejectMigrate(p, pt, src, dst) ==
    /\ RejectMigrate(p, pt, src, dst)
    /\ UNCHANGED <<AuthVars, ReadVars>>

DoAdvanceMigrate(pt) ==
    /\ AdvanceMigrate(pt)
    /\ UNCHANGED <<AuthVars, ReadVars>>

DoActivateMigrate(pt) ==
    /\ ActivateMigrate(pt)
    /\ UNCHANGED <<AuthVars, ReadVars>>

DoFinishMigrate(pt) ==
    /\ FinishMigrate(pt)
    /\ UNCHANGED <<AuthVars, ReadVars>>

DoRead(p, ks, level) ==
    /\ Read(p, ks, level)
    /\ UNCHANGED <<AuthVars>>

DoRejectRead(p, ks, level) ==
    /\ RejectRead(p, ks, level)
    /\ UNCHANGED <<AuthVars>>

Next ==
    \/ \E admin, target \in Principals, ks \in Keyspaces, op \in Operations :
        DoGrantPermission(admin, target, ks, op)
    \/ \E admin, target \in Principals, ks \in Keyspaces, op \in Operations :
        DoRevokePermission(admin, target, ks, op)
    \/ \E p \in Principals, r \in Records : DoReceiveWrite(p, r)
    \/ \E p \in Principals, r \in Records : DoRejectWrite(p, r)
    \/ \E r \in Records, rep \in Replicas : DoReplicaAck(r, rep)
    \/ \E r \in Records : DoCommitWrite(r)
    \/ \E r \in Records, rep \in Replicas : DoSyncReplica(r, rep)
    \/ \E p \in Principals, pt \in Partitions, src \in Nodes, dst \in Nodes :
        DoStartMigrate(p, pt, src, dst)
    \/ \E p \in Principals, pt \in Partitions, src \in Nodes, dst \in Nodes :
        DoRejectMigrate(p, pt, src, dst)
    \/ \E pt \in Partitions : DoAdvanceMigrate(pt)
    \/ \E pt \in Partitions : DoActivateMigrate(pt)
    \/ \E pt \in Partitions : DoFinishMigrate(pt)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        DoRead(p, ks, level)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels :
        DoRejectRead(p, ks, level)

Spec == Init /\ [][Next]_GlobalVars

GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ MigrateTypeOK
    /\ ReadTypeOK

AuthSafety ==
    /\ (lastWrite.kind = "Some") => lastWrite.authorized = TRUE
    /\ (lastMigrate.kind = "Some") => lastMigrate.authorized = TRUE
    /\ (lastRead.kind = "Some") => lastRead.authorized = TRUE

WalBeforeApply ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A rep \in Replicas : replicaHas[rep] \subseteq wal

MigrateSafety ==
    /\ \A pt \in Partitions : shardOwner[pt] \in shardLocation[pt]
    /\ \A pt \in Partitions :
        (migrateState[pt] = "Migratering") =>
            /\ migrateSrc[pt] = shardOwner[pt]
            /\ migrateDst[pt] \in shardLocation[pt]
            /\ migrateDst[pt] # migrateSrc[pt]
    /\ \A pt \in Partitions :
        (migrateState[pt] = "Activated") =>
            (applied \cap PointsOfPartition(pt)) \subseteq shardData[pt]
    /\ \A r \in applied : MigrationSafe(r)

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ AuthSafety
    /\ WalBeforeApply
    /\ ReplicaNotAheadOfWAL
    /\ MigrateSafety
    /\ FrontierSafety

=============================================================================
