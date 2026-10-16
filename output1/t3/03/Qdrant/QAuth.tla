------------------------------ MODULE QAuth ------------------------------

EXTENDS QCore

VARIABLES
    permission

AuthVars ==
    <<permission>>

\* CanAccess(p, c, op) is true iff p has op or Manage on collection c
CanAccess(p, c, op) ==
    \/ op \in permission[p][c]
    \/ "Manage" \in permission[p][c]

\* Initial permission state: at least one principal has Manage on some collection,
\* another principal has no permissions (so both authorized and unauthorized paths exist).
InitAuth ==
    /\ CoreAssumption
    /\ LET defaultPerm == [p \in Principals |-> [c \in Collections |-> {}]]
       IN  \E managed \in Principals :
           \E col \in Collections :
               permission = [defaultPerm EXCEPT ![managed][col] = {"Manage"}]

\* GrantPermission: admin must have Manage on the collection to grant an operation
GrantPermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' =
        [permission EXCEPT ![target][c] = @ \cup {op}]

\* RevokePermission: admin must have Manage on the collection to revoke an operation
RevokePermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' =
        [permission EXCEPT ![target][c] = @ \ {op}]

\* Local next for Auth module
NextAuth ==
    \/ \E admin \in Principals, target \in Principals,
            c \in Collections, op \in Operations :
        GrantPermission(admin, target, c, op)
    \/ \E admin \in Principals, target \in Principals,
            c \in Collections, op \in Operations :
        RevokePermission(admin, target, c, op)

\* Type invariant for permission
AuthTypeOK ==
    permission \in [Principals -> [Collections -> SUBSET Operations]]

=============================================================================
