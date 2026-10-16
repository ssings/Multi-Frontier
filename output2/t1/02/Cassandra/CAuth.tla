------------------------------- MODULE CAuth -------------------------------

EXTENDS CCore

VARIABLE permission

AuthVars == <<permission>>

InitAuth ==
    permission = [p \in Principals |-> [ks \in Keyspaces |-> {}]]

CanAccess(p, ks, op) ==
    op \in permission[p][ks]
    \/ "Manage" \in permission[p][ks]

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
    /\ op \in Operations
    /\ CanAccess(actor, ks, "Manage")
    /\ permission' = [permission EXCEPT ![target][ks] = @ \ {op}]

NextAuth ==
    \/ \E actor, target \in Principals, ks \in Keyspaces, op \in Operations :
        GrantPermission(actor, target, ks, op)
    \/ \E actor, target \in Principals, ks \in Keyspaces, op \in Operations :
        RevokePermission(actor, target, ks, op)

AuthTypeOK ==
    permission \in [Principals -> [Keyspaces -> SUBSET Operations]]

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
