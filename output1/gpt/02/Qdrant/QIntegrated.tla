---------------------------- MODULE QIntegrated ----------------------------

EXTENDS QFrontierInterface, QCfgHelpers

GlobalVars ==
    <<permission,
      writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
      shardOwner, shardLocation, migrateState, migrateSrc, migrateDst,
      copiedData, lastMigrate,
      searchResult, lastSearch>>

Init ==
    /\ CoreAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitSearch

NoSuccessfulSearchPending ==
    lastSearch.kind # "Search"

IntegratedAuthAction ==
    /\ NoSuccessfulSearchPending
    /\ NextAuth
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData,
                   lastWrite, shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, copiedData, lastMigrate,
                   searchResult, lastSearch>>

IntegratedWriteAction ==
    /\ NoSuccessfulSearchPending
    /\ NextWrite
    /\ UNCHANGED <<permission,
                   shardOwner, shardLocation, migrateState, migrateSrc,
                   migrateDst, copiedData, lastMigrate,
                   searchResult, lastSearch>>

IntegratedMigrateAction ==
    /\ NoSuccessfulSearchPending
    /\ NextMigrate
    /\ UNCHANGED <<permission,
                   writeState, wal, applied, ackSet, replicaHas, shardData,
                   lastWrite,
                   searchResult, lastSearch>>

IntegratedSearchAction ==
    /\ NextSearch
    /\ UNCHANGED <<permission,
                   writeState, wal, applied, ackSet, replicaHas, shardData,
                   lastWrite,
                   shardOwner, shardLocation, migrateState, migrateSrc,
                   migrateDst, copiedData, lastMigrate>>

Next ==
    \/ IntegratedAuthAction
    \/ IntegratedWriteAction
    \/ IntegratedMigrateAction
    \/ IntegratedSearchAction

Spec ==
    Init /\ [][Next]_GlobalVars

GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ ReplicaTypeOK
    /\ MigrateTypeOK
    /\ SearchTypeOK

AuthSafety ==
    /\ (lastWrite.kind = "Receive" =>
            lastWrite.authorized = TRUE)
    /\ (lastWrite.kind = "Reject" =>
            lastWrite.authorized = FALSE)
    /\ (lastMigrate.kind = "Migrate" =>
            lastMigrate.authorized = TRUE)
    /\ (lastMigrate.kind = "Reject" =>
            lastMigrate.authorized = FALSE)
    /\ (lastSearch.kind = "Search" =>
            /\ lastSearch.authorized = TRUE
            /\ lastSearch.executed = TRUE)
    /\ (lastSearch.kind = "Reject" =>
            /\ lastSearch.authorized = FALSE
            /\ lastSearch.executed = FALSE)

WalBeforeApply ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A r \in Replicas :
        replicaHas[r] \subseteq wal

MigrateSafety ==
    /\ \A s \in Shards :
        shardOwner[s] \in shardLocation[s]
    /\ \A s \in Shards :
        applied \cap PointsOfShard(s) \subseteq shardData[s]
    /\ \A s \in Shards :
        migrateState[s] = "Migratering" =>
            /\ migrateSrc[s] = shardOwner[s]
            /\ migrateDst[s] # migrateSrc[s]
            /\ migrateDst[s] \in shardLocation[s]
            /\ copiedData[s] \subseteq shardData[s]
    /\ \A s \in Shards :
        migrateState[s] = "Activated" =>
            /\ shardOwner[s] = migrateDst[s]
            /\ migrateDst[s] # migrateSrc[s]
            /\ shardOwner[s] \in shardLocation[s]
    /\ \A s \in Shards :
        migrateState[s] = "Stable" =>
            copiedData[s] = {}

=============================================================================
