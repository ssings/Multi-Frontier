----------------------------- MODULE CIntegrated ----------------------------

EXTENDS CFrontierInterface, CCfgHelpers

Vars == <<permission, lastWrite, lastQuery, lastMigrate,
           writeState, wal, applied, replicaHas,
           replicas,
           migrateState, migrateSrc, migrateDst, copiedData>>

Init ==
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate

\* Auth wrappers
DoGrantPermission(admin, target, ks, op) ==
    /\ GrantPermission(admin, target, ks, op)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas,
                   replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

DoRevokePermission(admin, target, ks, op) ==
    /\ RevokePermission(admin, target, ks, op)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas,
                   replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

DoRejectWrite(p, pt) ==
    /\ RejectWrite(p, pt)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas,
                   replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

DoRejectQuery(p, ks, lv) ==
    /\ RejectQuery(p, ks, lv)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas,
                   replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

DoRejectMigrate(p, s, src, dst) ==
    /\ RejectMigrate(p, s, src, dst)
    /\ UNCHANGED <<writeState, wal, applied, replicaHas,
                   replicas,
                   migrateState, migrateSrc, migrateDst, copiedData>>

\* Write wrappers
DoReceiveWrite(p, pt) ==
    /\ ReceiveWrite(p, pt)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData>>

DoReplicateToNode(pt, n) ==
    /\ ReplicateToNode(pt, n)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData>>

DoCommitIfReady(pt) ==
    /\ CommitIfReady(pt)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData>>

\* Query wrappers
DoQuery(p, ks, lv) ==
    /\ Query(p, ks, lv)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData>>

DoRejectQueryFinal(p, ks, lv) ==
    /\ RejectQuery(p, ks, lv)
    /\ UNCHANGED <<migrateState, migrateSrc, migrateDst, copiedData>>

\* Migrate wrappers
DoStartMigrate(p, s, src, dst) ==
    /\ StartMigrate(p, s, src, dst)
    /\ UNCHANGED <<writeState, wal, applied>>

DoAdvanceMigrate(p, s) ==
    /\ AdvanceMigrate(p, s)
    /\ UNCHANGED <<writeState, wal, applied>>

DoActivateMigrate(p, s) ==
    /\ ActivateMigrate(p, s)
    /\ UNCHANGED <<writeState, wal>>

DoFinishMigrate(p, s) ==
    /\ FinishMigrate(p, s)
    /\ UNCHANGED <<writeState, wal, applied>>

Next ==
    \/ \E admin, target \in Principals, ks \in Keyspaces, op \in Operations : DoGrantPermission(admin, target, ks, op)
    \/ \E admin, target \in Principals, ks \in Keyspaces, op \in Operations : DoRevokePermission(admin, target, ks, op)
    \/ \E p \in Principals, pt \in Partitions : DoRejectWrite(p, pt)
    \/ \E p \in Principals, ks \in Keyspaces, lv \in ReadConsistencyLevels : DoRejectQuery(p, ks, lv)
    \/ \E p \in Principals, s \in Shards, src,dst \in Nodes : DoRejectMigrate(p, s, src, dst)
    \/ \E p \in Principals, pt \in Partitions : DoReceiveWrite(p, pt)
    \/ \E pt \in Partitions, n \in Nodes : DoReplicateToNode(pt, n)
    \/ \E pt \in Partitions : DoCommitIfReady(pt)
    \/ \E p \in Principals, ks \in Keyspaces, lv \in ReadConsistencyLevels : DoQuery(p, ks, lv)
    \/ \E p \in Principals, ks \in Keyspaces, lv \in ReadConsistencyLevels : DoRejectQueryFinal(p, ks, lv)
    \/ \E p \in Principals, s \in Shards, src,dst \in Nodes : DoStartMigrate(p, s, src, dst)
    \/ \E p \in Principals, s \in Shards : DoAdvanceMigrate(p, s)
    \/ \E p \in Principals, s \in Shards : DoActivateMigrate(p, s)
    \/ \E p \in Principals, s \in Shards : DoFinishMigrate(p, s)

Spec ==
    /\ Init
    /\ [][Next]_Vars

GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeInvariant
    /\ WriteTypeInvariant
    /\ MigrateTypeInvariant

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ AuthSafety
    /\ WalBeforeApply
    /\ ReplicaNotAheadOfWAL
    /\ MigrateSafetyLocal
    /\ FrontierSafety
    /\ SearchFrontierEquivalence
    /\ QuerySafety

=============================================================================
