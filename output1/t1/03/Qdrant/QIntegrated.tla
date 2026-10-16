------------------------------- MODULE QIntegrated --------------------------

EXTENDS QFrontierInterface, QCfgHelpers

\* Global variables
GlobalVars ==
    << permission,
       writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
       shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
       searchResult, lastSearch >>

\* Initial condition
Init ==
    /\ CoreAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitSearch

\* Integrated actions with full UNCHANGED frames

IntegratedAuthAction ==
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
          GrantPermission(admin, target, c, op)
          /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                         searchResult, lastSearch>>
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
          RevokePermission(admin, target, c, op)
          /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                         searchResult, lastSearch>>

IntegratedWriteAction ==
    \/ \E p \in Principals, pt \in Points :
          ReceiveWrite(p, pt)
          /\ UNCHANGED <<permission,
                         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                         searchResult, lastSearch>>
    \/ \E p \in Principals, pt \in Points :
          RejectWrite(p, pt)
          /\ UNCHANGED <<permission,
                         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                         searchResult, lastSearch>>
    \/ \E pt \in Points, r \in Replicas :
          ReplicaAck(pt, r)
          /\ UNCHANGED <<permission,
                         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                         searchResult, lastSearch>>
    \/ \E pt \in Points :
          CommitWrite(pt)
          /\ UNCHANGED <<permission,
                         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                         searchResult, lastSearch>>
    \/ \E pt \in Points, r \in Replicas :
          SyncReplica(pt, r)
          /\ UNCHANGED <<permission,
                         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
                         searchResult, lastSearch>>

IntegratedMigrateAction ==
    \/ \E p \in Principals, s \in Shards, src, dst \in Nodes :
          StartMigrate(p, s, src, dst)
          /\ UNCHANGED <<permission,
                         writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                         searchResult, lastSearch>>
    \/ \E p \in Principals, s \in Shards, src, dst \in Nodes :
          RejectMigrate(p, s, src, dst)
          /\ UNCHANGED <<permission,
                         writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                         searchResult, lastSearch>>
    \/ \E p \in Principals, s \in Shards :
          AdvanceMigrate(p, s)
          /\ UNCHANGED <<permission,
                         writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                         searchResult, lastSearch>>
    \/ \E p \in Principals, s \in Shards :
          ActivateMigrate(p, s)
          /\ UNCHANGED <<permission,
                         writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                         searchResult, lastSearch>>
    \/ \E p \in Principals, s \in Shards :
          FinishMigrate(p, s)
          /\ UNCHANGED <<permission,
                         writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                         searchResult, lastSearch>>

IntegratedSearchAction ==
    \/ \E p \in Principals, c \in Collections, level \in ReadConsistencyLevels :
          Search(p, c, level)
          /\ UNCHANGED <<permission,
                         writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>
    \/ \E p \in Principals, c \in Collections, level \in ReadConsistencyLevels :
          RejectSearch(p, c, level)
          /\ UNCHANGED <<permission,
                         writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>

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

\* Authorization safety
AuthSafety ==
    /\ (lastWrite.kind = "Some") => (lastWrite.authorized = TRUE)
    /\ (lastSearch.kind = "Some") => (lastSearch.authorized = TRUE)
    /\ (lastMigrate.kind = "Some") => (lastMigrate.authorized = TRUE)

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
          \/ migrateState[s] = "Stable"
          \/ /\ migrateState[s] = "Migratering"
             /\ applied \cap PointsOfShard(s) \subseteq copiedData[s]
             /\ migrateSrc[s] = shardOwner[s]
             /\ migrateDst[s] \in Nodes
             /\ migrateDst[s] \neq migrateSrc[s]
          \/ /\ migrateState[s] = "Activated"
             /\ shardOwner[s] = migrateDst[s]
             /\ shardData[s] \supseteq (applied \cap PointsOfShard(s))

=============================================================================
