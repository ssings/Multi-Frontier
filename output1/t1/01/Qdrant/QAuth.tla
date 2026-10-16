------------------------------- MODULE QAuth --------------------------------

EXTENDS QCore

VARIABLE permission

AuthVars == <<permission>>

CanAccess(p, c, op) ==
    op \in permission[p][c]
    \/ "Manage" \in permission[p][c]

\* Choose a single principal that initially holds Manage on every collection.
HasAllPrincipal == CHOOSE p \in Principals : TRUE

InitAuth ==
    /\ permission = [p \in Principals |->
                     [c \in Collections |->
                         IF p = HasAllPrincipal THEN Operations ELSE {} ]]

AuthTypeOK ==
    permission \in [Principals -> [Collections -> SUBSET Operations]]

GrantPermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' = [permission EXCEPT ![target][c] = @ \cup {op}]

RevokePermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ op \in permission[target][c]
    /\ permission' = [permission EXCEPT ![target][c] = @ \ {op}]

NextAuth ==
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
        GrantPermission(admin, target, c, op)
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
        RevokePermission(admin, target, c, op)

=============================================================================
