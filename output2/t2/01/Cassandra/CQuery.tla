------------------------------- MODULE CQuery -------------------------------

EXTENDS CMigrate

VARIABLES
    queryResult,
    lastQuery

QueryRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      keyspace   : Keyspaces,
      level      : ConsistencyLevels,
      authorized : BOOLEAN,
      executed   : BOOLEAN ]

QueryTypeInvariant ==
    /\ queryResult \subseteq DataItems
    /\ lastQuery \in QueryRecordT

SearchEligibleSet(p, k, level) ==
    {d \in DataItems :
        /\ DataItemKeyspace(d) = k
        /\ CanAccess(p, k, "Read")
        /\ d \in committed
        /\ Visible(d, level)
        /\ MigrationSafe(d)}

InitQuery ==
    /\ queryResult = {}
    /\ lastQuery =
        [ kind       |-> "None",
          principal  |-> CHOOSE p \in Principals : TRUE,
          keyspace   |-> CHOOSE k \in Keyspaces : TRUE,
          level      |-> "ONE",
          authorized |-> FALSE,
          executed   |-> FALSE ]

Query(p, k, level) ==
    /\ p \in Principals
    /\ k \in Keyspaces
    /\ level \in ConsistencyLevels
    /\ CanAccess(p, k, "Read")
    /\ queryResult' = SearchEligibleSet(p, k, level)
    /\ lastQuery' =
        [ kind       |-> "Some",
          principal  |-> p,
          keyspace   |-> k,
          level      |-> level,
          authorized |-> TRUE,
          executed   |-> TRUE ]
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas,
                   lastWrite,
                   tokenReplicas, migrateState, migrateSrcNodes,
                   migrateDstNodes, copiedData, lastMigrate>>

RejectQuery(p, k, level) ==
    /\ p \in Principals
    /\ k \in Keyspaces
    /\ level \in ConsistencyLevels
    /\ ~CanAccess(p, k, "Read")
    /\ queryResult' = {}
    /\ lastQuery' =
        [ kind       |-> "Some",
          principal  |-> p,
          keyspace   |-> k,
          level      |-> level,
          authorized |-> FALSE,
          executed   |-> FALSE ]
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas,
                   lastWrite,
                   tokenReplicas, migrateState, migrateSrcNodes,
                   migrateDstNodes, copiedData, lastMigrate>>

NextQueryOnly ==
    \/ \E p, k, level : Query(p, k, level)
    \/ \E p, k, level : RejectQuery(p, k, level)

=============================================================================
