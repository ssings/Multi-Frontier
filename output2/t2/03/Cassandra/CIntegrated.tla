---------------------------- MODULE CIntegrated -----------------------------

EXTENDS CFrontierInterface, CHelpers

Vars ==
    <<permission, lastWrite, lastQuery, lastMigrate,
      writeState, wal, applied, replicaHas, replicas,
      migrateState, migrateSrc, migrateDst, copiedData>>

Init ==
    /\ permission    = [p \in Principals |-> [ks \in Keyspaces |-> {}]]
    /\ lastWrite     = [authorized |-> FALSE,
                        principal  |-> CHOOSE p \in Principals : TRUE,
                        keyspace   |-> CHOOSE ks \in Keyspaces : TRUE,
                        partition  |-> CHOOSE pt \in Partitions : TRUE]
    /\ lastQuery     = [authorized |-> FALSE,
                        principal  |-> CHOOSE p \in Principals : TRUE,
                        keyspace   |-> CHOOSE ks \in Keyspaces : TRUE,
                        level      |-> "One",
                        result     |-> {}]
    /\ lastMigrate  = [authorized |-> FALSE,
                        principal  |-> CHOOSE p \in Principals : TRUE,
                        shard      |-> CHOOSE sh \in Shards : TRUE]
    /\ writeState    = [pt \in Partitions |-> "None"]
    /\ wal           = {}
    /\ applied       = {}
    /\ replicaHas    = [n \in Nodes |-> {}]
    /\ replicas      = initialReplicas
    /\ migrateState = [sh \in Shards |-> "Stable"]
    /\ migrateSrc   = [sh \in Shards |-> CHOOSE n \in replicas[sh] : TRUE]
    /\ migrateDst   = migrateSrc
    /\ copiedData    = [sh \in Shards |-> {}]

\* Wrappers for actions from sub-modules, ensuring all variables are constrained.

DoGrantPermission(admin, target, ks, op) ==
    /\ GrantPermission(admin, target, ks, op)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

DoRevokePermission(admin, target, ks, op) ==
    /\ RevokePermission(admin, target, ks, op)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

DoRejectWrite(p, pt) ==
    /\ RejectWrite(p, pt)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

DoRejectQuery(p, ks, level) ==
    /\ RejectQuery(p, ks, level)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

DoRejectMigrate(p, sh) ==
    /\ RejectMigrate(p, sh)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

DoReceiveWrite(p, pt, node) ==
    /\ ReceiveWrite(p, pt, node)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData>>

DoReplicateToNode(pt, node) ==
    /\ ReplicateToNode(pt, node)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData>>

DoCommitIfReady(pt) ==
    /\ CommitIfReady(pt)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData>>

DoQuery(p, ks, level) ==
    /\ Query(p, ks, level)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData>>

DoStartMigrate(p, sh, src, dst) ==
    /\ StartMigrate(p, sh, src, dst)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas>>

DoAdvanceMigrate(sh) ==
    /\ AdvanceMigrate(sh)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas>>

DoActivateMigrate(sh) ==
    /\ ActivateMigrate(sh)
    /\ UNCHANGED <<writeState, wal, applied>>

DoFinishMigrate(sh) ==
    /\ FinishMigrate(sh)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas, replicas>>

Next ==
    \/ \E admin \in Principals, target \in Principals, ks \in Keyspaces, op \in Operations : DoGrantPermission(admin, target, ks, op)
    \/ \E admin \in Principals, target \in Principals, ks \in Keyspaces, op \in Operations : DoRevokePermission(admin, target, ks, op)
    \/ \E p \in Principals, pt \in Partitions : DoRejectWrite(p, pt)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels : DoRejectQuery(p, ks, level)
    \/ \E p \in Principals, sh \in Shards : DoRejectMigrate(p, sh)
    \/ \E p \in Principals, pt \in Partitions, node \in Nodes : DoReceiveWrite(p, pt, node)
    \/ \E pt \in Partitions, node \in Nodes : DoReplicateToNode(pt, node)
    \/ \E pt \in Partitions : DoCommitIfReady(pt)
    \/ \E p \in Principals, ks \in Keyspaces, level \in ReadConsistencyLevels : DoQuery(p, ks, level)
    \/ \E p \in Principals, sh \in Shards, src \in Nodes, dst \in Nodes : DoStartMigrate(p, sh, src, dst)
    \/ \E sh \in Shards : DoAdvanceMigrate(sh)
    \/ \E sh \in Shards : DoActivateMigrate(sh)
    \/ \E sh \in Shards : DoFinishMigrate(sh)

Spec ==
    Init /\ [][Next]_Vars

\* Global type invariant
GlobalTypeInvariant ==
    /\ AuthTypeInvariant
    /\ WriteTypeInvariant
    /\ MigrateTypeInvariant

\* Auth safety: last operation authorized implies appropriate capability was held.
AuthSafety ==
    /\ (lastWrite.authorized = TRUE) =>
           CanAccess(lastWrite.principal, lastWrite.keyspace, "Write")
    /\ (lastQuery.authorized = TRUE) =>
           CanAccess(lastQuery.principal, lastQuery.keyspace, "Read")
    /\ (lastMigrate.authorized = TRUE) =>
           CanAccess(lastMigrate.principal, shardKeyspace[lastMigrate.shard], "Migrate")

\* Combined safety properties for TLC
IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ AuthSafety
    /\ WalBeforeApply
    /\ ReplicaNotAheadOfWAL
    /\ QuerySafetyInv
    /\ NoUnsafeActivation
    /\ NoCommittedDataLoss
    /\ FrontierSafety

=============================================================================
