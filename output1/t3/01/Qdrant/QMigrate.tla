--------------------------- MODULE QMigrate ---------------------------

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

InitMigrate ==
    LET initOwner == CHOOSE n \in Nodes : TRUE
    IN
    /\ shardOwner   = [s \in Shards |-> initOwner]
    /\ shardLocation = [s \in Shards |-> {shardOwner[s]}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc   = shardOwner
    /\ migrateDst   = shardOwner
    /\ copiedData    = [s \in Shards |-> {}]
    /\ lastMigrate  = [kind       |-> "None",
                        principal  |-> CHOOSE p \in Principals : TRUE,
                        shard      |-> CHOOSE s \in Shards : TRUE,
                        phase      |-> "Start",
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
    /\ migrateSrc'   = [migrateSrc EXCEPT ![s] = src]
    /\ migrateDst'   = [migrateDst EXCEPT ![s] = dst]
    /\ shardLocation' = [shardLocation EXCEPT ![s] =
                            shardLocation[s] \cup {dst}]
    /\ copiedData'    = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate'  = [kind       |-> "Some",
                         principal  |-> p,
                         shard      |-> s,
                         phase      |-> "Start",
                         authorized |-> TRUE]
    /\ UNCHANGED <<shardOwner>>

RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ src \in Nodes
    /\ dst \in Nodes
    /\ ~CanAccess(p, shardCollection[s], "Migrate")
    /\ lastMigrate' = [kind       |-> "Some",
                        principal  |-> p,
                        shard      |-> s,
                        phase      |-> "Start",
                        authorized |-> FALSE]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, copiedData>>

AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
    /\ lastMigrate' = [kind       |-> "Some",
                        principal  |-> p,
                        shard      |-> s,
                        phase      |-> "Advance",
                        authorized |-> TRUE]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst>>

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ applied \cap PointsOfShard(s) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardData'  = [shardData EXCEPT ![s] = copiedData[s]]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Activated"]
    /\ lastMigrate' = [kind       |-> "Some",
                        principal  |-> p,
                        shard      |-> s,
                        phase      |-> "Activate",
                        authorized |-> TRUE]
    /\ UNCHANGED <<shardLocation, migrateSrc, migrateDst, copiedData>>

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData'    = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate'  = [kind       |-> "Some",
                         principal  |-> p,
                         shard      |-> s,
                         phase      |-> "Finish",
                         authorized |-> TRUE]
    /\ UNCHANGED <<shardOwner, shardData, migrateSrc, migrateDst>>

MigrationSafe(pt) ==
    pt \in shardData[pointShard[pt]]

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
    /\ shardOwner   \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc   \in [Shards -> Nodes]
    /\ migrateDst   \in [Shards -> Nodes]
    /\ copiedData    \in [Shards -> SUBSET Points]
    /\ lastMigrate  \in [kind       : {"None","Some"},
                          principal  : Principals,
                          shard      : Shards,
                          phase      : {"Start","Advance","Activate","Finish"},
                          authorized : BOOLEAN]

MigrateSafety ==
    /\ \A s \in Shards :
        \/ (migrateState[s] = "Stable") =>
            (shardOwner[s] = migrateSrc[s] /\ shardOwner[s] = migrateDst[s])
        \/ (migrateState[s] = "Migratering") =>
            (shardOwner[s] = migrateSrc[s] /\ migrateDst[s] # shardOwner[s])
        \/ (migrateState[s] = "Activated") =>
            (shardOwner[s] = migrateDst[s] /\ shardOwner[s] # migrateSrc[s])

=============================================================================
