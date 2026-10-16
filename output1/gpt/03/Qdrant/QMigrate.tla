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

MigrateRecordT ==
    [ kind       : {"None", "Start", "Reject", "Advance", "Activate", "Finish"},
      principal  : Principals,
      shard      : Shards,
      src        : Nodes,
      dst        : Nodes,
      phase      : {"None", "Start", "Reject", "Advance", "Activate", "Finish"},
      authorized : BOOLEAN ]

InitialMigratePrincipal == CHOOSE p \in Principals : TRUE

InitialMigrateShard == CHOOSE s \in Shards : TRUE

InitialMigrateNode == CHOOSE n \in Nodes : TRUE

InitMigrate ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation =
        [s \in Shards |-> {shardOwner[s]}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = shardOwner
    /\ migrateDst = shardOwner
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate =
        [ kind       |-> "None",
          principal  |-> InitialMigratePrincipal,
          shard      |-> InitialMigrateShard,
          src        |-> InitialMigrateNode,
          dst        |-> InitialMigrateNode,
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
    /\ migrateState' =
        [migrateState EXCEPT ![s] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![s] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![s] = dst]
    /\ shardLocation' =
        [shardLocation EXCEPT ![s] = @ \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' =
        [ kind       |-> "Start",
          principal  |-> p,
          shard      |-> s,
          src        |-> src,
          dst        |-> dst,
          phase      |-> "Start",
          authorized |-> TRUE ]
    /\ UNCHANGED <<shardOwner, shardData>>

RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ src \in Nodes
    /\ dst \in Nodes
    /\ ~CanAccess(p, shardCollection[s], "Migrate")
    /\ lastMigrate' =
        [ kind       |-> "Reject",
          principal  |-> p,
          shard      |-> s,
          src        |-> src,
          dst        |-> dst,
          phase      |-> "Reject",
          authorized |-> FALSE ]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, copiedData, shardData>>

AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
    /\ lastMigrate' =
        [ kind       |-> "Advance",
          principal  |-> p,
          shard      |-> s,
          src        |-> migrateSrc[s],
          dst        |-> migrateDst[s],
          phase      |-> "Advance",
          authorized |-> TRUE ]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, shardData>>

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ applied \cap PointsOfShard(s) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardData' = [shardData EXCEPT ![s] = copiedData[s]]
    /\ migrateState' =
        [migrateState EXCEPT ![s] = "Activated"]
    /\ lastMigrate' =
        [ kind       |-> "Activate",
          principal  |-> p,
          shard      |-> s,
          src        |-> migrateSrc[s],
          dst        |-> migrateDst[s],
          phase      |-> "Activate",
          authorized |-> TRUE ]
    /\ UNCHANGED <<shardLocation, migrateSrc, migrateDst, copiedData>>

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardLocation' =
        [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' =
        [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' =
        [ kind       |-> "Finish",
          principal  |-> p,
          shard      |-> s,
          src        |-> migrateSrc[s],
          dst        |-> migrateDst[s],
          phase      |-> "Finish",
          authorized |-> TRUE ]
    /\ UNCHANGED <<shardOwner, migrateSrc, migrateDst, shardData>>

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

MigrationSafe(pt) ==
    /\ pt \in Points
    /\ pt \in shardData[pointShard[pt]]

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ \A s \in Shards :
        copiedData[s] \subseteq PointsOfShard(s)
    /\ lastMigrate \in MigrateRecordT

=============================================================================
