------------------------------ MODULE MMigrate ------------------------------

EXTENDS MQuery

CONSTANTS
    InitialMigrationRequests

VARIABLES
    migrationCopiedVersion,
    shardNode,
    migrationState,
    migrationTarget,
    migrationRequests,
    replicaReady,
    lastMigration

MigrateVars ==
    <<migrationCopiedVersion, shardNode, migrationState,
      migrationTarget, migrationRequests, replicaReady,
      lastMigration>>

MigrationRecordT ==
    [ kind       : {"None", "Some"},
      user       : Users,
      shard      : Shards,
      oldNode    : Nodes,
      newNode    : Nodes,
      version    : VersionT,
      phase      : {"Start", "Advance","Ready", "Finish"},
      authorized : BOOLEAN ]

MigrateAssumption ==
    InitialMigrationRequests \subseteq Users \X Shards \X Nodes

MigrateTypeInvariant ==
    /\ migrationCopiedVersion \in [Shards -> VersionT]
    /\ shardNode \in [Shards -> Nodes]
    /\ migrationState \in [Shards -> MigrationStateT]
    /\ migrationTarget \in [Shards -> Nodes]
    /\ migrationRequests \subseteq Users \X Shards \X Nodes
    /\ replicaReady \in [Nodes -> [Shards -> BOOLEAN]]
    /\ lastMigration \in MigrationRecordT

InitMigrate ==
    /\ migrationCopiedVersion = [s \in Shards |-> 0]
    /\ shardNode \in [Shards -> Nodes]
    /\ migrationState = [s \in Shards |-> "Stable"]
    /\ migrationTarget = shardNode
    /\ migrationRequests = InitialMigrationRequests
    /\ replicaReady = [n \in Nodes |->
                          [s \in Shards |->
                              n = shardNode[s]]]
    /\ lastMigration =
        [ kind       |-> "None",
          user       |-> CHOOSE u \in Users : TRUE,
          shard      |-> CHOOSE s \in Shards : TRUE,
          oldNode    |-> CHOOSE n \in Nodes : TRUE,
          newNode    |-> CHOOSE n \in Nodes : TRUE,
          version    |-> 0,
          phase      |-> "Start",
          authorized |-> FALSE ]


StartMigration(user, s, newNode) ==
    /\ user \in Users
    /\ s \in Shards
    /\ newNode \in Nodes

    /\ <<user, s, newNode>>
        \in migrationRequests

    /\ newNode # shardNode[s]

    /\ CanMigrate(user)

    /\ migrationState[s] = "Stable"

    /\ syncedVersions[newNode][s]
        >= migrationCopiedVersion[s]

    /\ migrationState' =
        [migrationState EXCEPT
            ![s] = "Migrating"]

    /\ migrationTarget' =
        [migrationTarget EXCEPT
            ![s] = newNode]

    /\ migrationRequests' =
        migrationRequests
            \ {<<user, s, newNode>>}

    /\ replicaReady' =
        [replicaReady EXCEPT
            ![newNode][s] = FALSE]

    /\ UNCHANGED
        <<migrationCopiedVersion,  shardNode>>

    /\ lastMigration' =
        [ kind       |-> "Some",
          user       |-> user,
          shard      |-> s,
          oldNode    |-> shardNode[s],
          newNode    |-> newNode,
          version    |-> migrationCopiedVersion[s],
          phase      |-> "Start",
          authorized |-> TRUE ]


AdvanceMigrationCopy(user, s) ==
    /\ user \in Users
    /\ s \in Shards

    /\ CanMigrate(user)

    /\ migrationState[s] = "Migrating"

    /\ migrationCopiedVersion[s]
        < versionVector[s]

    /\ syncedVersions[migrationTarget[s]][s]
        >= migrationCopiedVersion[s] + 1

    /\ migrationCopiedVersion' =
        [migrationCopiedVersion EXCEPT
            ![s] = @ + 1]

    /\ UNCHANGED
        <<shardNode, migrationState, migrationTarget,
          migrationRequests, replicaReady>>

    /\ lastMigration' =
        [ kind       |-> "Some",
          user       |-> user,
          shard      |-> s,
          oldNode    |-> shardNode[s],
          newNode    |-> migrationTarget[s],
          version    |-> migrationCopiedVersion[s] + 1,
          phase      |-> "Advance",
          authorized |-> TRUE ]



ActivateTargetReplica(user, s) ==
    /\ user \in Users
    /\ s \in Shards

    /\ CanMigrate(user)

    /\ migrationState[s] = "Migrating"

    /\ ~replicaReady[migrationTarget[s]][s]

    /\ syncedVersions[migrationTarget[s]][s]
        >= migrationCopiedVersion[s]

    /\ replicaReady' =
        [replicaReady EXCEPT
            ![migrationTarget[s]][s] = TRUE]

    /\ UNCHANGED
        <<migrationCopiedVersion, shardNode, migrationState,
          migrationTarget, migrationRequests>>

    /\ lastMigration' =
        [ kind       |-> "Some",
          user       |-> user,
          shard      |-> s,
          oldNode    |-> shardNode[s],
          newNode    |-> migrationTarget[s],
          version    |-> migrationCopiedVersion[s],
          phase      |-> "Ready",
          authorized |-> TRUE ]


