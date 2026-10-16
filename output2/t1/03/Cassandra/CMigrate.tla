------------------------------ MODULE CMigrate ------------------------------

EXTENDS CQuery

VARIABLES migrateState, migrateSrc, migrateDst, copiedData

MigrateTypeInvariant ==
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Partitions]

InitMigrate ==
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = [s \in Shards |-> CHOOSE n \in Nodes : TRUE]
    /\ migrateDst = [s \in Shards |-> CHOOSE n \in Nodes : TRUE]
    /\ copiedData = [s \in Shards |-> {}]
    /\ replicas = initialReplicas

StartMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ src \in replicas[s]
    /\ dst \in Nodes \ replicas[s]
    /\ CanAccess(p, shardKeyspace[s], "Migrate")
    /\ migrateState[s] = "Stable"
    /\ migrateState' = [migrateState EXCEPT ![s] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![s] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![s] = dst]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' = [principal |-> p, shard |-> s, phase |-> "Start", authorized |-> TRUE]
    /\ UNCHANGED <<permission, lastWrite, lastQuery, writeState, wal, applied, replicaHas, replicas>>

AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardKeyspace[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ LET shPoints == {pt \in Partitions : partitionShard[pt] = s} IN
       copiedData' = [copiedData EXCEPT ![s] = applied \cap shPoints]
    /\ lastMigrate' = [principal |-> p, shard |-> s, phase |-> "Advance", authorized |-> TRUE]
    /\ UNCHANGED <<permission, lastWrite, lastQuery, writeState, wal, applied, replicaHas, replicas, migrateState, migrateSrc, migrateDst>>

ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardKeyspace[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ LET shPoints == {pt \in Partitions : partitionShard[pt] = s} IN
       (applied \cap shPoints) \subseteq copiedData[s]
    /\ replicas' = [replicas EXCEPT ![s] = (replicas[s] \ {migrateSrc[s]}) \cup {migrateDst[s]}]
    /\ replicaHas' = [replicaHas EXCEPT ![migrateDst[s]] = replicaHas[migrateDst[s]] \cup copiedData[s]]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Activated"]
    /\ lastMigrate' = [principal |-> p, shard |-> s, phase |-> "Activate", authorized |-> TRUE]
    /\ UNCHANGED <<permission, lastWrite, lastQuery, writeState, wal, applied, migrateSrc, migrateDst, copiedData>>

FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardKeyspace[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' = [principal |-> p, shard |-> s, phase |-> "Finish", authorized |-> TRUE]
    /\ UNCHANGED <<permission, lastWrite, lastQuery, writeState, wal, applied, replicaHas, replicas, migrateSrc, migrateDst>>

RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ src \in Nodes
    /\ dst \in Nodes
    /\ ~CanAccess(p, shardKeyspace[s], "Migrate")
    /\ lastMigrate' = [principal |-> p, shard |-> s, phase |-> "Start", authorized |-> FALSE]
    /\ UNCHANGED <<permission, lastWrite, lastQuery, writeState, wal, applied, replicaHas, replicas, migrateState, migrateSrc, migrateDst, copiedData>>

NoUnsafeActivation ==
    \A s \in Shards : 
        migrateState[s] = "Activated" =>
        LET shPoints == {pt \in Partitions : partitionShard[pt] = s} IN
        (applied \cap shPoints) \subseteq copiedData[s]

NoCommittedDataLoss ==
    \A pt \in applied :
        LET sh == partitionShard[pt] IN
        \E n \in replicas[sh] : pt \in replicaHas[n]

NoDoubleOwner ==
    \A s \in Shards : migrateState[s] = "Stable" => Cardinality(replicas[s]) = replicationFactor[shardKeyspace[s]]

MigrateSafetyLocal ==
    /\ NoUnsafeActivation
    /\ NoCommittedDataLoss
    /\ NoDoubleOwner

=============================================================================
