------------------------------ MODULE QMigrate ---------------------------

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
    /\ \E owner \in [Shards -> Nodes] :
        shardOwner = owner
        /\ shardLocation = [s \in Shards |-> {owner[s]}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = shardOwner
    /\ migrateDst = shardOwner
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate =
        [ kind       |-> "None",
          principal  |-> CHOOSE p \in Principals : TRUE,
          shard      |-> CHOOSE s \in Shards : TRUE,
          phase      |-> "Start",
          authorized |-> FALSE ]

\* MigrationSafe(pt) checks that pt resides in the shardData of its owning shard
MigrationSafe(pt) ==
    pt \in shardData[pointShard[pt]]

\* Start a shard migrate from current owner to a different target
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
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          phase      |-> "Start",
          authorized |-> TRUE ]
    /\ UNCHANGED shardOwner
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData,
                    lastWrite>>

\* Unauthorized migrate request is rejected without state change
RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ ~CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Stable"
    /\ src = shardOwner[s]
    /\ dst \in Nodes
    /\ dst # src
    /\ UNCHANGED shardOwner
    /\ UNCHANGED shardLocation
    /\ UNCHANGED migrateState
    /\ UNCHANGED migrateSrc
    /\ UNCHANGED migrateDst
    /\ UNCHANGED copiedData
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          phase      |-> "Start",
          authorized |-> FALSE ]
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData,
                    lastWrite>>

\* One-shot full copy of the shard's committed data to the target
AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          phase      |-> "Advance",
          authorized |-> TRUE ]
    /\ UNCHANGED shardOwner
    /\ UNCHANGED shardLocation
    /\ UNCHANGED migrateState
    /\ UNCHANGED migrateSrc
    /\ UNCHANGED migrateDst
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData,
                    lastWrite>>

\* Activate the migrate: all applied points of the shard must be in copiedData
ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ (applied \cap PointsOfShard(s)) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardData' = [shardData EXCEPT ![s] = copiedData[s]]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Activated"]
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          phase      |-> "Activate",
          authorized |-> TRUE ]
    /\ UNCHANGED shardLocation
    /\ UNCHANGED migrateSrc
    /\ UNCHANGED migrateDst
    /\ UNCHANGED copiedData
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, lastWrite>>

\* Finalize the migrate: clear temporary copiedData, shrink location to owner
FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          shard      |-> s,
          phase      |-> "Finish",
          authorized |-> TRUE ]
    /\ UNCHANGED shardOwner
    /\ UNCHANGED shardData
    /\ UNCHANGED migrateSrc
    /\ UNCHANGED migrateDst
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, lastWrite>>

\* Local next for Migrate module
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
