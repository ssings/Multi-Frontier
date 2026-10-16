------------------------------- MODULE CMigrate -------------------------------

EXTENDS CQuery

VARIABLES
    migrateState,
    migrateSrc,
    migrateDst,
    copiedData

MigrateVars == <<migrateState, migrateSrc, migrateDst, copiedData>>

MigrateStates == {"Stable", "Migratering", "Activated"}

MigrateTypeOK ==
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Partitions]

InitMigrate ==
    /\ migrateState = [sh \in Shards |-> "Stable"]
    /\ migrateSrc = [sh \in Shards |-> CHOOSE n \in Nodes : TRUE]
    /\ migrateDst = [sh \in Shards |-> CHOOSE n \in Nodes : TRUE]
    /\ copiedData = [sh \in Shards |-> {}]

StartMigrate(p, sh, src, dst) ==
    /\ p \in Principals
    /\ sh \in Shards
    /\ src \in Nodes
    /\ dst \in Nodes
    /\ CanAccess(p, shardKeyspace[sh], "Migrate")
    /\ migrateState[sh] = "Stable"
    /\ src \in replicas[sh]
    /\ dst \notin replicas[sh]
    /\ migrateState' = [migrateState EXCEPT ![sh] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![sh] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![sh] = dst]
    /\ copiedData' = [copiedData EXCEPT ![sh] = {pt \in replicaHas[dst] : partitionShard[pt] = sh}]
    /\ UNCHANGED <<replicas, writeState, wal, applied, replicaHas, searchResult, lastWrite, lastQuery>>
    /\ lastMigrate' = [ kind |-> "Migrate", principal |-> p, keyspace |-> shardKeyspace[sh], op |-> "Migrate", level |-> "None", authorized |-> TRUE ]

RejectMigrateInMigrate(p, sh) ==
    /\ RejectMigrate(p, sh)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData, replicas, writeState, wal, applied, replicaHas, searchResult>>

AdvanceMigrate(sh) ==
    /\ sh \in Shards
    /\ migrateState[sh] = "Migratering"
    /\ LET committed == applied \cap {pt \in Partitions : partitionShard[pt] = sh} IN
       copiedData' = [copiedData EXCEPT ![sh] = committed]
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, replicas, writeState, wal, applied, replicaHas, searchResult, lastWrite, lastQuery, lastMigrate>>

ActivateMigrate(sh) ==
    /\ sh \in Shards
    /\ migrateState[sh] = "Migratering"
    /\ LET committed == applied \cap {pt \in Partitions : partitionShard[pt] = sh} IN
       committed \subseteq copiedData[sh]
    /\ replicas' = [replicas EXCEPT ![sh] = (replicas[sh] \ {migrateSrc[sh]}) \cup {migrateDst[sh]}]
    /\ replicaHas' = [replicaHas EXCEPT ![migrateDst[sh]] = replicaHas[migrateDst[sh]] \cup copiedData[sh]]
    /\ migrateState' = [migrateState EXCEPT ![sh] = "Activated"]
    /\ UNCHANGED <<migrateSrc, migrateDst, copiedData, writeState, wal, applied, searchResult, lastWrite, lastQuery, lastMigrate>>

FinishMigrate(sh) ==
    /\ sh \in Shards
    /\ migrateState[sh] = "Activated"
    /\ migrateState' = [migrateState EXCEPT ![sh] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![sh] = {}]
    /\ UNCHANGED <<migrateSrc, migrateDst, replicas, writeState, wal, applied, replicaHas, searchResult, lastWrite, lastQuery, lastMigrate>>

NextMigrate ==
    \/ \E p \in Principals :
        \E sh \in Shards :
            \E src \in Nodes :
                \E dst \in Nodes :
                    StartMigrate(p, sh, src, dst)
    \/ \E p \in Principals :
        \E sh \in Shards :
            RejectMigrateInMigrate(p, sh)
    \/ \E sh \in Shards : AdvanceMigrate(sh)
    \/ \E sh \in Shards : ActivateMigrate(sh)
    \/ \E sh \in Shards : FinishMigrate(sh)

=============================================================================
