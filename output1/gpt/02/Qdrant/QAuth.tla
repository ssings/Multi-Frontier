------------------------------- MODULE QAuth -------------------------------

EXTENDS QCore

VARIABLES
    permission

AuthVars ==
    <<permission>>

InitialAdmin ==
    CHOOSE p \in Principals : TRUE

CanAccess(p, c, op) ==
    /\ p \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ (op \in permission[p][c]
        \/ "Manage" \in permission[p][c])

AuthTypeOK ==
    permission \in
        [Principals -> [Collections -> SUBSET Operations]]

InitAuth ==
    permission =
        [p \in Principals |->
            [c \in Collections |->
                IF p = InitialAdmin
                THEN Operations
                ELSE {}]]

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

=============================================================================
