----------------------------- MODULE QMigrate -------------------------

EXTENDS QReplica

VARIABLES
    shardOwner,
    shardLocation,
    migrateState,
    migrateSrc,
    migrateDst,
    copiedData,
    lastMigrate

MigrateVars ==
    <<shardOwner, shardLocation, migrateState,
      migrateSrc, migrateDst, copiedData, lastMigrate>>

MigrateRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      shard      : Shards,
      src        : Nodes,
      dst        : Nodes,
      authorized : BOOLEAN,
      phase      : {"Start", "Advance", "Activate", "Finish"} ]

InitMigrate ==
    /\ \E ownerFn \in [Shards -> Nodes] :
        /\ shardOwner = ownerFn
        /\ shardLocation = [s \in Shards |-> {ownerFn[s]}]
        /\ migrateState = [s \in Shards |-> "Stable"]
        /\ migrateSrc = [s \in Shards |-> CHOOSE n \in Nodes : TRUE]
        /\ migrateDst = [s \in Shards |-> CHOOSE n \in Nodes : TRUE]
        /\ copiedData = [s \in Shards |-> {}]
        /\ lastMigrate =
            [ kind       |-> "None",
              principal  |-> CHOOSE p \in Principals : TRUE,
              shard      |-> CHOOSE s \in Shards : TRUE,
              src        |-> CHOOSE n \in Nodes : TRUE,
              dst        |-> CHOOSE n \in Nodes : TRUE,
              authorized |-> FALSE,
              phase      |-> "Start" ]

StartMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ src \in Nodes
    /\ dst \in Nodes
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Stable"
    /\ src = shardOwner[s]
    /\ dst # src
    /\ migrateState' = [migrateState EXCEPT ![s] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![s] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![s] = dst]
    /\ shardLocation' = [shardLocation EXCEPT ![s] = @ \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ shardOwner' = shardOwner
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          src        |-> src,
          dst        |-> dst,
          authorized |-> TRUE,
          phase      |-> "Start" ]

RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ src \in Nodes
    /\ dst \in Nodes
    /\ ~CanAccess(p, shardCollection[s], "Migrate")
    /\ shardOwner' = shardOwner
    /\ shardLocation' = shardLocation
    /\ migrateState' = migrateState
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ copiedData' = copiedData
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          src        |-> src,
          dst        |-> dst,
          authorized |-> FALSE,
          phase      |-> "Start" ]

AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
    /\ shardOwner' = shardOwner
    /\ shardLocation' = shardLocation
    /\ migrateState' = migrateState
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          src        |-> migrateSrc[s],
          dst        |-> migrateDst[s],
          authorized |-> TRUE,
          phase      |-> "Advance" ]

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ (applied \cap PointsOfShard(s)) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardData' = [shardData EXCEPT ![s] = copiedData[s]]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Activated"]
    /\ shardLocation' = shardLocation
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ copiedData' = copiedData
    /\ writeState' = writeState
    /\ wal' = wal
    /\ applied' = applied
    /\ ackSet' = ackSet
    /\ replicaHas' = replicaHas
    /\ lastWrite' = lastWrite
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          src        |-> migrateSrc[s],
          dst        |-> migrateDst[s],
          authorized |-> TRUE,
          phase      |-> "Activate" ]

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ shardOwner' = shardOwner
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          src        |-> migrateSrc[s],
          dst        |-> migrateDst[s],
          authorized |-> TRUE,
          phase      |-> "Finish" ]

MigrationSafe(pt) ==
    pt \in shardData[pointShard[pt]]

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

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ lastMigrate \in MigrateRecordT

MigrateSafety ==
    \A pt \in applied : MigrationSafe(pt)

=============================================================================
