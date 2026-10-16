------------------------------- MODULE CAuth -------------------------------

EXTENDS CCore

VARIABLE permission

AuthVars == <<permission>>

CanAccess(p, ks, op) ==
    op \in permission[p][ks] \/ "Manage" \in permission[p][ks]

InitAuth ==
    permission = [p \in Principals |-> [ks \in Keyspaces |-> {}]]

GrantPermission(actor, target, ks, op) ==
    /\ actor \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(actor, ks, "Manage")
    /\ permission' = [permission EXCEPT ![target][ks] = @ \cup {op}]

RevokePermission(actor, target, ks, op) ==
    /\ actor \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations \ {"Manage"}
    /\ CanAccess(actor, ks, "Manage")
    /\ permission' = [permission EXCEPT ![target][ks] = @ \ {op}]

NextAuth ==
    \/ \E a, t, ks, op : GrantPermission(a, t, ks, op)
    \/ \E a, t, ks, op : RevokePermission(a, t, ks, op)

AuthTypeOK ==
    permission \in [Principals -> [Keyspaces -> SUBSET Operations]]

=============================================================================