FinishMigration(user, s) ==
    /\ user \in Users
    /\ s \in Shards

    /\ CanMigrate(user)

    /\ migrationState[s] = "Migrating"

    /\ migrationCopiedVersion[s]
        = versionVector[s]

    /\ syncedVersions[migrationTarget[s]][s]
        >= migrationCopiedVersion[s]

    /\ replicaReady[migrationTarget[s]][s]

    /\ \A c \in Collections :
        ShardFor(c) = s
        =>
        consistencyVector[migrationTarget[s]][c]
            <= syncedVersions[migrationTarget[s]][s]

    /\ shardNode' =
        [shardNode EXCEPT
            ![s] = migrationTarget[s]]

    /\ migrationState' =
        [migrationState EXCEPT
            ![s] = "Stable"]


    /\ replicaReady' =
        [replicaReady EXCEPT
            ![shardNode[s]][s] = FALSE,
            ![migrationTarget[s]][s] = TRUE]

    /\ UNCHANGED
        <<migrationTarget, migrationRequests, migrationCopiedVersion>>

    /\ lastMigration' =
        [ kind       |-> "Some",
          user       |-> user,
          shard      |-> s,
          oldNode    |-> shardNode[s],
          newNode    |-> migrationTarget[s],
          version    |-> migrationCopiedVersion[s],
          phase      |-> "Finish",
          authorized |-> TRUE ]


NextMigrate ==
    \/ /\ NextQueryLocal
       /\ UNCHANGED MigrateVars

    \/ /\ \E u \in Users,
             s \in Shards,
             n \in Nodes :
            StartMigration(u, s, n)

       /\ UNCHANGED
            <<tsoVector,
              versionVector,
              sessionWriteTs,
              pendingWrites,
              lastWrite,
              syncedVersions,
              syncState,
              lastSync,
              consistencyVector,
              lastQuery>>

    \/ /\ \E u \in Users,
             s \in Shards :
            AdvanceMigrationCopy(u, s)

       /\ UNCHANGED
            <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
              lastWrite, syncedVersions, syncState, lastSync,
              consistencyVector, lastQuery>>

    \/ /\ \E u \in Users,
             s \in Shards :
            ActivateTargetReplica(u, s)

       /\ UNCHANGED
            <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
              lastWrite, syncedVersions, syncState, lastSync,
              consistencyVector, lastQuery>>

    \/ /\ \E u \in Users,
             s \in Shards :
            FinishMigration(u, s)

       /\ UNCHANGED
            <<tsoVector, versionVector, sessionWriteTs, pendingWrites,
              lastWrite, syncedVersions, syncState, lastSync,
              consistencyVector, lastQuery>>


MigrateSpec ==
    /\ CoreAssumption
    /\ AuthAssumption
    /\ MigrateAssumption

    /\ InitAuth
    /\ InitWrite
    /\ InitSync
    /\ InitQuery
    /\ InitMigrate

    /\ [][NextMigrate]_<<tsoVector, versionVector, sessionWriteTs, pendingWrites,
                         lastWrite, syncedVersions, syncState, lastSync,
                         consistencyVector, lastQuery, migrationCopiedVersion,
                         shardNode, migrationState, migrationTarget, migrationRequests,
                         replicaReady, lastMigration>>


MigrationNotAheadOfWrite ==
    \A s \in Shards :
        migrationCopiedVersion[s]
            <= versionVector[s]


MigrationRouteSafe ==
    \A s \in Shards :
        migrationState[s] = "Stable"
        =>
        syncedVersions[shardNode[s]][s]
            >= migrationCopiedVersion[s]


MigrationTargetSafe ==
    \A s \in Shards :
        migrationState[s] = "Migrating"
        =>
        syncedVersions[migrationTarget[s]][s]
            >= migrationCopiedVersion[s]


MigrationQuerySafe ==
    \A n \in Nodes,
       c \in Collections :

        consistencyVector[n][c]
            <= syncedVersions[n][ShardFor(c)]


StableReplicaReady ==
    \A s \in Shards :
        migrationState[s] = "Stable"
        =>
        replicaReady[shardNode[s]][s]


ReadyTargetSafe ==
    \A s \in Shards :
        /\ migrationState[s] = "Migrating"
        /\ replicaReady[migrationTarget[s]][s]
        =>
        syncedVersions[migrationTarget[s]][s]
            >= migrationCopiedVersion[s]
    
=============================================================================
