------------------------------- MODULE QMigrate -------------------------------

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
    <<shardOwner, shardLocation, migrateState, migrateSrc,
      migrateDst, copiedData, lastMigrate>>

MigrateRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      shard      : Shards,
      srcNode    : Nodes,
      dstNode    : Nodes,
      phase      : {"Start", "Advance", "Activate", "Finish"},
      authorized : BOOLEAN ]

MigrationSafe(pt) ==
    pt \in shardData[pointShard[pt]]

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ lastMigrate \in MigrateRecordT
    /\ \A s \in Shards : shardOwner[s] \in shardLocation[s]

InitMigrate ==
    LET default_owner == [s \in Shards |-> CHOOSE n \in Nodes : TRUE]
    IN
    /\ shardOwner = default_owner
    /\ shardLocation = [s \in Shards |-> {shardOwner[s]}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = default_owner
    /\ migrateDst = default_owner
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate =
        [ kind       |-> "None",
          principal  |-> CHOOSE p \in Principals : TRUE,
          shard      |-> CHOOSE s \in Shards : TRUE,
          srcNode    |-> CHOOSE n \in Nodes : TRUE,
          dstNode    |-> CHOOSE n \in Nodes : TRUE,
          phase      |-> "Start",
          authorized |-> FALSE ]

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
          srcNode    |-> src,
          dstNode    |-> dst,
          phase      |-> "Start",
          authorized |-> TRUE ]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

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
          srcNode    |-> src,
          dstNode    |-> dst,
          phase      |-> "Start",
          authorized |-> FALSE ]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

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
          srcNode    |-> migrateSrc[s],
          dstNode    |-> migrateDst[s],
          phase      |-> "Advance",
          authorized |-> TRUE ]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

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
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          srcNode    |-> migrateSrc[s],
          dstNode    |-> migrateDst[s],
          phase      |-> "Activate",
          authorized |-> TRUE ]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, lastWrite>>

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ shardOwner' = shardOwner
    /\ shardData' = shardData
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          srcNode    |-> migrateSrc[s],
          dstNode    |-> migrateDst[s],
          phase      |-> "Finish",
          authorized |-> TRUE ]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, lastWrite>>

NextMigrate ==
    \/ \E p \in Principals, s \in Shards, src \in Nodes, dst \in Nodes :
          StartMigrate(p, s, src, dst)
    \/ \E p \in Principals, s \in Shards, src \in Nodes, dst \in Nodes :
          RejectMigrate(p, s, src, dst)
    \/ \E p \in Principals, s \in Shards :
          AdvanceMigrate(p, s)
    \/ \E p \in Principals, s \in Shards :
          ActivateMigrate(p, s)
    \/ \E p \in Principals, s \in Shards :
          FinishMigrate(p, s)

=============================================================================
