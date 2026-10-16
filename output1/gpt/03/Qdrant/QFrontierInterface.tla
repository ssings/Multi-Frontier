---------------------- MODULE QFrontierInterface ----------------------

EXTENDS QSearch

WriteFrontier == wal

CommitFrontier == applied

ReplicaFrontier(pt) ==
    {r \in ReplicasOfPoint(pt) : pt \in replicaHas[r]}

QueryFrontier(p, c, level) ==
    {pt \in CommitFrontier :
        /\ pointCollection[pt] = c
        /\ CanAccess(p, c, "Read")
        /\ Visible(pt, level, sel)}

MigrateFrontier ==
    {pt \in CommitFrontier : MigrationSafe(pt)}

SearchFrontier(p, c, level, sel) ==
    QueryFrontier(p, c, level) \cap MigrateFrontier

HistoricalSearchFrontier(c, level) ==
    {pt \in CommitFrontier :
        /\ pointCollection[pt] = c
        /\ Visible(pt, level, sel)
        /\ MigrationSafe(pt)}

FrontierSafety ==
    /\ WriteFrontier = wal
    /\ CommitFrontier = applied
    /\ \A pt \in Points :
        ReplicaFrontier(pt) = ReplicaContains(pt)
    /\ \A p \in Principals :
        \A c \in Collections :
            \A level \in ReadConsistencyLevels, sel \in ReplicaSelections :
                QueryFrontier(p, c, level) =
                    {pt \in CommitFrontier :
                        /\ pointCollection[pt] = c
                        /\ CanAccess(p, c, "Read")
                        /\ Visible(pt, level, sel)}
    /\ MigrateFrontier =
        {pt \in CommitFrontier : MigrationSafe(pt)}
    /\ \A p \in Principals :
        \A c \in Collections :
            \A level \in ReadConsistencyLevels, sel \in ReplicaSelections :
                SearchFrontier(p, c, level, sel) =
                    SearchEligibleSet(p, c, level, sel)
    /\ lastSearch.executed =>
        /\ lastSearch.kind = "Search"
        /\ lastSearch.authorized
        /\ searchResult = lastSearch.result
        /\ lastSearch.result \subseteq
            HistoricalSearchFrontier(
                lastSearch.collection,
                lastSearch.level)

=============================================================================
