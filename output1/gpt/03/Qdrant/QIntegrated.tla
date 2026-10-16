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

IntegratedAuthAction ==
    /\ NextAuth
    /\ UNCHANGED
        <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
          shardOwner, shardLocation, migrateState, migrateSrc, migrateDst,
          copiedData, lastMigrate,
          searchResult, lastSearch>>

IntegratedWriteAction ==
    /\ NextWrite
    /\ UNCHANGED
        <<permission,
          shardOwner, shardLocation, migrateState, migrateSrc, migrateDst,
          copiedData, lastMigrate,
          searchResult, lastSearch>>

IntegratedMigrateAction ==
    /\ NextMigrate
    /\ UNCHANGED
        <<permission,
          writeState, wal, applied, ackSet, replicaHas, lastWrite,
          searchResult, lastSearch>>

IntegratedSearchAction ==
    /\ NextSearch
    /\ UNCHANGED
        <<permission,
          writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
          shardOwner, shardLocation, migrateState, migrateSrc, migrateDst,
          copiedData, lastMigrate>>

Next ==
    \/ IntegratedAuthAction
    \/ IntegratedWriteAction
    \/ IntegratedMigrateAction
    \/ IntegratedSearchAction

Spec == Init /\ [][Next]_GlobalVars

GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ ReplicaTypeOK
    /\ MigrateTypeOK
    /\ SearchTypeOK

AuthSafety ==
    /\ (lastWrite.kind = "Receive" => lastWrite.authorized = TRUE)
    /\ (lastWrite.authorized = FALSE =>
            lastWrite.kind \in {"None", "Reject"})
    /\ (lastSearch.kind = "Search" => lastSearch.authorized = TRUE)
    /\ (lastSearch.authorized = FALSE =>
            lastSearch.kind \in {"None", "Reject"})
    /\ (lastMigrate.kind \in {"Start", "Advance", "Activate", "Finish"}
            => lastMigrate.authorized = TRUE)
    /\ (lastMigrate.authorized = FALSE =>
            lastMigrate.kind \in {"None", "Reject"})

WalBeforeApply ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A r \in Replicas :
        replicaHas[r] \subseteq wal

MigrateSafety ==
    /\ \A s \in Shards :
        shardOwner[s] \in shardLocation[s]
    /\ \A s \in Shards :
        migrateState[s] = "Migratering" =>
            /\ migrateSrc[s] = shardOwner[s]
            /\ migrateDst[s] # migrateSrc[s]
            /\ migrateDst[s] \in shardLocation[s]
    /\ \A s \in Shards :
        migrateState[s] = "Activated" =>
            /\ shardOwner[s] = migrateDst[s]
            /\ migrateDst[s] # migrateSrc[s]
    /\ \A s \in Shards :
        copiedData[s] \subseteq shardData[s]
    /\ \A s \in Shards :
        applied \cap PointsOfShard(s) \subseteq shardData[s]

=============================================================================
