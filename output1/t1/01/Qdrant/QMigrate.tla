----------------------------- MODULE QMigrate -----------------------------

EXTENDS QReplica

VARIABLES
    shardOwner,
    shardLocation,
    migrateState,
    migrateSrc,
    migrateDst,
    copiedData,
    lastMigrate

MigrateVars == <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>

MigrateRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      shard      : Shards,
      src        : Nodes,
      dst        : Nodes,
      phase      : {"Start", "Advance", "Activate", "Finish"},
      authorized : BOOLEAN,
      executed   : BOOLEAN ]

InitMigrate ==
    LET initialOwner == CHOOSE n \in Nodes : TRUE IN
    /\ shardOwner = [s \in Shards |-> initialOwner]
    /\ shardLocation = [s \in Shards |-> {initialOwner}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = [s \in Shards |-> initialOwner]
    /\ migrateDst = [s \in Shards |-> initialOwner]
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate = [kind       |-> "None",
                       principal  |-> CHOOSE p \in Principals : TRUE,
                       shard      |-> CHOOSE s \in Shards : TRUE,
                       src        |-> initialOwner,
                       dst        |-> initialOwner,
                       phase      |-> "Start",
                       authorized |-> FALSE,
                       executed   |-> FALSE]

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ lastMigrate \in MigrateRecordT

MigrationSafe(pt) ==
    pt \in shardData[pointShard[pt]]

StartMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Stable"
    /\ src = shardOwner[s]
    /\ dst \in Nodes
    /\ dst # src
    /\ migrateState' = [migrateState EXCEPT ![s] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![s] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![s] = dst]
    /\ shardLocation' = [shardLocation EXCEPT ![s] = @ \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' = [kind       |-> "Some",
                        principal  |-> p,
                        shard      |-> s,
                        src        |-> src,
                        dst        |-> dst,
                        phase      |-> "Start",
                        authorized |-> TRUE,
                        executed   |-> TRUE]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ ~CanAccess(p, shardCollection[s], "Migrate")
    /\ src = shardOwner[s]
    /\ dst \in Nodes
    /\ dst # src
    /\ lastMigrate' = [kind       |-> "Some",
                        principal  |-> p,
                        shard      |-> s,
                        src        |-> src,
                        dst        |-> dst,
                        phase      |-> "Start",
                        authorized |-> FALSE,
                        executed   |-> FALSE]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                   shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData>>

AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
    /\ lastMigrate' = [kind       |-> "Some",
                        principal  |-> p,
                        shard      |-> s,
                        src        |-> migrateSrc[s],
                        dst        |-> migrateDst[s],
                        phase      |-> "Advance",
                        authorized |-> TRUE,
                        executed   |-> TRUE]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                   shardOwner, shardLocation, migrateState, migrateSrc, migrateDst>>

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ applied \cap PointsOfShard(s) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardData' = [shardData EXCEPT ![s] = copiedData[s]]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Activated"]
    /\ lastMigrate' = [kind       |-> "Some",
                        principal  |-> p,
                        shard      |-> s,
                        src        |-> migrateSrc[s],
                        dst        |-> migrateDst[s],
                        phase      |-> "Activate",
                        authorized |-> TRUE,
                        executed   |-> TRUE]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, lastWrite,
                   shardLocation, migrateSrc, migrateDst, copiedData>>

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' = [kind       |-> "Some",
                        principal  |-> p,
                        shard      |-> s,
                        src        |-> migrateSrc[s],
                        dst        |-> migrateDst[s],
                        phase      |-> "Finish",
                        authorized |-> TRUE,
                        executed   |-> TRUE]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                   shardOwner, migrateSrc, migrateDst>>

NextMigrate ==
    \/ \E p \in Principals, s \in Shards, src, dst \in Nodes :
        StartMigrate(p, s, src, dst)
    \/ \E p \in Principals, s \in Shards, src, dst \in Nodes :
        RejectMigrate(p, s, src, dst)
    \/ \E p \in Principals, s \in Shards :
        AdvanceMigrate(p, s)
    \/ \E p \in Principals, s \in Shards :
        ActivateMigrate(p, s)
    \/ \E p \in Principals, s \in Shards :
        FinishMigrate(p, s)

=============================================================================
