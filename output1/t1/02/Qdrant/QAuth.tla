--------------------------- MODULE QAuth ---------------------------

EXTENDS QCore

(********************************************
 * Qdrant Authorization module.
 ********************************************)

VARIABLE permission

AuthVars ==
    <<permission>>

InitAuth ==
    LET admin == CHOOSE p \in Principals : TRUE IN
    /\ permission = [p \in Principals |->
                        [c \in Collections |->
                            IF p = admin THEN {"Manage"} ELSE {}]]
    /\ Principals # {admin}  \* ensures at least one powerless principal

CanAccess(p, c, op) ==
    op \in permission[p][c] \/ "Manage" \in permission[p][c]

GrantPermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' = [permission EXCEPT ![target][c] = @ \cup {op}]
    /\ UNCHANGED <<AuthVars>>

RevokePermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' = [permission EXCEPT ![target][c] = @ \ {op}]
    /\ UNCHANGED <<AuthVars>>

NextAuth ==
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
          GrantPermission(admin, target, c, op)
    \/ \E admin, target \in Principals, c \in Collections, op \in Operations :
          RevokePermission(admin, target, c, op)

AuthTypeOK ==
    permission \in [Principals -> [Collections -> SUBSET Operations]]

=============================================================================
