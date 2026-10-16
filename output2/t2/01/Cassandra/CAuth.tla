------------------------------- MODULE CAuth -------------------------------

EXTENDS CCore

VARIABLES permission

InitAuth ==
    \E sp \in Principals :
        permission = [p \in Principals |->
            IF p = sp
            THEN [k \in Keyspaces |-> {"Manage"}]
            ELSE [k \in Keyspaces |-> {}]]

CanAccess(p, k, op) ==
    op \in permission[p][k]
    \/ "Manage" \in permission[p][k]

CanMigrate(p) ==
    \E k \in Keyspaces : CanAccess(p, k, "Migrate")
                     \/ CanAccess(p, k, "Manage")

GrantPermission(admin, target, k, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ k \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, k, "Manage")
    /\ permission' = [permission EXCEPT ![target][k] = @ \cup {op}]

RevokePermission(admin, target, k, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ k \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, k, "Manage")
    /\ permission' = [permission EXCEPT ![target][k] = @ \ {op}]

NextAuthOnly ==
    \/ \E a, t, k, o : GrantPermission(a, t, k, o)
    \/ \E a, t, k, o : RevokePermission(a, t, k, o)

AuthTypeInvariant ==
    /\ permission \in [Principals -> [Keyspaces -> SUBSET Operations]]

=============================================================================
