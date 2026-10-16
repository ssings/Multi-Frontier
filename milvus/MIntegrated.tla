---------------------------- MODULE MIntegrated ----------------------------

EXTENDS MFrontierInterface

Vars ==
    << tsoVector, versionVector, sessionWriteTs, pendingWrites,
       lastWrite, syncedVersions, syncState, lastSync,
       consistencyVector, lastQuery, migrationCopiedVersion,
       shardNode, migrationState, migrationTarget,
       migrationRequests, replicaReady, lastMigration >>

Init ==
    /\ CoreAssumption
    /\ AuthAssumption
    /\ MigrateAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitSync
    /\ InitQuery
    /\ InitMigrate


DoAssignWrite(u, c) ==
    /\ AssignWriteTSO(u, c)
    /\ UNCHANGED
        <<syncedVersions, syncState, lastSync, consistencyVector,
          lastQuery, migrationCopiedVersion, shardNode,
          migrationState, migrationTarget, migrationRequests,
          replicaReady, lastMigration>>

NextAssignWrite ==
    \E u \in Users,
       c \in Collections :
        DoAssignWrite(u, c)

DoCommitWAL(s) ==
    /\ CommitWAL(s)

    /\ UNCHANGED
        <<syncedVersions, syncState, lastSync, consistencyVector,
          lastQuery, migrationCopiedVersion, shardNode,
          migrationState, migrationTarget, migrationRequests,
          replicaReady, lastMigration>>

NextCommitWAL ==
    \E s \in Shards :
        DoCommitWAL(s)

DoStartSync(n, s) ==
    /\ StartSync(n, s)
    /\ UNCHANGED <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
                   lastWrite, consistencyVector, lastQuery, migrationCopiedVersion,
                   shardNode,migrationState, migrationTarget,
                   migrationRequests, replicaReady, lastMigration>>

NextStartSync ==
    \E n \in Nodes, s \in Shards :
        DoStartSync(n, s)

DoPullSync(n, s) ==
    /\ PullSync(n, s)
    /\ UNCHANGED <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
                   lastWrite, consistencyVector, lastQuery, migrationCopiedVersion,
                   shardNode,migrationState, migrationTarget,
                   migrationRequests, replicaReady, lastMigration>>

NextPullSync ==
    \E n \in Nodes, s \in Shards :
        DoPullSync(n, s)

DoFinishSync(n, s) ==
    /\ FinishSync(n, s)
    /\ UNCHANGED <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
                   lastWrite, consistencyVector, lastQuery, migrationCopiedVersion,
                   shardNode,migrationState, migrationTarget,
                   migrationRequests, replicaReady, lastMigration>>

NextFinishSync ==
    \E n \in Nodes, s \in Shards :
        DoFinishSync(n, s)

DoQuery(u, c, level) ==
    /\ QueryExecute(u, shardNode[ShardFor(c)], c, level)
    /\ UNCHANGED <<tsoVector, versionVector, sessionWriteTs,
                   pendingWrites, lastWrite, syncedVersions,
                   syncState, lastSync, migrationCopiedVersion,
                   shardNode, migrationState, migrationTarget,
                   migrationRequests, replicaReady, lastMigration>>

NextQuery ==
    \E u \in Users,
       c \in Collections,
       level \in ConsistencyLevels :
        DoQuery(u, c, level)

DoStartMigration(u, s, n) ==
    /\ StartMigration(u, s, n)
    /\ UNCHANGED <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
                   lastWrite, syncedVersions, syncState, lastSync,
                   consistencyVector, lastQuery>>

NextStartMigration ==
    \E u \in Users, s \in Shards, n \in Nodes :
        DoStartMigration(u, s, n)

DoAdvanceMigration(u, s) ==
    /\ AdvanceMigrationCopy(u, s)
    /\ UNCHANGED <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
                   lastWrite, syncedVersions, syncState, lastSync,
                   consistencyVector, lastQuery>>

