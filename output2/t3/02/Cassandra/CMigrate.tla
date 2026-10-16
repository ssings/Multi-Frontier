------------------------------ MODULE CMigrate ------------------------------

EXTENDS CReplica

VARIABLES
    shardOwner,
    shardLocation,
    migrateState,
    migrateSrc,
    migrateDst,
    copiedData,
    lastMigrate

MigrateVars == <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>

LastMigrateT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      partition  : Partitions,
      src        : Nodes,
      dst        : Nodes,
      phase      : {"Start", "Advance", "Activate", "Finish"},
      authorized : BOOLEAN ]

MigrateTypeOK ==
    /\ shardOwner \in [Partitions -> Nodes]
    /\ shardLocation \in [Partitions -> SUBSET Nodes]
    /\ migrateState \in [Partitions -> MigrateStates]
    /\ migrateSrc \in [Partitions -> Nodes]
    /\ migrateDst \in [Partitions -> Nodes]
    /\ copiedData \in [Partitions -> SUBSET Records]
    /\ lastMigrate \in LastMigrateT

InitMigrate ==
    /\ shardOwner \in [Partitions -> Nodes]
    /\ shardLocation = [p \in Partitions |-> {shardOwner[p]}]
    /\ migrateState = [p \in Partitions |-> "Stable"]
    /\ migrateSrc = shardOwner
    /\ migrateDst = shardOwner
    /\ copiedData = [p \in Partitions |-> {}]
    /\ lastMigrate = [kind |-> "None",
                       principal |-> CHOOSE p \in Principals : TRUE,
                       partition |-> CHOOSE pt \in Partitions : TRUE,
                       src |-> CHOOSE n \in Nodes : TRUE,
                       dst |-> CHOOSE n \in Nodes : TRUE,
                       phase |-> "Start",
                       authorized |-> FALSE]

MigrationSafe(r) ==
    r \in shardData[recordPartition[r]]

StartMigrate(p, pt, src, dst) ==
    /\ p \in Principals
    /\ pt \in Partitions
    /\ CanAccess(p, partitionKeyspace[pt], "Migrate")
    /\ migrateState[pt] = "Stable"
    /\ src = shardOwner[pt]
    /\ dst \in Nodes
    /\ dst # src
    /\ migrateState' = [migrateState EXCEPT ![pt] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![pt] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![pt] = dst]
    /\ shardLocation' = [shardLocation EXCEPT ![pt] = @ \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![pt] = {}]
    /\ shardOwner' = shardOwner
    /\ lastMigrate' = [kind |-> "Some", principal |-> p, partition |-> pt,
                        src |-> src, dst |-> dst, phase |-> "Start", authorized |-> TRUE]
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

RejectMigrate(p, pt, src, dst) ==
    /\ p \in Principals
    /\ pt \in Partitions
    /\ ~CanAccess(p, partitionKeyspace[pt], "Migrate")
    /\ src \in Nodes
    /\ dst \in Nodes
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate>>
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

AdvanceMigrate(pt) ==
    /\ migrateState[pt] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![pt] = shardData[pt]]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, lastMigrate>>
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

ActivateMigrate(pt) ==
    /\ migrateState[pt] = "Migratering"
    /\ (applied \cap PointsOfPartition(pt)) \subseteq copiedData[pt]
    /\ shardOwner' = [shardOwner EXCEPT ![pt] = migrateDst[pt]]
    /\ shardData' = [shardData EXCEPT ![pt] = copiedData[pt]]
    /\ migrateState' = [migrateState EXCEPT ![pt] = "Activated"]
    /\ UNCHANGED <<shardLocation, migrateSrc, migrateDst, copiedData, lastMigrate>>
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, lastWrite>>

FinishMigrate(pt) ==
    /\ migrateState[pt] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![pt] = {shardOwner[pt]}]
    /\ migrateState' = [migrateState EXCEPT ![pt] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![pt] = {}]
    /\ UNCHANGED <<shardOwner, shardData, migrateSrc, migrateDst, lastMigrate>>
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, lastWrite>>

NextMigrate ==
    \/ \E p \in Principals, pt \in Partitions, src \in Nodes, dst \in Nodes :
        StartMigrate(p, pt, src, dst)
    \/ \E p \in Principals, pt \in Partitions, src \in Nodes, dst \in Nodes :
        RejectMigrate(p, pt, src, dst)
    \/ \E pt \in Partitions : AdvanceMigrate(pt)
    \/ \E pt \in Partitions : ActivateMigrate(pt)
    \/ \E pt \in Partitions : FinishMigrate(pt)

=============================================================================
