---------------------------- MODULE QIntegrated ----------------------------

EXTENDS QFrontierInterface, QCfgHelpers

GlobalVars ==
    <<permission, writeState, wal, applied, ackSet, replicaHas, shardData,
      lastWrite, shardOwner, shardLocation, migrateState, migrateSrc,
      migrateDst, copiedData, lastMigrate, searchResult, lastSearch>>

Init ==
    /\ CoreAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitSearch

IntegratedAuthAction ==
    /\ NextAuth
    /\ UNCHANGED <<WriteVars, MigrateVars, searchResult>>
    /\ lastSearch' = [lastSearch EXCEPT !.executed = FALSE]

IntegratedWriteAction ==
    /\ NextWrite
    /\ UNCHANGED <<AuthVars, MigrateVars, searchResult>>
    /\ lastSearch' = [lastSearch EXCEPT !.executed = FALSE]

IntegratedMigrateAction ==
    /\ NextMigrate
    /\ UNCHANGED <<AuthVars, WriteVars, searchResult>>
    /\ lastSearch' = [lastSearch EXCEPT !.executed = FALSE]

IntegratedSearchAction ==
    /\ NextSearch
    /\ UNCHANGED <<AuthVars, WriteVars, MigrateVars>>

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
    /\ lastWrite.accepted => lastWrite.authorized
    /\ lastSearch.executed => lastSearch.authorized
    /\ lastMigrate.phase \in {"Start", "Advance", "Activate", "Finish"} =>
        lastMigrate.authorized

WalBeforeApply ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A r \in Replicas :
        replicaHas[r] \subseteq wal

MigrateSafety ==
    /\ \A s \in Shards :
        shardOwner[s] \in shardLocation[s]
    /\ \A s \in Shards :
        migrateState[s] = "Stable" =>
            shardLocation[s] = {shardOwner[s]}

=============================================================================
