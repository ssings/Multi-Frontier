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

MigrateVars == <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>

MigrateRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      shard      : Shards,
      src        : Nodes,
      dst        : Nodes,
      phase      : {"Start", "Advance", "Activate", "Finish"},
      authorized : BOOLEAN ]

InitMigrate ==
    /\ \E ownerFn \in [Shards -> Nodes] :
        /\ shardOwner = ownerFn
        /\ shardLocation = [s \in Shards |-> {ownerFn[s]}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = [s \in Shards |-> CHOOSE n \in Nodes : TRUE]
    /\ migrateDst = [s \in Shards |-> CHOOSE n \in Nodes : TRUE]
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate = [ kind |-> "None", principal |-> CHOOSE p \in Principals : TRUE, shard |-> CHOOSE s \in Shards : TRUE, src |-> CHOOSE n \in Nodes : TRUE, dst |-> CHOOSE n \in Nodes : TRUE, phase |-> "Start", authorized |-> FALSE ]

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
    /\ shardOwner' = shardOwner
    /\ shardLocation' = [shardLocation EXCEPT ![s] = shardLocation[s] \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' = [ kind |-> "Some", principal |-> p, shard |-> s, src |-> src, dst |-> dst, phase |-> "Start", authorized |-> TRUE ]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ ~CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState' = migrateState
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ shardOwner' = shardOwner
    /\ shardLocation' = shardLocation
    /\ copiedData' = copiedData
    /\ lastMigrate' = lastMigrate
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ LET thisSrc == migrateSrc[s]
           thisDst == migrateDst[s]
       IN
        /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
        /\ migrateState' = migrateState
        /\ migrateSrc' = migrateSrc
        /\ migrateDst' = migrateDst
        /\ shardOwner' = shardOwner
        /\ shardLocation' = shardLocation
        /\ lastMigrate' = [ kind |-> "Some", principal |-> p, shard |-> s, src |-> thisSrc, dst |-> thisDst, phase |-> "Advance", authorized |-> TRUE ]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ applied \cap PointsOfShard(s) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardData' = [shardData EXCEPT ![s] = copiedData[s]]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Activated"]
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ shardLocation' = shardLocation
    /\ copiedData' = copiedData
    /\ LET thisSrc == migrateSrc[s]
           thisDst == migrateDst[s]
       IN
        /\ lastMigrate' = [ kind |-> "Some", principal |-> p, shard |-> s, src |-> thisSrc, dst |-> thisDst, phase |-> "Activate", authorized |-> TRUE ]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, lastWrite>>

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ migrateSrc' = migrateSrc
    /\ migrateDst' = migrateDst
    /\ shardOwner' = shardOwner
    /\ shardData' = shardData
    /\ LET thisSrc == migrateSrc[s]
           thisDst == migrateDst[s]
       IN
        /\ lastMigrate' = [ kind |-> "Some", principal |-> p, shard |-> s, src |-> thisSrc, dst |-> thisDst, phase |-> "Finish", authorized |-> TRUE ]
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

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ lastMigrate \in MigrateRecordT

MigrateSafety ==
    /\ \A s \in Shards : shardOwner[s] \in shardLocation[s]
    /\ \A s \in Shards : (migrateState[s] = "Migratering") => (shardOwner[s] = migrateSrc[s] /\ migrateDst[s] # shardOwner[s])
    /\ \A s \in Shards : (migrateState[s] = "Activated") => (shardOwner[s] = migrateDst[s] /\ applied \cap PointsOfShard(s) \subseteq shardData[s])
    /\ \A s \in Shards : (migrateState[s] = "Stable") => (shardLocation[s] = {shardOwner[s]} /\ copiedData[s] = {})

=============================================================================
