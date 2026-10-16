------------------------------- MODULE QFrontierInterface -------------------------------

EXTENDS QSearch

\* Frontiers
WriteFrontier == wal

CommitFrontier == applied

ReplicaFrontier == replicaHas

QueryFrontier(p, c, level) == SearchEligibleSet(p, c, level, sel)

MigrateFrontier == {pt \in applied : MigrationSafe(pt)}

SearchFrontier(p, c, level, sel) == SearchEligibleSet(p, c, level, sel)

\* Type invariant
GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ ReplicaTypeOK
    /\ MigrateTypeOK
    /\ SearchTypeOK

\* Auth safety: only authorized actions may be recorded as such;
\* the recorded `authorized` flag is used rather than re-evaluating current permissions.
AuthSafety ==
    /\ lastWrite.authorized => CanAccess(lastWrite.principal, lastWrite.collection, "Write")
    /\ lastMigrate.authorized => CanAccess(lastMigrate.principal, shardCollection[lastMigrate.shard], "Migrate")
    /\ lastSearch.authorized => CanAccess(lastSearch.principal, lastSearch.collection, "Read")

\* Frontier safety (non‑trivial relations)
FrontierSafety ==
    /\ WriteFrontier \subseteq Points
    /\ CommitFrontier \subseteq Points
    /\ \A p \in Principals, c \in Collections, l \in ReadConsistencyLevels :
        SearchFrontier(p, c, l) \subseteq Points
    /\ \A pt \in CommitFrontier : MigrationSafe(pt) => pt \in MigrateFrontier

\* Additional required invariants
WalBeforeApply ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A r \in Replicas : replicaHas[r] \subseteq wal

MigrateSafety ==
    \A s \in Shards : migrateState[s] \in MigrateStates

=============================================================================
