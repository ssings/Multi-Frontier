------------------------------- MODULE QAuth -------------------------------

EXTENDS QCore

VARIABLES
    permission

AuthVars == <<permission>>

PermissionRecordT ==
    [Collections -> SUBSET Operations]

InitAuth ==
    LET initialAdmin == CHOOSE p \in Principals : TRUE IN
    /\ permission =
        [p \in Principals |->
            IF p = initialAdmin
            THEN [c \in Collections |-> Operations]
            ELSE [c \in Collections |-> {}]]

CanAccess(p, c, op) ==
    /\ p \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ \/ op \in permission[p][c]
       \/ "Manage" \in permission[p][c]

GrantPermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' =
        [permission EXCEPT ![target][c] = @ \cup {op}]

RevokePermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' =
        [permission EXCEPT ![target][c] = @ \ {op}]

NextAuth ==
    \/ \E admin \in Principals :
        \E target \in Principals :
            \E c \in Collections :
                \E op \in Operations :
                    GrantPermission(admin, target, c, op)
    \/ \E admin \in Principals :
        \E target \in Principals :
            \E c \in Collections :
                \E op \in Operations :
                    RevokePermission(admin, target, c, op)

AuthTypeOK ==
    permission \in [Principals -> PermissionRecordT]

=============================================================================
