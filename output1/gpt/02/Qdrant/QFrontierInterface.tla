---------------------- MODULE QFrontierInterface ---------------------------

EXTENDS QSearch

WriteFrontier ==
    wal

CommitFrontier ==
    applied

ReplicaFrontier(r) ==
    replicaHas[r]

QueryFrontier(level, sel) ==
    {pt \in CommitFrontier : Visible(pt, level, sel)}

MigrateFrontier ==
    {pt \in CommitFrontier : MigrationSafe(pt)}

SearchFrontier(p, c, level, sel) ==
    SearchEligibleSet(p, c, level, sel)

CommitFrontierSafety ==
    CommitFrontier \subseteq WriteFrontier

ReplicaFrontierSafety ==
    \A r \in Replicas :
        ReplicaFrontier(r) \subseteq WriteFrontier

QueryFrontierSafety ==
    \A level \in ReadConsistencyLevels, sel \in ReplicaSelections :
        QueryFrontier(level, sel) \subseteq CommitFrontier

MigrateFrontierSafety ==
    MigrateFrontier \subseteq CommitFrontier

SearchFrontierSafety ==
    \A p \in Principals :
        \A c \in Collections :
            \A level \in ReadConsistencyLevels, sel \in ReplicaSelections :
                SearchFrontier(p, c, level, sel)
                    = SearchEligibleSet(p, c, level, sel)

SearchResultSafety ==
    lastSearch.kind # "Search"
    \/
    /\ lastSearch.executed = TRUE
    /\ lastSearch.authorized = TRUE
    /\ lastSearch.result =
        SearchFrontier(lastSearch.principal,
                       lastSearch.collection,
                       lastSearch.level)
    /\ searchResult = lastSearch.result

FrontierSafety ==
    /\ CommitFrontierSafety
    /\ ReplicaFrontierSafety
    /\ QueryFrontierSafety
    /\ MigrateFrontierSafety
    /\ SearchFrontierSafety
    /\ SearchResultSafety

=============================================================================
