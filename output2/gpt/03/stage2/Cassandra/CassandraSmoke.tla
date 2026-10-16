----------------------------- MODULE CassandraSmoke -----------------------------

EXTENDS CassandraFrontier, CassandraCfgHelpers

CfgPrincipalRole ==
    UniformMap(Principals, Roles)

CfgLoginEnabled ==
    BooleanTrueMap(Roles)

CfgRoleMembership ==
    EmptySetMap(Roles)

CfgTableKeyspace ==
    UniformMap(Tables, Keyspaces)

CfgPartitionTable ==
    UniformMap(Partitions, Tables)

CfgPartitionKey ==
    UniformMap(Partitions, PartitionKeys)

CfgPartitionToken ==
    UniformMap(Partitions, Tokens)

CfgRangeOfToken ==
    UniformMap(Tokens, TokenRanges)

CfgRangeKeyspace ==
    UniformMap(TokenRanges, Keyspaces)

CfgItemPartition ==
    UniformMap(Items, Partitions)

CfgTokenNode ==
    UniformMap(Tokens, Nodes)

CfgNodeDatacenter ==
    UniformMap(Nodes, Datacenters)

CfgMutationItem ==
    UniformMap(Mutations, Items)

CfgMutationVersion ==
    MutationVersionMap(Mutations)

CfgMutationKind ==
    MutationKindMap(Mutations)

CfgReplicationFactor ==
    ReplicationFactorMap(Keyspaces)

CfgInitialReplicaSets ==
    ReplicaSetMap(TokenRanges, Nodes)

CfgInitialPermissionStore ==
    PermissionStoreMap(Roles, Tables)

CassandraSmokeSpec ==
    Spec

SmokeStateConstraint ==
    /\ permissionStore = InitialPermissionStore
    /\ authView = [n \in Nodes |-> InitialPermissionStore]
    /\ nodeAvailable = [n \in Nodes |-> TRUE]
    /\ activeReplicas = initialReplicaSets
    /\ plannedReplicas = initialReplicaSets
    /\ migrateState = [r \in TokenRanges |-> "Stable"]
    /\ migrateEpoch = [r \in TokenRanges |-> 0]
    /\ migrateBoundary = [r \in TokenRanges |-> {}]
    /\ lastRead.kind = "None"
    /\ lastMigrate.kind = "None"
    /\ lastAuth.kind = "None"

=============================================================================
