------------------------------- MODULE CAuth -------------------------------

EXTENDS CCore

VARIABLES
    permission,
    lastWrite,
    lastQuery,
    lastMigrate

WriteRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      keyspace   : Keyspaces,
      dataItem   : DataItems,
      authorized : BOOLEAN,
      accepted   : BOOLEAN ]

QueryRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      keyspace   : Keyspaces,
      level      : {"ONE", "QUORUM", "ALL"},
      result     : SUBSET DataItems,
      authorized : BOOLEAN,
      executed   : BOOLEAN ]

MigrateRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      keyspace   : Keyspaces,
      tokenRange : TokenRanges,
      phase      : {"Start", "Advance", "Activate", "Finish"},
      authorized : BOOLEAN ]

InitAuth ==
    /\ permission = [p \in Principals |-> [k \in Keyspaces |-> {}]]
    /\ lastWrite = [ kind |-> "None",
                     principal |-> CHOOSE p \in Principals : TRUE,
                     keyspace |-> CHOOSE k \in Keyspaces : TRUE,
                     dataItem |-> CHOOSE d \in DataItems : TRUE,
                     authorized |-> FALSE,
                     accepted |-> FALSE ]
    /\ lastQuery = [ kind |-> "None",
                     principal |-> CHOOSE p \in Principals : TRUE,
                     keyspace |-> CHOOSE k \in Keyspaces : TRUE,
                     level |-> "ONE",
                     result |-> {},
                     authorized |-> FALSE,
                     executed |-> FALSE ]
    /\ lastMigrate = [ kind |-> "None",
                        principal |-> CHOOSE p \in Principals : TRUE,
                        keyspace |-> CHOOSE k \in Keyspaces : TRUE,
                        tokenRange |-> CHOOSE tr \in TokenRanges : TRUE,
                        phase |-> "Start",
                        authorized |-> FALSE ]

CanAccess(p, k, op) ==
    /\ p \in Principals
    /\ k \in Keyspaces
    /\ \/ op \in permission[p][k]
       \/ "Manage" \in permission[p][k]

GrantPermission(admin, target, k, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ k \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, k, "Manage")
    /\ permission' = [permission EXCEPT ![target][k] = @ \cup {op}]
    /\ UNCHANGED <<lastWrite, lastQuery, lastMigrate>>

RevokePermission(admin, target, k, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ k \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, k, "Manage")
    /\ permission' = [permission EXCEPT ![target][k] = @ \ {op}]
    /\ UNCHANGED <<lastWrite, lastQuery, lastMigrate>>

AuthTypeOK ==
    /\ permission \in [Principals -> [Keyspaces -> SUBSET Operations]]
    /\ lastWrite \in WriteRecordT
    /\ lastQuery \in QueryRecordT
    /\ lastMigrate \in MigrateRecordT

=============================================================================
