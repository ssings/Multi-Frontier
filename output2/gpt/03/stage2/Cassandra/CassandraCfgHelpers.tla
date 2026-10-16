--------------------------- MODULE CassandraCfgHelpers ---------------------------

Pick(S) ==
    CHOOSE x \in S : TRUE

UniformMap(domain, codomain) ==
    [x \in domain |-> Pick(codomain)]

BooleanTrueMap(domain) ==
    [x \in domain |-> TRUE]

EmptySetMap(domain) ==
    [x \in domain |-> {}]

FullPermissionSet ==
    {"SELECT", "MODIFY", "AUTHORIZE", "MANAGE_TOPOLOGY"}

PermissionStoreMap(roles, tables) ==
    [r \in roles |->
        [resource \in (tables \cup {"Topology"}) |->
            FullPermissionSet]]

ReplicationFactorMap(keyspaces) ==
    [ks \in keyspaces |-> 3]

ReplicaSetMap(ranges, nodes) ==
    [r \in ranges |-> nodes]

MutationVersionMap(mutations) ==
    [m \in mutations |-> 1]

MutationKindMap(mutations) ==
    [m \in mutations |-> "Value"]

=============================================================================
