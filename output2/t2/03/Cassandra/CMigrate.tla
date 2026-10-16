------------------------------ MODULE CMigrate ------------------------------

EXTENDS CQuery

MigrateStates == {"Stable", "Migratering", "Activated"}

VARIABLES
    migrateState,
    migrateSrc,
    migrateDst,
    copiedData

StartMigrate(p, sh, src, dst) ==
    LET ks == shardKeyspace[sh] IN
    /\ p \in Principals
    /\ sh \in Shards
    /\ src \in replicas[sh]
    /\ dst \in Nodes
    /\ dst \notin replicas[sh]
    /\ CanAccess(p, ks, "Migrate")
    /\ migrateState[sh] = "Stable"
    /\ migrateState' = [migrateState EXCEPT ![sh] = "Migratering"]
    /\ migrateSrc'   = [migrateSrc   EXCEPT ![sh] = src]
    /\ migrateDst'   = [migrateDst   EXCEPT ![sh] = dst]
    /\ copiedData'    = [copiedData    EXCEPT ![sh] = {}]
    /\ lastMigrate'  = [authorized |-> TRUE, principal |-> p, shard |-> sh]
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas, permission, lastWrite, lastQuery>>

AdvanceMigrate(sh) ==
    /\ migrateState[sh] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![sh] = applied \cap PartitionsOfShard(sh)]
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, writeState, wal, applied, replicaHas, replicas, permission, lastWrite, lastQuery, lastMigrate>>

ActivateMigrate(sh) ==
    /\ migrateState[sh] = "Migratering"
    /\ (applied \cap PartitionsOfShard(sh)) \subseteq copiedData[sh]
    /\ replicas' = [replicas EXCEPT ![sh] =
                       (replicas[sh] \ {migrateSrc[sh]}) \cup {migrateDst[sh]}]
    /\ replicaHas' = [replicaHas EXCEPT ![migrateDst[sh]] =
                          replicaHas[migrateDst[sh]] \cup copiedData[sh]]
    /\ migrateState' = [migrateState EXCEPT ![sh] = "Activated"]
    /\ UNCHANGED <<migrateSrc, migrateDst, copiedData, writeState, wal, applied, permission, lastWrite, lastQuery, lastMigrate>>

FinishMigrate(sh) ==
    /\ migrateState[sh] = "Activated"
    /\ migrateState' = [migrateState EXCEPT ![sh] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![sh] = {}]
    /\ UNCHANGED <<migrateSrc, migrateDst, writeState, wal, applied, replicaHas, replicas, permission, lastWrite, lastQuery, lastMigrate>>

MigrateTypeInvariant ==
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc   \in [Shards -> Nodes]
    /\ migrateDst   \in [Shards -> Nodes]
    /\ copiedData    \in [Shards -> SUBSET Partitions]

NoUnsafeActivation ==
    \A sh \in Shards :
        (migrateState[sh] = "Activated") =>
            (\A pt \in copiedData[sh] : pt \in replicaHas[migrateDst[sh]])

NoCommittedDataLoss ==
    \A sh \in Shards :
        \A pt \in applied \cap PartitionsOfShard(sh) :
            \/ migrateState[sh] = "Stable"
            \/ migrateState[sh] = "Migratering"
            \/ ( (migrateState[sh] = "Activated" \/ migrateState[sh] = "Stable") =>
                   \E n \in replicas[sh] : pt \in replicaHas[n] )

NoDoubleOwner ==
    \A sh \in Shards :
        (migrateState[sh] = "Stable") => Cardinality(replicas[sh]) = replicationFactor[shardKeyspace[sh]]

=============================================================================