DoActivateTargetReplica(u, s) ==
    /\ ActivateTargetReplica(u, s)

    /\ UNCHANGED
        <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
          lastWrite, syncedVersions, syncState, lastSync,
          consistencyVector, lastQuery>>


NextActivateTargetReplica ==
    \E u \in Users,
       s \in Shards :
        DoActivateTargetReplica(u, s)

NextAdvanceMigration ==
    \E u \in Users, s \in Shards :
        DoAdvanceMigration(u, s)

DoFinishMigration(u, s) ==
    /\ FinishMigration(u, s)
    /\ UNCHANGED <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
                   lastWrite, syncedVersions, syncState, lastSync,
                   consistencyVector, lastQuery>>

NextFinishMigration ==
    \E u \in Users, s \in Shards :
        DoFinishMigration(u, s)

Next ==
    \/ NextAssignWrite
    \/ NextCommitWAL
    \/ NextStartSync
    \/ NextPullSync
    \/ NextFinishSync
    \/ NextQuery
    \/ NextStartMigration
    \/ NextAdvanceMigration
    \/ NextActivateTargetReplica
    \/ NextFinishMigration

Fairness ==
    /\ \A n \in Nodes, s \in Shards :
        WF_Vars(DoStartSync(n, s))
    /\ \A n \in Nodes, s \in Shards :
        WF_Vars(DoPullSync(n, s))
    /\ \A n \in Nodes, s \in Shards :
        WF_Vars(DoFinishSync(n, s))
    /\ \A u \in Users, s \in Shards, n \in Nodes :
        WF_Vars(DoStartMigration(u, s, n))
    /\ \A u \in Users, s \in Shards :
        WF_Vars(DoAdvanceMigration(u, s))
    /\ \A u \in Users, s \in Shards :
        WF_Vars(DoActivateTargetReplica(u, s))
    /\ \A u \in Users, s \in Shards :
        WF_Vars(DoFinishMigration(u, s))

SafetySpec ==
    /\ Init
    /\ [][Next]_Vars

LivenessSpec ==
    /\ Init
    /\ [][Next]_Vars
    /\ Fairness

Spec ==
    SafetySpec

GlobalTypeInvariant ==
    /\ AuthTypeInvariant
    /\ WriteTypeInvariant
    /\ SyncTypeInvariant
    /\ QueryTypeInvariant
    /\ MigrateTypeInvariant

PermissionSafety ==
    /\ LastWriteAuthorized
    /\ LastQueryAuthorized
    /\ LastMigrationAuthorized

WriteSafety ==
    /\ WALNotAheadOfTSO
    /\ IdleWriteFullyCommitted
    /\ PendingWriteValid

ReadConsistencySafety ==
    /\ QueryNotAheadOfSync
    /\ LastQuerySafe
    /\ StrongReadSafe
    /\ BoundedReadSafe
    /\ SessionReadSafe
    /\ EventuallyReadSafe

SyncSafety ==
    /\ SyncNotAheadOfWrite
    /\ LastSyncValid

MigrationSafety ==
    /\ MigrationNotAheadOfWrite
    /\ MigrationRouteSafe
    /\ MigrationTargetSafe
    /\ MigrationQuerySafe
    /\ StableReplicaReady
    /\ ReadyTargetSafe
    /\ MigrationRouteFrontierSafe
    /\ MigrationTargetFrontierSafe

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ PermissionSafety
    /\ WriteSafety
    /\ ReadConsistencySafety
    /\ SyncSafety
    /\ MigrationSafety
    /\ FrontierInterfaceInvariant

SyncEventuallyCatchesUp ==
    \A n \in Nodes, s \in Shards, v \in VersionT :
        v <= versionVector[s]
        ~>
        v <= syncedVersions[n][s]

MigrationEventuallyFinishes ==
    \A s \in Shards :
        migrationState[s] = "Migrating"
        ~>
        migrationState[s] = "Stable"

=============================================================================
