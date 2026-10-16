------------------------------- MODULE QMigrate ----------------------------

EXTENDS QReplica

VARIABLES
    shardOwner,
    shardLocation,
    migrateState,
    migrateSrc,
    migrateDst,
    copiedData,
    lastMigrate

MigrateVars == <<shardOwner, shardLocation, migrateState,
                  migrateSrc, migrateDst, copiedData, lastMigrate>>

MigrateRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      collection : Collections,
      shard      : Shards,
      phase      : {"Start", "Advance", "Activate", "Finish"},
      authorized : BOOLEAN ]

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ lastMigrate \in MigrateRecordT

InitMigrate ==
    /\ \E nodeAssignment \in [Shards -> Nodes] :
          /\ shardOwner = nodeAssignment
          /\ shardLocation = [s \in Shards |-> {nodeAssignment[s]}]
          /\ migrateState = [s \in Shards |-> "Stable"]
          /\ migrateSrc = nodeAssignment
          /\ migrateDst = nodeAssignment
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate = [kind |-> "None",
                       principal |-> CHOOSE p \in Principals : TRUE,
                       collection |-> CHOOSE c \in Collections : TRUE,
                       shard |-> CHOOSE s \in Shards : TRUE,
                       phase |-> "Start",
                       authorized |-> FALSE]

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
    /\ shardLocation' = [shardLocation EXCEPT ![s] = shardLocation[s] \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ UNCHANGED <<shardOwner, shardData>>
    /\ lastMigrate' = [kind |-> "Some", principal |-> p,
                        collection |-> shardCollection[s],
                        shard |-> s,
                        phase |-> "Start",
                        authorized |-> TRUE]

RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ ~CanAccess(p, shardCollection[s], "Migrate")
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, copiedData, shardData>>
    /\ lastMigrate' = [kind |-> "Some", principal |-> p,
                        collection |-> shardCollection[s],
                        shard |-> s,
                        phase |-> "Start",
                        authorized |-> FALSE]

AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ migrateState[s] = "Migratering"
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, shardData>>
    /\ lastMigrate' = [kind |-> "Some", principal |-> p,
                        collection |-> shardCollection[s],
                        shard |-> s,
                        phase |-> "Advance",
                        authorized |-> TRUE]

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ migrateState[s] = "Migratering"
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ applied \cap PointsOfShard(s) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardData' = [shardData EXCEPT ![s] = copiedData[s]]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Activated"]
    /\ UNCHANGED <<shardLocation, migrateSrc, migrateDst, copiedData>>
    /\ lastMigrate' = [kind |-> "Some", principal |-> p,
                        collection |-> shardCollection[s],
                        shard |-> s,
                        phase |-> "Activate",
                        authorized |-> TRUE]

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ migrateState[s] = "Activated"
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ shardLocation' = [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ UNCHANGED <<shardOwner, shardData, migrateSrc, migrateDst>>
    /\ lastMigrate' = [kind |-> "Some", principal |-> p,
                        collection |-> shardCollection[s],
                        shard |-> s,
                        phase |-> "Finish",
                        authorized |-> TRUE]

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

=============================================================================
