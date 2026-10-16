--------------------------- MODULE QAuth ---------------------------

EXTENDS QCore

VARIABLE permission

AuthVars == <<permission>>

InitAuth ==
    LET admin == CHOOSE p \in Principals : TRUE
        nope  == CHOOSE p \in Principals \ {admin} : TRUE
    IN
    permission = [ p \in Principals |-> 
                    [ c \in Collections |-> 
                        IF p = admin THEN {"Read","Write","Manage","Migrate"}
                        ELSE IF p = nope THEN {}
                        ELSE {"Read"} ] ]

CanAccess(p, c, op) ==
    op \in permission[p][c] \/ "Manage" \in permission[p][c]

GrantPermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' = [permission EXCEPT ![target][c] =
                        permission[target][c] \cup {op}]

RevokePermission(admin, target, c, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ c \in Collections
    /\ op \in Operations
    /\ CanAccess(admin, c, "Manage")
    /\ permission' = [permission EXCEPT ![target][c] =
                        permission[target][c] \ {op}]

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
    permission \in [Principals -> [Collections -> SUBSET Operations]]

AuthSafety == AuthTypeOK

=============================================================================
