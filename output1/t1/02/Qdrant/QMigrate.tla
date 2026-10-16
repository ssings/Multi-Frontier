--------------------------- MODULE QMigrate ---------------------------

EXTENDS QReplica

(********************************************
 * Qdrant Migrate module: shard migration.
 ********************************************)

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

InitMigrate ==
    LET defaultNode == CHOOSE n \in Nodes : TRUE IN
    /\ shardOwner = [s \in Shards |-> defaultNode]
    /\ shardLocation = [s \in Shards |-> {shardOwner[s]}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = shardOwner
    /\ migrateDst = shardOwner
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate = [kind |-> "None",
                       principal |-> CHOOSE p \in Principals : TRUE,
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
    /\ shardLocation' = [shardLocation EXCEPT ![s] = @ \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ UNCHANGED <<shardOwner>>
    /\ lastMigrate' = [kind |-> "Some",
                        principal |-> p,
                        shard |-> s,
                        phase |-> "Start",
                        authorized |-> TRUE]

RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ ~CanAccess(p, shardCollection[s], "Migrate")
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                  migrateSrc, migrateDst, copiedData>>
    /\ lastMigrate' = [kind |-> "Some",
                        principal |-> p,
                        shard |-> s,
                        phase |-> "Start",
                        authorized |-> FALSE]

AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                  migrateSrc, migrateDst, lastMigrate>>

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ (applied \cap PointsOfShard(s)) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardData' = [shardData EXCEPT ![s] = copiedData[s]]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Activated"]
    /\ UNCHANGED <<shardLocation, migrateSrc, migrateDst, copiedData,
                  writeState, wal, applied, ackSet, replicaHas, lastWrite>>
    /\ lastMigrate' = [kind |-> "Some",
                        principal |-> p,
                        shard |-> s,
                        phase |-> "Activate",
                        authorized |-> TRUE]

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ UNCHANGED <<shardOwner, migrateSrc, migrateDst,
                  writeState, wal, applied, ackSet, replicaHas, shardData>>
    /\ lastMigrate' = [kind |-> "Some",
                        principal |-> p,
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

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ lastMigrate \in [kind : {"None", "Some"},
                         principal : Principals,
                         shard : Shards,
                         phase : {"Start", "Activate", "Finish"},
                         authorized : BOOLEAN]

=============================================================================
