------------------------------- MODULE CAuth --------------------------------

EXTENDS CCore

VARIABLES
    permission,
    lastWrite,
    lastQuery,
    lastMigrate

AuthVars == <<permission, lastWrite, lastQuery, lastMigrate>>

CanAccess(p, ks, op) ==
    op \in permission[p][ks]
    \/ "Manage" \in permission[p][ks]

CanMigrate(p) ==
    \E ks \in Keyspaces : CanAccess(p, ks, "Migrate")

InitAuth ==
    LET Superuser == CHOOSE p \in Principals : TRUE
    IN
    /\ permission = [p \in Principals |->
        IF p = Superuser
        THEN [ks \in Keyspaces |-> {"Manage"}]
        ELSE [ks \in Keyspaces |-> {}]]
    /\ lastWrite = [kind |-> "None", principal |-> Superuser,
                    keyspace |-> CHOOSE ks \in Keyspaces : TRUE,
                    dataItem |-> CHOOSE d \in DataItems : TRUE,
                    level |-> "ONE", authorized |-> FALSE]
    /\ lastQuery = [kind |-> "None", principal |-> Superuser,
                    keyspace |-> CHOOSE ks \in Keyspaces : TRUE,
                    level |-> "ONE", result |-> {},
                    authorized |-> FALSE]
    /\ lastMigrate = [kind |-> "None", principal |-> Superuser,
                       tokenRange |-> CHOOSE tr \in TokenRanges : TRUE,
                       phase |-> "Start", authorized |-> FALSE]

GrantPermission(admin, target, ks, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, ks, "Manage")
    /\ permission' = [permission EXCEPT ![target][ks] = @ \cup {op}]
    /\ UNCHANGED <<lastWrite, lastQuery, lastMigrate>>

RevokePermission(admin, target, ks, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, ks, "Manage")
    /\ permission' = [permission EXCEPT ![target][ks] = @ \ {op}]
    /\ UNCHANGED <<lastWrite, lastQuery, lastMigrate>>

RejectAuthWrite(p, ks, d, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ d \in DataItems
    /\ level \in WriteConsistencyLevels
    /\ ks = KeyspaceOf(d)
    /\ ~CanAccess(p, ks, "Write")
    /\ lastWrite' = [kind |-> "Some", principal |-> p,
                     keyspace |-> ks, dataItem |-> d,
                     level |-> level, authorized |-> FALSE]
    /\ UNCHANGED <<permission, lastQuery, lastMigrate>>

RejectAuthQuery(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ ~CanAccess(p, ks, "Read")
    /\ lastQuery' = [kind |-> "Some", principal |-> p,
                     keyspace |-> ks, level |-> level,
                     result |-> {}, authorized |-> FALSE]
    /\ UNCHANGED <<permission, lastWrite, lastMigrate>>

RejectAuthMigrate(p, tr) ==
    /\ p \in Principals
    /\ tr \in TokenRanges
    /\ ~CanMigrate(p)
    /\ lastMigrate' = [kind |-> "Some", principal |-> p,
                        tokenRange |-> tr, phase |-> "Start",
                        authorized |-> FALSE]
    /\ UNCHANGED <<permission, lastWrite, lastQuery>>

AuthTypeOK ==
    /\ permission \in [Principals -> [Keyspaces -> SUBSET Operations]]
    /\ lastWrite \in [kind: {"None","Some"}, principal: Principals,
                      keyspace: Keyspaces, dataItem: DataItems,
                      level: WriteConsistencyLevels, authorized: BOOLEAN]
    /\ lastQuery \in [kind: {"None","Some"}, principal: Principals,
                      keyspace: Keyspaces, level: ReadConsistencyLevels,
                      result: SUBSET DataItems, authorized: BOOLEAN]
    /\ lastMigrate \in [kind: {"None","Some"}, principal: Principals,
                         tokenRange: TokenRanges,
                         phase: {"Start","Advance","Activate","Finish"},
                         authorized: BOOLEAN]

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
