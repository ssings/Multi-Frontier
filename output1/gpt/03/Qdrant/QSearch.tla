------------------------------ MODULE QSearch ------------------------------

EXTENDS QMigrate

VARIABLES
    searchResult,
    lastSearch

SearchVars == <<searchResult, lastSearch>>

SearchRecordT ==
    [ kind       : {"None", "Search", "Reject"},
      principal  : Principals,
      collection : Collections,
      level      : ReadConsistencyLevels,
      result     : SUBSET Points,
      authorized : BOOLEAN,
      executed   : BOOLEAN ]

InitialSearchPrincipal == CHOOSE p \in Principals : TRUE

InitialSearchCollection == CHOOSE c \in Collections : TRUE

InitSearch ==
    /\ searchResult = {}
    /\ lastSearch =
        [ kind       |-> "None",
          principal  |-> InitialSearchPrincipal,
          collection |-> InitialSearchCollection,
          level      |-> "One",
          result     |-> {},
          authorized |-> FALSE,
          executed   |-> FALSE ]

SearchEligibleSet(p, c, level, sel) ==
    {pt \in Points :
        /\ pointCollection[pt] = c
        /\ CanAccess(p, c, "Read")
        /\ pt \in applied
        /\ Visible(pt, level, sel)
        /\ MigrationSafe(pt)}

Search(p, c, level, sel) ==
    /\ sel \in ReplicaSelections
    /\ p \in Principals
    /\ c \in Collections
    /\ level \in ReadConsistencyLevels
    /\ CanAccess(p, c, "Read")
    /\ searchResult' = SearchEligibleSet(p, c, level, sel)
    /\ lastSearch' =
        [ kind       |-> "Search",
          principal  |-> p,
          collection |-> c,
          level      |-> level,
          result     |-> SearchEligibleSet(p, c, level, sel),
          authorized |-> TRUE,
          executed   |-> TRUE ]

RejectSearch(p, c, level) ==
    /\ p \in Principals
    /\ c \in Collections
    /\ level \in ReadConsistencyLevels
    /\ ~CanAccess(p, c, "Read")
    /\ searchResult' = {}
    /\ lastSearch' =
        [ kind       |-> "Reject",
          principal  |-> p,
          collection |-> c,
          level      |-> level,
          result     |-> {},
          authorized |-> FALSE,
          executed   |-> FALSE ]

NextSearch ==
    \/ \E p \in Principals :
        \E c \in Collections :
            \E level \in ReadConsistencyLevels :
                \E sel \in ReplicaSelections : Search(p, c, level, sel)
    \/ \E p \in Principals :
        \E c \in Collections :
            \E level \in ReadConsistencyLevels :
                RejectSearch(p, c, level)

SearchTypeOK ==
    /\ searchResult \subseteq Points
    /\ lastSearch \in SearchRecordT

=============================================================================
