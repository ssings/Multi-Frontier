------------------------------ MODULE QFrontierInterface ------------------------------

EXTENDS QSearch

\* WalBeforeApply: every applied point must have been written to WAL.
WalBeforeApply == applied \subseteq wal

\* ReplicaNotAheadOfWAL: a replica only holds points that are in the WAL.
ReplicaNotAheadOfWAL == \A r \in Replicas : replicaHas[r] \subseteq wal

\* AuthSafety: permission sets only contain valid operations.
AuthSafety == \A p \in Principals, c \in Collections : permission[p][c] \subseteq Operations

\* WriteFrontier: the set of points that have been written to WAL.
WriteFrontier == wal

\* CommitFrontier: the set of points that have been applied (committed).
CommitFrontier == applied

\* ReplicaFrontier: the union of all points stored on any replica.
ReplicaFrontier == UNION {replicaHas[r] : r \in Replicas}

\* QueryFrontier: points that are committed and migration-safe (using strongest read level "All").
QueryFrontier == {pt \in CommitFrontier : MigrationSafe(pt) /\ Visible(pt, "All")}

\* MigrateFrontier: committed points that are migration-safe.
MigrateFrontier == {pt \in CommitFrontier : MigrationSafe(pt)}

\* SearchFrontier must be equivalent to SearchEligibleSet.
SearchFrontier(p, c, level, sel) == SearchEligibleSet(p, c, level, sel)

\* FrontierSafety references the multi-layered frontiers.
FrontierSafety ==
    /\ WriteFrontier \subseteq Points
    /\ CommitFrontier \subseteq WriteFrontier
    /\ ReplicaFrontier \subseteq WriteFrontier
    /\ MigrateFrontier \subseteq CommitFrontier
    /\ \A p \in Principals, c \in Collections, level \in ReadConsistencyLevels, sel \in ReplicaSelections :
          SearchFrontier(p, c, level, sel) \subseteq CommitFrontier

\* MigrateSafety: a state predicate that holds during shard migrates.
\* It simply ensures that migrate source and destination are always valid nodes.
MigrateSafety ==
    \A s \in Shards : migrateSrc[s] \in Nodes /\ migrateDst[s] \in Nodes

=============================================================================
