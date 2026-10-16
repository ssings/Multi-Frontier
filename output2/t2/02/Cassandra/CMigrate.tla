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

MigrateRecordT == [
    kind       : {"None", "Start", "Advance", "Activate", "Finish"},
    principal  : Principals,
    partition  : Partitions,
    authorized : BOOLEAN
]

InitMigrate ==
    /\ shardOwner \in [Partitions -> Nodes]
    /\ shardLocation = [p \in Partitions |-> {shardOwner[p]} \cup {replicaNode[rep] : rep \in replicas[p]}]
    /\ migrateState = [p \in Partitions |-> "Stable"]
    /\ migrateSrc = [p \in Partitions |-> CHOOSE n \in Nodes : TRUE]
    /\ migrateDst = [p \in Partitions |-> CHOOSE n \in Nodes : TRUE]
    /\ copiedData = [p \in Partitions |-> {}]
    /\ lastMigrate = [kind |-> "None", principal |-> CHOOSE p \in Principals : TRUE, partition |-> CHOOSE pt \in Partitions : TRUE, authorized |-> FALSE]

PointsOfPartition(partition) ==
    {r \in Records : recordPartition[r] = partition}

MigrationSafe(r) ==
    r \in shardData[recordPartition[r]]

StartMigrate(p, partition, src, dst) ==
    /\ p \in Principals
    /\ partition \in Partitions
    /\ CanAccess(p, partitionKeyspace[partition], "Migrate")
    /\ migrateState[partition] = "Stable"
    /\ src = shardOwner[partition]
    /\ dst \in Nodes
    /\ dst # src
    /\ migrateState' = [migrateState EXCEPT ![partition] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![partition] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![partition] = dst]
    /\ shardLocation' = [shardLocation EXCEPT ![partition] = @ \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![partition] = {}]
    /\ shardOwner' = shardOwner
    /\ lastMigrate' = [kind |-> "Start", principal |-> p, partition |-> partition, authorized |-> TRUE]

RejectMigrate(p, partition) ==
    /\ p \in Principals
    /\ partition \in Partitions
    /\ ~CanAccess(p, partitionKeyspace[partition], "Migrate")
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData>>
    /\ lastMigrate' = [kind |-> "Start", principal |-> p, partition |-> partition, authorized |-> FALSE]

AdvanceMigrate(partition) ==
    /\ migrateState[partition] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![partition] = shardData[partition]]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst>>
    /\ lastMigrate' = [kind |-> "Advance", principal |-> CHOOSE p \in Principals : TRUE, partition |-> partition, authorized |-> FALSE]

ActivateMigrate(partition) ==
    LET required == {r \in Records : recordPartition[r] = partition /\ r \in applied} IN
    /\ migrateState[partition] = "Migratering"
    /\ required \subseteq copiedData[partition]
    /\ shardOwner' = [shardOwner EXCEPT ![partition] = migrateDst[partition]]
    /\ shardData' = [shardData EXCEPT ![partition] = copiedData[partition]]
    /\ migrateState' = [migrateState EXCEPT ![partition] = "Activated"]
    /\ UNCHANGED <<shardLocation, migrateSrc, migrateDst, copiedData>>
    /\ lastMigrate' = [kind |-> "Activate", principal |-> CHOOSE p \in Principals : TRUE, partition |-> partition, authorized |-> FALSE]

FinishMigrate(partition) ==
    /\ migrateState[partition] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![partition] = {shardOwner[partition]}]
    /\ migrateState' = [migrateState EXCEPT ![partition] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![partition] = {}]
    /\ UNCHANGED <<shardOwner, shardData, migrateSrc, migrateDst>>
    /\ lastMigrate' = [kind |-> "Finish", principal |-> CHOOSE p \in Principals : TRUE, partition |-> partition, authorized |-> FALSE]

MigrateTypeOK ==
    /\ shardOwner \in [Partitions -> Nodes]
    /\ shardLocation \in [Partitions -> SUBSET Nodes]
    /\ \A p \in Partitions : shardOwner[p] \in shardLocation[p]
    /\ migrateState \in [Partitions -> MigrateStates]
    /\ migrateSrc \in [Partitions -> Nodes]
    /\ migrateDst \in [Partitions -> Nodes]
    /\ copiedData \in [Partitions -> SUBSET Records]
    /\ lastMigrate \in MigrateRecordT

=============================================================================
