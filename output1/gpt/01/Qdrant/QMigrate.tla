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

LastMigrateT ==
    [ principal  : Principals,
      shard      : Shards,
      source     : Nodes,
      target     : Nodes,
      phase      : {"None", "Start", "Reject", "Advance", "Activate", "Finish"},
      authorized : BOOLEAN ]

InitMigrate ==
    LET initialOwner == CHOOSE n \in Nodes : TRUE IN
    /\ shardOwner = [s \in Shards |-> initialOwner]
    /\ shardLocation = [s \in Shards |-> {initialOwner}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = [s \in Shards |-> initialOwner]
    /\ migrateDst = [s \in Shards |-> initialOwner]
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate =
        [ principal  |-> CHOOSE p \in Principals : TRUE,
          shard      |-> CHOOSE s \in Shards : TRUE,
          source     |-> initialOwner,
          target     |-> initialOwner,
          phase      |-> "None",
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
    /\ shardOwner' = shardOwner
    /\ shardLocation' =
        [shardLocation EXCEPT ![s] = @ \cup {dst}]
    /\ migrateState' =
        [migrateState EXCEPT ![s] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![s] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![s] = dst]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' =
        [ principal  |-> p,
          shard      |-> s,
          source     |-> src,
          target     |-> dst,
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
        [ principal  |-> p,
          shard      |-> s,
          source     |-> src,
          target     |-> dst,
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
    /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
    /\ lastMigrate' =
        [ principal  |-> p,
          shard      |-> s,
          source     |-> migrateSrc[s],
          target     |-> migrateDst[s],
          phase      |-> "Advance",
          authorized |-> TRUE ]

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ applied \cap PointsOfShard(s) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardLocation' = shardLocation
    /\ migrateState' =
        [migrateState EXCEPT ![s] = "Activated"]
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ copiedData' = copiedData
    /\ shardData' = [shardData EXCEPT ![s] = copiedData[s]]
    /\ lastMigrate' =
        [ principal  |-> p,
          shard      |-> s,
          source     |-> migrateSrc[s],
          target     |-> migrateDst[s],
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
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ shardData' = shardData
    /\ lastMigrate' =
        [ principal  |-> p,
          shard      |-> s,
          source     |-> migrateSrc[s],
          target     |-> migrateDst[s],
          phase      |-> "Finish",
          authorized |-> TRUE ]

MigrationSafe(pt) ==
    /\ pt \in Points
    /\ pt \in shardData[pointShard[pt]]

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

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ lastMigrate \in LastMigrateT
    /\ \A s \in Shards :
        copiedData[s] \subseteq PointsOfShard(s)

=============================================================================
