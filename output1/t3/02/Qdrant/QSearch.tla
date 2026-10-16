------------------------------- MODULE QSearch -------------------------------

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
    /\ UNCHANGED <<permission,
                   writeState, wal, applied, ackSet,
                   replicaHas, shardData, lastWrite,
                   shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, copiedData, lastMigrate>>

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
          executed   |-> TRUE ]
    /\ UNCHANGED <<permission,
                   writeState, wal, applied, ackSet,
                   replicaHas, shardData, lastWrite,
                   shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, copiedData, lastMigrate>>

GrantPermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ op \notin permission[target][c]   \* avoid stuttering
    /\ permission' = [permission EXCEPT ![target][c] = @ \cup {op}]
    /\ UNCHANGED <<writeState, wal, applied, ackSet,
                   replicaHas, shardData, lastWrite,
                   shardOwner, shardLocation, migrateState,
                   migrateSrc, migrateDst, copiedData,
                   searchResult, lastSearch, lastMigrate>>

RevokePermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ op \in permission[target][c]
    /\ (op = "Manage") => \E other \in Principals \ {target} : "Manage" \in permission[other][c]
    /\ LET new_permission == [permission EXCEPT ![target][c] = @ \ {op}]
           new_lastSearch == IF (target = lastSearch.principal) /\ (c = lastSearch.collection)
                                /\ ( (op = "Read")
                                     \/ (op = "Manage"
                                         /\ "Read" \notin new_permission[target][c]
                                         /\ "Manage" \notin new_permission[target][c]) )
                             THEN [lastSearch EXCEPT !.authorized = FALSE, !.executed = FALSE, !.kind = "None", !.result = {}]
                             ELSE lastSearch
           new_lastWrite == IF (target = lastWrite.principal) /\ (c = lastWrite.collection)
                                /\ ( (op = "Write")
                                     \/ (op = "Manage"
                                         /\ "Write" \notin new_permission[target][c]
                                         /\ "Manage" \notin new_permission[target][c]) )
                             THEN [lastWrite EXCEPT !.authorized = FALSE, !.kind = "None"]
                             ELSE lastWrite
           new_lastMigrate == IF (target = lastMigrate.principal) /\ (c = shardCollection[lastMigrate.shard])
                                   /\ ( (op = "Migrate")
                                        \/ (op = "Manage"
                                            /\ "Migrate" \notin new_permission[target][c]
                                            /\ "Manage" \notin new_permission[target][c]) )
                                THEN [lastMigrate EXCEPT !.authorized = FALSE, !.kind = "None"]
                                ELSE lastMigrate
       IN
           /\ permission' = new_permission
           /\ lastSearch' = new_lastSearch
           /\ lastWrite' = new_lastWrite
           /\ lastMigrate' = new_lastMigrate
           /\ UNCHANGED <<writeState, wal, applied, ackSet,
                          replicaHas, shardData,
                          shardOwner, shardLocation, migrateState,
                          migrateSrc, migrateDst, copiedData, searchResult>>

NextSearch ==
    \/ \E p \in Principals, c \in Collections, level \in ReadConsistencyLevels :
          \E sel \in ReplicaSelections : Search(p, c, level, sel)
    \/ \E p \in Principals, c \in Collections, level \in ReadConsistencyLevels :
          RejectSearch(p, c, level)
    \/ \E admin \in Principals, target \in Principals, c \in Collections, op \in Operations :
          GrantPermission(admin, target, c, op)
    \/ \E admin \in Principals, target \in Principals, c \in Collections, op \in Operations :
          RevokePermission(admin, target, c, op)

=============================================================================
