------------------------------- MODULE QAuth ---------------------------------

EXTENDS QCore

VARIABLE permission

AuthVars ==
    <<permission>>

\* Initial permission state: one principal has Manage on every collection,
\* another has no permissions (covering authorized and denied paths).
InitAuth ==
    \E admin \in Principals, nobody \in Principals :
        /\ admin # nobody
        /\ permission = [p \in Principals |->
            CASE p = admin   -> [c \in Collections |-> Operations]
            [] p = nobody    -> [c \in Collections |-> {}]
            [] OTHER         -> [c \in Collections |-> {}]
            ]

\* Can p perform operation op on collection c ?
CanAccess(p, c, op) ==
    op \in permission[p][c]
    \/ "Manage" \in permission[p][c]

\* Grant a permission
GrantPermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ op \notin permission[target][c]
    /\ permission' = [permission EXCEPT ![target][c] = @ \cup {op}]

\* Revoke a permission
RevokePermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ op \in permission[target][c]
    /\ op # "Manage"   \* prevent accidental escalate via revoke loop
    /\ permission' = [permission EXCEPT ![target][c] = @ \ {op}]

NextAuth ==
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
        GrantPermission(admin, target, c, op)
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
        RevokePermission(admin, target, c, op)

AuthTypeOK ==
    permission \in [Principals -> [Collections -> SUBSET Operations]]

=============================================================================
