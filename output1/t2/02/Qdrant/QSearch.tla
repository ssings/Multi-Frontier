----------------------------- MODULE QSearch --------------------------

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
        [ kind       |-> "Some",
          principal  |-> p,
          collection |-> c,
          level      |-> level,
          result     |-> SearchEligibleSet(p, c, level, sel),
          authorized |-> TRUE,
          executed   |-> TRUE ]
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData,
                   lastWrite, shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, copiedData, lastMigrate,
                   permission>>

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
    /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData,
                   lastWrite, shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, copiedData, lastMigrate,
                   permission>>

NextSearch ==
    \/ \E p \in Principals, c \in Collections, level \in ReadConsistencyLevels :
        \E sel \in ReplicaSelections : Search(p, c, level, sel)
    \/ \E p \in Principals, c \in Collections, level \in ReadConsistencyLevels :
        RejectSearch(p, c, level)

SearchTypeOK ==
    /\ searchResult \subseteq Points
    /\ lastSearch \in SearchRecordT

AuthSafety ==
    \* The last recorded write must have been authorized if it reports success
    /\ (lastWrite.kind = "Some" /\ lastWrite.authorized) =>
        CanAccess(lastWrite.principal, pointCollection[lastWrite.point], "Write")
    \* The last recorded search must have been authorized if it reports success
    /\ (lastSearch.kind = "Some" /\ lastSearch.authorized) =>
        CanAccess(lastSearch.principal, lastSearch.collection, "Read")
    \* The last recorded migrate must have been authorized if it reports success
    /\ (lastMigrate.kind = "Some" /\ lastMigrate.authorized) =>
        CanAccess(lastMigrate.principal, shardCollection[lastMigrate.shard], "Migrate")

FrontierSafety ==
    /\ WalBeforeApply
    /\ ReplicaNotAheadOfWAL
    /\ MigrateSafety
    /\ AuthSafety

GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ ReplicaTypeOK
    /\ MigrateTypeOK
    /\ SearchTypeOK

=============================================================================
