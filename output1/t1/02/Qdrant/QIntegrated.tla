--------------------------- MODULE QIntegrated ---------------------------

EXTENDS QFrontierInterface, QCfgHelpers

(********************************************
 * Qdrant Integrated module:
 * Initialisation, global actions, specification,
 * and top‑level safety invariants.
 ********************************************)

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

\* Integrated wrappers

IntegratedAuthAction ==
    \/ /\ NextAuth
       /\ UNCHANGED <<WriteVars, MigrateVars, SearchVars>>

IntegratedWriteAction ==
    \/ /\ NextWrite
       /\ UNCHANGED <<AuthVars, MigrateVars, SearchVars>>

IntegratedMigrateAction ==
    \/ /\ NextMigrate
       /\ UNCHANGED <<AuthVars, WriteVars, SearchVars>>

IntegratedSearchAction ==
    \/ /\ NextSearch
       /\ UNCHANGED <<AuthVars, WriteVars, MigrateVars>>

Next ==
    \/ IntegratedAuthAction
    \/ IntegratedWriteAction
    \/ IntegratedMigrateAction
    \/ IntegratedSearchAction

Spec ==
    Init /\ [][Next]_GlobalVars

\* Global type invariant

GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ ReplicaTypeOK
    /\ MigrateTypeOK
    /\ SearchTypeOK

\* Authorization safety (history‑based)

AuthSafety ==
    /\ (lastWrite.kind = "None")
        \/ (lastWrite.authorized => CanAccess(lastWrite.principal,
                                               lastWrite.collection, "Write"))
    /\ (lastSearch.kind = "None")
        \/ (lastSearch.authorized => CanAccess(lastSearch.principal,
                                                lastSearch.collection, "Read"))
    /\ (lastMigrate.kind = "None")
        \/ (lastMigrate.authorized => CanAccess(lastMigrate.principal,
                                                  shardCollection[lastMigrate.shard],
                                                  "Migrate"))

\* Write safety

WalBeforeApply ==
    applied \subseteq wal

\* Replica safety

ReplicaNotAheadOfWAL ==
    \A r \in Replicas : replicaHas[r] \subseteq wal

\* Migrate safety

MigrateSafety ==
    /\ \A s \in Shards : shardOwner[s] \in shardLocation[s]
    /\ \A s \in Shards :
          (migrateState[s] = "Stable") => (shardLocation[s] = {shardOwner[s]})
    /\ \A s \in Shards :
          (migrateState[s] = "Migratering") =>
             (migrateSrc[s] = shardOwner[s]) /\ (migrateDst[s] # migrateSrc[s])
    /\ \A s \in Shards :
          (migrateState[s] = "Activated") =>
             (shardOwner[s] = migrateDst[s])
    /\ \A s \in Shards :
          (applied \cap PointsOfShard(s)) \subseteq shardData[s]

=============================================================================
