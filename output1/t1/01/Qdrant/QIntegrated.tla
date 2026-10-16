---------------------------- MODULE QIntegrated ----------------------------

EXTENDS QFrontierInterface, QCfgHelpers

GlobalVars ==
    << permission,
       writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
       shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
       searchResult, lastSearch >>

Init ==
    /\ CoreAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitSearch

\* Integrated wrapper actions
IntegratedAuthAction ==
    \/ /\ NextAuth
       /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                      shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                      searchResult, lastSearch>>

IntegratedWriteAction ==
    \/ /\ NextWrite
       /\ UNCHANGED <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                      searchResult, lastSearch>>

IntegratedMigrateAction ==
    \/ /\ NextMigrate
       /\ UNCHANGED <<searchResult, lastSearch>>

IntegratedSearchAction ==
    NextSearch

Next ==
    \/ IntegratedAuthAction
    \/ IntegratedWriteAction
    \/ IntegratedMigrateAction
    \/ IntegratedSearchAction

Spec == Init /\ [][Next]_GlobalVars

\* Global type invariant
GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ ReplicaTypeOK
    /\ MigrateTypeOK
    /\ SearchTypeOK

\* Authorization safety (recorded authorized flag suffices)
AuthSafety ==
    /\ (lastWrite.kind = "None") \/ (lastWrite.authorized = TRUE)
    /\ (lastSearch.kind = "None") \/ (lastSearch.authorized = TRUE)
    /\ (lastMigrate.kind = "None") \/ (lastMigrate.authorized = TRUE)

WalBeforeApply ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A r \in Replicas : replicaHas[r] \subseteq wal

\* Migrate safety (prevents committed data loss during migration)
MigrateSafety ==
    /\ \A s \in Shards : shardOwner[s] \in shardLocation[s]
    /\ \A s \in Shards :
        IF migrateState[s] = "Migratering"
        THEN /\ migrateSrc[s] = shardOwner[s]
             /\ migrateDst[s] # shardOwner[s]
             /\ applied \cap PointsOfShard(s) \subseteq copiedData[s]
        ELSE TRUE
    /\ \A s \in Shards :
        IF migrateState[s] = "Activated"
        THEN applied \cap PointsOfShard(s) \subseteq shardData[s]
        ELSE TRUE
    /\ \A s \in Shards : applied \cap PointsOfShard(s) \subseteq shardData[s]

=============================================================================
