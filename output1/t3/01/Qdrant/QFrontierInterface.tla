--------------------------- MODULE QFrontierInterface ---------------------------

EXTENDS QSearch

\* WriteFrontier: set of points that have been written (wal)
WriteFrontier == wal

\* CommitFrontier: set of points that have been committed (applied)
CommitFrontier == applied

\* ReplicaFrontier: per-replica set of points
ReplicaFrontier == replicaHas

\* QueryFrontier: points visible to a consistency level
QueryFrontier(pt, level, sel) ==
    pt \in applied /\ Visible(pt, level, sel)

\* MigrateFrontier: points that are both committed and migration safe
MigrateFrontier == { pt \in Points : pt \in applied /\ MigrationSafe(pt) }

\* SearchFrontier: equivalent to SearchEligibleSet (three arguments)
SearchFrontier(p, c, level, sel) == SearchEligibleSet(p, c, level, sel)

\* FrontierSafety: references all frontiers
FrontierSafety ==
    /\ WriteFrontier = wal
    /\ CommitFrontier = applied
    /\ ReplicaFrontier = replicaHas
    /\ \A pt \in Points, level \in ReadConsistencyLevels, sel \in ReplicaSelections :
        QueryFrontier(pt, level, sel) = (pt \in applied /\ Visible(pt, level, sel))
    /\ MigrateFrontier = { pt \in Points : pt \in applied /\ MigrationSafe(pt) }
    /\ \A p \in Principals, c \in Collections, level \in ReadConsistencyLevels, sel \in ReplicaSelections :
        SearchFrontier(p, c, level, sel) = SearchEligibleSet(p, c, level, sel)

=============================================================================
