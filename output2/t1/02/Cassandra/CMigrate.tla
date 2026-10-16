------------------------------- MODULE CMigrate -------------------------------

EXTENDS CReplica

VARIABLES
    shardOwner, shardLocation, migrateState,
    migrateSrc, migrateDst, copiedData, lastMigrate

MigrateVars == <<shardOwner, shardLocation, migrateState,
                  migrateSrc, migrateDst, copiedData, lastMigrate>>

MigrateStates == {"Stable", "Migratering", "Activated"}

MigrateRecordT == [kind : {"None", "Some"},
                    principal : Principals,
                    partition : Partitions,
                    phase : {"Start", "Advance", "Activate", "Finish"},
                    authorized : BOOLEAN]

InitMigrate ==
    /\ shardLocation = [p \in Partitions |-> {replicaNode[rep] : rep \in replicas[p]}]
    /\ shardOwner \in [Partitions -> Nodes]
    /\ \A p \in Partitions : shardOwner[p] \in shardLocation[p]
    /\ migrateState = [p \in Partitions |-> "Stable"]
    /\ migrateSrc = shardOwner
    /\ migrateDst = shardOwner
    /\ copiedData = [p \in Partitions |-> {}]
    /\ lastMigrate = [kind |-> "None",
                       principal |-> CHOOSE p \in Principals : TRUE,
                       partition |-> CHOOSE pt \in Partitions : TRUE,
                       phase |-> "Start",
                       authorized |-> FALSE]

MigrationSafe(r) ==
    r \in shardData[recordPartition[r]]

StartMigrate(p, partition, src, dst) ==
    /\ p \in Principals
    /\ partition \in Partitions
    /\ CanAccess(p, partitionKeyspace[partition], "Migrate")
    /\ migrateState[partition] = "Stable"
    /\ src = shardOwner[partition]
    /\ dst \in Nodes
    /\ dst \# src
    /\ migrateState' = [migrateState EXCEPT ![partition] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![partition] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![partition] = dst]
    /\ shardLocation' = [shardLocation EXCEPT ![partition] = @ \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![partition] = {}]
    /\ shardOwner' = shardOwner
    /\ lastMigrate' = [kind |-> "Some", principal |-> p, partition |-> partition,
                        phase |-> "Start", authorized |-> TRUE]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite>>

RejectMigrate(p, partition) ==
    /\ p \in Principals
    /\ partition \in Partitions
    /\ ~CanAccess(p, partitionKeyspace[partition], "Migrate")
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData,
                  lastWrite, lastMigrate>>
    /\ lastMigrate' = [kind |-> "Some", principal |-> p, partition |-> partition,
                        phase |-> "Start", authorized |-> FALSE]

AdvanceMigrate(partition) ==
    /\ partition \in Partitions
    /\ migrateState[partition] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![partition] = shardData[partition]]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData,
                  shardOwner, shardLocation, migrateState, migrateSrc, migrateDst,
                  lastWrite, lastMigrate>>

ActivateMigrate(partition) ==
    /\ partition \in Partitions
    /\ migrateState[partition] = "Migratering"
    /\ applied \cap PartitionRecords(partition) \subseteq copiedData[partition]
    /\ shardOwner' = [shardOwner EXCEPT ![partition] = migrateDst[partition]]
    /\ shardData' = [shardData EXCEPT ![partition] = copiedData[partition]]
    /\ migrateState' = [migrateState EXCEPT ![partition] = "Activated"]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas,
                  shardLocation, migrateSrc, migrateDst, copiedData, lastWrite, lastMigrate>>
    /\ lastMigrate' = [kind |-> "Some", principal |-> lastMigrate.principal,
                        partition |-> partition, phase |-> "Activate", authorized |-> TRUE]

FinishMigrate(partition) ==
    /\ partition \in Partitions
    /\ migrateState[partition] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![partition] = {shardOwner[partition]}]
    /\ migrateState' = [migrateState EXCEPT ![partition] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![partition] = {}]
    /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData,
                  shardOwner, migrateSrc, migrateDst, lastWrite, lastMigrate>>
    /\ lastMigrate' = [kind |-> "Some", principal |-> lastMigrate.principal,
                        partition |-> partition, phase |-> "Finish", authorized |-> TRUE]

NextMigrate ==
    \/ \E p \in Principals, partition \in Partitions, src, dst \in Nodes :
        StartMigrate(p, partition, src, dst)
    \/ \E p \in Principals, partition \in Partitions :
        RejectMigrate(p, partition)
    \/ \E partition \in Partitions :
        AdvanceMigrate(partition)
    \/ \E partition \in Partitions :
        ActivateMigrate(partition)
    \/ \E partition \in Partitions :
        FinishMigrate(partition)

MigrateTypeOK ==
    /\ shardOwner \in [Partitions -> Nodes]
    /\ shardLocation \in [Partitions -> SUBSET Nodes]
    /\ migrateState \in [Partitions -> MigrateStates]
    /\ migrateSrc \in [Partitions -> Nodes]
    /\ migrateDst \in [Partitions -> Nodes]
    /\ copiedData \in [Partitions -> SUBSET Records]
    /\ lastMigrate \in MigrateRecordT

MigrateSafety ==
    /\ \A p \in Partitions : shardOwner[p] \in shardLocation[p]
    /\ \A p \in Partitions :
        migrateState[p] = "Migratering" =>
           migrateSrc[p] = shardOwner[p] /\ migrateDst[p] \in Nodes /\ migrateDst[p] # migrateSrc[p]
    /\ \A p \in Partitions :
        migrateState[p] = "Activated" =>
           applied \cap PartitionRecords(p) \subseteq shardData[p]
    /\ \A p \in Partitions :
        migrateState[p] = "Stable" => copiedData[p] = {}

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
