------------------------------ MODULE QSearch -----------------------------

EXTENDS QMigrate

VARIABLES
    searchResult,
    lastSearch

SearchVars ==
    <<searchResult, lastSearch>>

SearchRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      collection : Collections,
      level      : ReadConsistencyLevels,
      result     : SUBSET Points,
      authorized : BOOLEAN,
      executed   : BOOLEAN ]

SearchTypeOK ==
    /\ searchResult \subseteq Points
    /\ lastSearch \in SearchRecordT

InitSearch ==
    /\ searchResult = {}
    /\ lastSearch =
        [ kind       |-> "None",
          principal  |-> CHOOSE p \in Principals : TRUE,
          collection |-> CHOOSE c \in Collections : TRUE,
          level      |-> "One",
          result     |-> {},
          authorized |-> FALSE,
          executed   |-> FALSE ]

\* SearchEligibleSet defines the exact set of points visible to the search
SearchEligibleSet(p, c, level, sel) ==
    {pt \in Points :
        /\ pointCollection[pt] = c
        /\ CanAccess(p, c, "Read")
        /\ pt \in applied
        /\ Visible(pt, level, sel)
        /\ MigrationSafe(pt)}

\* Successful search returns exactly the eligible set
Search(p, c, level, sel) ==
    /\ sel \in ReplicaSelections
    /\ p \in Principals
    /\ c \in Collections
    /\ level \in ReadConsistencyLevels
    /\ CanAccess(p, c, "Read")
    /\ searchResult' = SearchEligibleSet(p, c, level, sel)
    /\ lastSearch' =
        [ kind       |-> "Some",
          principal  |-> p,
          collection |-> c,
          level      |-> level,
          result     |-> SearchEligibleSet(p, c, level, sel),
          authorized |-> TRUE,
          executed   |-> TRUE ]
    /\ UNCHANGED <<permission,
                    writeState, wal, applied, ackSet, replicaHas, shardData,
                    lastWrite,
                    shardOwner, shardLocation, migrateState,
                    migrateSrc, migrateDst, copiedData, lastMigrate>>

\* Unauthorized search attempt returns empty result
RejectSearch(p, c, level) ==
    /\ p \in Principals
    /\ c \in Collections
    /\ level \in ReadConsistencyLevels
    /\ ~CanAccess(p, c, "Read")
    /\ searchResult' = {}
    /\ lastSearch' =
        [ kind       |-> "Some",
          principal  |-> p,
          collection |-> c,
          level      |-> level,
          result     |-> {},
          authorized |-> FALSE,
          executed   |-> FALSE ]
    /\ UNCHANGED <<permission,
                    writeState, wal, applied, ackSet, replicaHas, shardData,
                    lastWrite,
                    shardOwner, shardLocation, migrateState,
                    migrateSrc, migrateDst, copiedData, lastMigrate>>

\* Local next for Search module
NextSearch ==
    \/ \E p \in Principals, c \in Collections, level \in ReadConsistencyLevels :
        \E sel \in ReplicaSelections : Search(p, c, level, sel)
    \/ \E p \in Principals, c \in Collections, level \in ReadConsistencyLevels :
        RejectSearch(p, c, level)

=============================================================================
