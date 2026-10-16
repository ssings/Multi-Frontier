--------------------------- MODULE QAuth ---------------------------
EXTENDS QCore

VARIABLE permission

AuthVars == <<permission>>

InitAuth ==
    \E admin \in Principals, noPerm \in Principals :
        /\ admin # noPerm
        /\ permission = [p \in Principals |-> [c \in Collections |-> IF p = admin THEN {"Manage"} ELSE {}]]

CanAccess(p, c, op) ==
    \/ op \in permission[p][c]
    \/ "Manage" \in permission[p][c]

GrantPermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations \ {"Manage"}
    /\ CanAccess(admin, c, "Manage")
    /\ permission' = [permission EXCEPT ![target][c] = @ \cup {op}]

RevokePermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations \ {"Manage"}
    /\ CanAccess(admin, c, "Manage")
    /\ permission' = [permission EXCEPT ![target][c] = @ \ {op}]

NextAuth ==
    \/ \E admin \in Principals, target \in Principals, c \in Collections, op \in Operations \ {"Manage"} :
        GrantPermission(admin, target, c, op)
    \/ \E admin \in Principals, target \in Principals, c \in Collections, op \in Operations \ {"Manage"} :
        RevokePermission(admin, target, c, op)

AuthTypeOK ==
    permission \in [Principals -> [Collections -> SUBSET Operations]]

=============================================================================
