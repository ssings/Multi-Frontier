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

MigrateVars ==
    <<shardOwner, shardLocation, migrateState, migrateSrc,
      migrateDst, copiedData, lastMigrate>>

InitialNode ==
    CHOOSE n \in Nodes : TRUE

InitialShard ==
    CHOOSE s \in Shards : TRUE

MigrateRecordT ==
    [ kind       : {"None", "Migrate", "Reject"},
      principal  : Principals,
      shard      : Shards,
      src        : Nodes,
      dst        : Nodes,
      phase      : {"None", "Start", "Advance", "Activate",
                    "Finish", "Reject"},
      authorized : BOOLEAN ]

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ lastMigrate \in MigrateRecordT
    /\ \A s \in Shards :
        shardLocation[s] \subseteq Nodes
    /\ \A s \in Shards :
        copiedData[s] \subseteq PointsOfShard(s)

InitMigrate ==
    /\ shardOwner = [s \in Shards |-> InitialNode]
    /\ shardLocation = [s \in Shards |-> {InitialNode}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = [s \in Shards |-> InitialNode]
    /\ migrateDst = [s \in Shards |-> InitialNode]
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate =
        [ kind       |-> "None",
          principal  |-> InitialAdmin,
          shard      |-> InitialShard,
          src        |-> InitialNode,
          dst        |-> InitialNode,
          phase      |-> "None",
          authorized |-> FALSE ]

MigrationSafe(pt) ==
    /\ pt \in Points
    /\ pt \in shardData[pointShard[pt]]

StartMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ src \in Nodes
    /\ dst \in Nodes
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Stable"
    /\ src = shardOwner[s]
    /\ dst # src
    /\ shardOwner' = shardOwner
    /\ shardLocation' =
        [shardLocation EXCEPT ![s] = @ \cup {dst}]
    /\ migrateState' =
        [migrateState EXCEPT ![s] = "Migratering"]
    /\ migrateSrc' =
        [migrateSrc EXCEPT ![s] = src]
    /\ migrateDst' =
        [migrateDst EXCEPT ![s] = dst]
    /\ copiedData' =
        [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' =
        [ kind       |-> "Migrate",
          principal  |-> p,
          shard      |-> s,
          src        |-> src,
          dst        |-> dst,
          phase      |-> "Start",
          authorized |-> TRUE ]

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
        [ kind       |-> "Reject",
          principal  |-> p,
          shard      |-> s,
          src        |-> src,
          dst        |-> dst,
          phase      |-> "Reject",
          authorized |-> FALSE ]

AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ shardOwner' = shardOwner
    /\ shardLocation' = shardLocation
    /\ migrateState' = migrateState
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ copiedData' =
        [copiedData EXCEPT ![s] = shardData[s]]
    /\ lastMigrate' =
        [ kind       |-> "Migrate",
          principal  |-> p,
          shard      |-> s,
          src        |-> migrateSrc[s],
          dst        |-> migrateDst[s],
          phase      |-> "Advance",
          authorized |-> TRUE ]

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ applied \cap PointsOfShard(s) \subseteq copiedData[s]
    /\ shardOwner' =
        [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardLocation' = shardLocation
    /\ migrateState' =
        [migrateState EXCEPT ![s] = "Activated"]
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ copiedData' = copiedData
    /\ lastMigrate' =
        [ kind       |-> "Migrate",
          principal  |-> p,
          shard      |-> s,
          src        |-> migrateSrc[s],
          dst        |-> migrateDst[s],
          phase      |-> "Activate",
          authorized |-> TRUE ]

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardOwner' = shardOwner
    /\ shardLocation' =
        [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' =
        [migrateState EXCEPT ![s] = "Stable"]
    /\ migrateSrc' =
        [migrateSrc EXCEPT ![s] = shardOwner[s]]
    /\ migrateDst' =
        [migrateDst EXCEPT ![s] = shardOwner[s]]
    /\ copiedData' =
        [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' =
        [ kind       |-> "Migrate",
          principal  |-> p,
          shard      |-> s,
          src        |-> migrateSrc[s],
          dst        |-> migrateDst[s],
          phase      |-> "Finish",
          authorized |-> TRUE ]

NextMigrate ==
    \/ \E p \in Principals :
        \E s \in Shards :
            \E src \in Nodes :
                \E dst \in Nodes :
                    StartMigrate(p, s, src, dst)
    \/ \E p \in Principals :
        \E s \in Shards :
            \E src \in Nodes :
                \E dst \in Nodes :
                    RejectMigrate(p, s, src, dst)
    \/ \E p \in Principals :
        \E s \in Shards :
            AdvanceMigrate(p, s)
    \/ \E p \in Principals :
        \E s \in Shards :
            ActivateMigrate(p, s)
    \/ \E p \in Principals :
        \E s \in Shards :
            FinishMigrate(p, s)

=============================================================================
