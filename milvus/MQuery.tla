------------------------------- MODULE MQuery -------------------------------

EXTENDS MSync

VARIABLES
    consistencyVector, lastQuery

QueryVars ==
    <<consistencyVector, lastQuery>>

QueryRecordT ==
    [ kind       : {"None", "Some"},
      user       : Users,
      node       : Nodes,
      collection : Collections,
      shard      : Shards,
      level      : ConsistencyLevels,
      required   : VersionT,
      available  : VersionT,
      observed   : VersionT,
      authorized : BOOLEAN,
      executed   : BOOLEAN ]

QueryTypeInvariant ==
    /\ consistencyVector \in [Nodes -> [Collections -> VersionT]]
    /\ lastQuery \in QueryRecordT

InitQuery ==
    /\ consistencyVector =
        [n \in Nodes |-> [c \in Collections |-> 0]]
    /\ lastQuery =
        [ kind       |-> "None",
          user       |-> CHOOSE u \in Users : TRUE,
          node       |-> CHOOSE n \in Nodes : TRUE,
          collection |-> CHOOSE c \in Collections : TRUE,
          shard      |-> CHOOSE s \in Shards : TRUE,
          level      |-> "Eventually",
          required   |-> 0,
          available  |-> 0,
          observed   |-> 0,
          authorized |-> FALSE,
          executed   |-> FALSE ]

GuaranteeTs(user, c, level) ==
    LET s == ShardFor(c) IN
    CASE level = "Strong" ->
            versionVector[s]

      [] level = "Bounded" ->
            IF versionVector[s] >= MaxCatchUpLag
            THEN versionVector[s] - MaxCatchUpLag
            ELSE 0

      [] level = "Session" ->
            sessionWriteTs[user][c]

      [] level = "Eventually" ->
            0

QueryExecute(user, node, c, level) ==
    LET s == ShardFor(c) IN
    LET required == GuaranteeTs(user, c, level) IN
    LET available == syncedVersions[node][s] IN
    LET observed ==
        IF consistencyVector[node][c] >= required
        THEN consistencyVector[node][c]
        ELSE required
    IN
    /\ user \in Users
    /\ node \in Nodes
    /\ c \in Collections
    /\ level \in ConsistencyLevels
    /\ CanRead(user, c)
    /\ required <= available
    /\ observed <= available
    /\ consistencyVector' =
        [consistencyVector EXCEPT ![node][c] = observed]
    /\ lastQuery' =
        [ kind       |-> "Some",
          user       |-> user,
          node       |-> node,
          collection |-> c,
          shard      |-> s,
          level      |-> level,
          required   |-> required,
          available  |-> available,
          observed   |-> observed,
          authorized |-> TRUE,
          executed   |-> TRUE ]

NextQueryLocal ==
    \/ /\ NextSync
       /\ UNCHANGED QueryVars

    \/ /\ \E u \in Users,
             n \in Nodes,
             c \in Collections,
             level \in ConsistencyLevels :
            QueryExecute(u, n, c, level)
       /\ UNCHANGED <<tsoVector, versionVector, sessionWriteTs, lastWrite,
                      pendingWrites, syncedVersions, syncState, lastSync>>

QuerySpec ==
    /\ CoreAssumption
    /\ AuthAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitSync
    /\ InitQuery
    /\ [][NextQueryLocal]_<<versionVector, sessionWriteTs, lastWrite,
                            syncedVersions, syncState, lastSync,
                            consistencyVector, lastQuery>>

QueryNotAheadOfSync ==
    \A n \in Nodes, c \in Collections :
        consistencyVector[n][c] <= syncedVersions[n][ShardFor(c)]

LastQueryAuthorized ==
    lastQuery.kind = "None"
    \/
    /\ lastQuery.authorized = TRUE
    /\ CanRead(lastQuery.user, lastQuery.collection)

LastQuerySafe ==
    lastQuery.kind = "None"
    \/
    /\ lastQuery.executed = TRUE
    /\ lastQuery.observed >= lastQuery.required
    /\ lastQuery.observed <= lastQuery.available

StrongReadSafe ==
    lastQuery.kind = "None"
    \/
    lastQuery.level # "Strong"
    \/
    lastQuery.observed = lastQuery.required

BoundedReadSafe ==
    lastQuery.kind = "None"
    \/
    lastQuery.level # "Bounded"
    \/
    lastQuery.observed >= lastQuery.required

SessionReadSafe ==
    lastQuery.kind = "None"
    \/
    lastQuery.level # "Session"
    \/
    lastQuery.observed >= lastQuery.required

EventuallyReadSafe ==
    lastQuery.kind = "None"
    \/
    lastQuery.level # "Eventually"
    \/
    lastQuery.observed <= lastQuery.available

=============================================================================
