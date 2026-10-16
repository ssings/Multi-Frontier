------------------------------- MODULE CAuth -------------------------------

EXTENDS CCore

VARIABLE permission

AuthVars == <<permission>>

AuthTypeOK ==
    permission \in [Principals -> [Keyspaces -> SUBSET Operations]]

CanAccess(p, ks, op) ==
    op \in permission[p][ks]
    \/ "Manage" \in permission[p][ks]

InitAuth ==
    LET admin == CHOOSE p \in Principals : TRUE
        ks == CHOOSE k \in Keyspaces : TRUE
    IN permission = [p \in Principals |-> 
                        [k \in Keyspaces |-> 
                            IF p = admin /\ k = ks THEN {"Manage"} ELSE {}]]

GrantPermission(admin, target, ks, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, ks, "Manage")
    /\ permission' = [permission EXCEPT ![target][ks] = @ \cup {op}]

RevokePermission(admin, target, ks, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, ks, "Manage")
    /\ permission' = [permission EXCEPT ![target][ks] = @ \ {op}]

NextAuth ==
    \/ \E admin, target \in Principals, ks \in Keyspaces, op \in Operations :
        GrantPermission(admin, target, ks, op)
    \/ \E admin, target \in Principals, ks \in Keyspaces, op \in Operations :
        RevokePermission(admin, target, ks, op)

=============================================================================
