------------------------------- MODULE QAuth -------------------------------

EXTENDS QCore

VARIABLE permission

AuthVars == <<permission>>

CanAccess(p, c, op) ==
    op \in permission[p][c]
    \/ "Manage" \in permission[p][c]

\* Initial permission: at least one principal has full Manage rights
\* and at least one principal has no rights
InitAuth ==
    /\ \E admin \in Principals :
          \A c \in Collections : permission[admin][c] = Operations
    /\ \A p \in Principals :
          p \notin {CHOOSE admin \in Principals :
                       \A c \in Collections : permission[admin][c] = Operations}
          => \A c \in Collections : permission[p][c] = {}

AuthTypeOK ==
    permission \in [Principals -> [Collections -> SUBSET Operations]]

GrantPermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' = [permission EXCEPT ![target][c] = permission[target][c] \cup {op}]

RevokePermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' = [permission EXCEPT ![target][c] = permission[target][c] \ {op}]

NextAuth ==
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
          GrantPermission(admin, target, c, op)
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
          RevokePermission(admin, target, c, op)

=============================================================================
