--------------------------- MODULE CassandraFrontier ---------------------------

EXTENDS Naturals, FiniteSets

CONSTANTS
    Principals,
    Roles,
    Nodes,
    Datacenters,
    Keyspaces,
    Tables,
    Partitions,
    PartitionKeys,
    Items,
    Mutations,
    Tokens,
    TokenRanges,

    principalRole,
    loginEnabled,
    superuser,
    roleMembership,

    tableKeyspace,
    partitionTable,
    partitionKey,
    partitionToken,
    rangeOfToken,
    rangeKeyspace,
    itemPartition,

    tokenNode,
    nodeDatacenter,

    mutationItem,
    mutationVersion,
    mutationKind,

    replicationFactor,
    initialReplicaSets,
    InitialPermissionStore

VARIABLES
    permissionStore,
    authView,
    nodeAvailable,

    writeFrontier,
    writeTargets,
    writeLevel,
    writeCoordinator,
    writeAuthor,
    writeSucceeded,
    acked,

    commitLog,
    replicaApplied,
    hintStore,

    activeReplicas,
    plannedReplicas,
    migrateState,
    migrateEpoch,
    migrateBoundary,

    lastWrite,
    lastRead,
    lastMigrate,
    lastAuth

TopologyResource == "Topology"

PermissionKinds == {"SELECT", "MODIFY", "AUTHORIZE", "MANAGE_TOPOLOGY"}

WriteLevels == {"ONE", "QUORUM", "ALL"}

ReadLevels == {"ONE", "QUORUM", "ALL"}

MigrateModes == {"Bootstrap", "Decommission", "Move", "Replace"}

MigrateStates == {"Stable", "Streaming", "Activated"}

SyncMethods == {"ReadRepair", "AntiEntropyRepair"}

NoMutation == "NoMutation"

Resources == Tables \cup {TopologyResource}

NodeTokens(n) == {t \in Tokens : tokenNode[t] = n}

PartitionRange(p) == rangeOfToken[partitionToken[p]]

ItemTable(i) == partitionTable[itemPartition[i]]

ItemRange(i) == PartitionRange(itemPartition[i])

ItemMutations(ms, i) ==
    {m \in ms : mutationItem[m] = i}

Winner(ms, i) ==
    IF ItemMutations(ms, i) = {}
    THEN NoMutation
    ELSE
        CHOOSE m \in ItemMutations(ms, i) :
            \A q \in ItemMutations(ms, i) :
                mutationVersion[q] <= mutationVersion[m]

WinnerIsValue(ms, i) ==
    /\ Winner(ms, i) # NoMutation
    /\ mutationKind[Winner(ms, i)] = "Value"

InheritedRoles(r) ==
    {q \in Roles : q = r \/ q \in roleMembership[r]}

EffectivePermissions(view, p, resource) ==
    UNION {view[r][resource] : r \in InheritedRoles(principalRole[p])}

CanSelect(view, p, table) ==
    /\ loginEnabled[principalRole[p]]
    /\ ("SELECT" \in EffectivePermissions(view, p, table)
        \/ principalRole[p] \in superuser)

CanModify(view, p, table) ==
    /\ loginEnabled[principalRole[p]]
    /\ ("MODIFY" \in EffectivePermissions(view, p, table)
        \/ principalRole[p] \in superuser)

CanAuthorize(view, p, resource) ==
    /\ loginEnabled[principalRole[p]]
    /\ ("AUTHORIZE" \in EffectivePermissions(view, p, resource)
        \/ principalRole[p] \in superuser)

CanManageTopology(view, p) ==
    /\ loginEnabled[principalRole[p]]
    /\ ("MANAGE_TOPOLOGY" \in EffectivePermissions(view, p, TopologyResource)
        \/ principalRole[p] \in superuser)

Required(level, replicaSet) ==
    CASE level = "ONE" -> 1
      [] level = "QUORUM" -> (Cardinality(replicaSet) \div 2) + 1
      [] level = "ALL" -> Cardinality(replicaSet)

ValidReplicaSet(ks, replicaSet) ==
    /\ replicaSet \subseteq Nodes
    /\ replicaSet # {}
    /\ Cardinality(replicaSet) = replicationFactor[ks]

AvailableReplicas(r) ==
    {n \in activeReplicas[r] : nodeAvailable[n]}

ReadResponsesOK(level, routing, responders) ==
    /\ responders \subseteq routing
    /\ Cardinality(responders) >= Required(level, routing)

ResponseMutations(responders) ==
    UNION {replicaApplied[n] : n \in responders}

QueryFrontier(i, responders) ==
    IF WinnerIsValue(ResponseMutations(responders), i)
    THEN {Winner(ResponseMutations(responders), i)}
    ELSE {}

MigrateFrontier(r) ==
    {m \in writeFrontier : ItemRange(mutationItem[m]) = r}

CoveredBy(replicaSet, mutations) ==
    \A n \in replicaSet : mutations \subseteq replicaApplied[n]

MigrationSafe(r) ==
    CoveredBy(activeReplicas[r], migrateBoundary[r])

FinalQueryFrontier(authorized, i, responders) ==
    IF authorized /\ MigrationSafe(ItemRange(i))
    THEN QueryFrontier(i, responders)
    ELSE {}

LegalSyncTarget(m, n) ==
    \/ n \in activeReplicas[ItemRange(mutationItem[m])]
    \/ /\ migrateState[ItemRange(mutationItem[m])] = "Streaming"
       /\ n \in plannedReplicas[ItemRange(mutationItem[m])]

SomePrincipal == CHOOSE p \in Principals : TRUE

SomeRole == CHOOSE r \in Roles : TRUE

SomeNode == CHOOSE n \in Nodes : TRUE

SomeTable == CHOOSE t \in Tables : TRUE

SomeItem == CHOOSE i \in Items : TRUE

SomeMutation == CHOOSE m \in Mutations : TRUE

SomeRange == CHOOSE r \in TokenRanges : TRUE

StaticAssumptions ==
    /\ Principals # {}
    /\ Roles # {}
    /\ Nodes # {}
    /\ Datacenters # {}
    /\ Keyspaces # {}
    /\ Tables # {}
    /\ Partitions # {}
    /\ PartitionKeys # {}
    /\ Items # {}
    /\ Mutations # {}
    /\ Tokens # {}
    /\ TokenRanges # {}
    /\ NoMutation \notin Mutations

    /\ principalRole \in [Principals -> Roles]
    /\ loginEnabled \in [Roles -> BOOLEAN]
    /\ superuser \subseteq Roles
    /\ roleMembership \in [Roles -> SUBSET Roles]
    /\ \A r \in Roles : r \notin roleMembership[r]
    /\ \A r \in Roles :
        \A q \in roleMembership[r] :
            roleMembership[q] \subseteq roleMembership[r]

    /\ tableKeyspace \in [Tables -> Keyspaces]
    /\ partitionTable \in [Partitions -> Tables]
    /\ partitionKey \in [Partitions -> PartitionKeys]
    /\ partitionToken \in [Partitions -> Tokens]
    /\ rangeOfToken \in [Tokens -> TokenRanges]
    /\ rangeKeyspace \in [TokenRanges -> Keyspaces]
    /\ itemPartition \in [Items -> Partitions]
    /\ \A p \in Partitions :
        tableKeyspace[partitionTable[p]] = rangeKeyspace[PartitionRange(p)]
    /\ \A i \in Items :
        tableKeyspace[ItemTable(i)] = rangeKeyspace[ItemRange(i)]

    /\ tokenNode \in [Tokens -> Nodes]
    /\ nodeDatacenter \in [Nodes -> Datacenters]

    /\ mutationItem \in [Mutations -> Items]
    /\ mutationVersion \in [Mutations -> Nat]
    /\ mutationKind \in [Mutations -> {"Value", "Tombstone"}]
    /\ \A m1 \in Mutations :
        \A m2 \in Mutations :
            /\ m1 # m2
            /\ mutationItem[m1] = mutationItem[m2]
            => mutationVersion[m1] # mutationVersion[m2]

    /\ replicationFactor \in [Keyspaces -> Nat]
    /\ \A ks \in Keyspaces : replicationFactor[ks] > 0
    /\ initialReplicaSets \in [TokenRanges -> SUBSET Nodes]
    /\ \A r \in TokenRanges :
        ValidReplicaSet(rangeKeyspace[r], initialReplicaSets[r])

    /\ InitialPermissionStore \in
        [Roles -> [Resources -> SUBSET PermissionKinds]]

GlobalVars ==
    << permissionStore,
       authView,
       nodeAvailable,
       writeFrontier,
       writeTargets,
       writeLevel,
       writeCoordinator,
       writeAuthor,
       writeSucceeded,
       acked,
       commitLog,
       replicaApplied,
       hintStore,
       activeReplicas,
       plannedReplicas,
       migrateState,
       migrateEpoch,
       migrateBoundary,
       lastWrite,
       lastRead,
       lastMigrate,
       lastAuth >>

WriteRecordT ==
    [ kind        : {"None", "Accepted", "Completed", "Rejected"},
      principal   : Principals,
      coordinator : Nodes,
      mutation    : Mutations,
      level       : WriteLevels,
      authorized  : BOOLEAN,
      completed   : BOOLEAN ]

ReadRecordT ==
    [ kind        : {"None", "Success", "Rejected", "Unavailable"},
      principal   : Principals,
      coordinator : Nodes,
      item        : Items,
      level       : ReadLevels,
      routing     : SUBSET Nodes,
      responders  : SUBSET Nodes,
      result      : SUBSET Mutations,
      frontier    : SUBSET Mutations,
      authorized  : BOOLEAN,
      executed    : BOOLEAN ]

MigrateRecordT ==
    [ kind        : {"None", "Start", "Activate", "Cleanup", "Rejected"},
      principal   : Principals,
      coordinator : Nodes,
      range       : TokenRanges,
      planned     : SUBSET Nodes,
      mode        : MigrateModes,
      authorized  : BOOLEAN ]

AuthRecordT ==
    [ kind        : {"None", "Grant", "Revoke", "Rejected"},
      admin       : Principals,
      coordinator : Nodes,
      targetRole  : Roles,
      resource    : Resources,
      permission  : PermissionKinds,
      authorized  : BOOLEAN ]

Init ==
    /\ StaticAssumptions
    /\ permissionStore = InitialPermissionStore
    /\ authView = [n \in Nodes |-> InitialPermissionStore]
    /\ nodeAvailable = [n \in Nodes |-> TRUE]

    /\ writeFrontier = {}
    /\ writeTargets = [m \in Mutations |-> {}]
    /\ writeLevel = [m \in Mutations |-> "ONE"]
    /\ writeCoordinator = [m \in Mutations |-> SomeNode]
    /\ writeAuthor = [m \in Mutations |-> SomePrincipal]
    /\ writeSucceeded = [m \in Mutations |-> FALSE]
    /\ acked = [m \in Mutations |-> {}]

    /\ commitLog = [n \in Nodes |-> {}]
    /\ replicaApplied = [n \in Nodes |-> {}]
    /\ hintStore = [n \in Nodes |-> {}]

    /\ activeReplicas = initialReplicaSets
    /\ plannedReplicas = initialReplicaSets
    /\ migrateState = [r \in TokenRanges |-> "Stable"]
    /\ migrateEpoch = [r \in TokenRanges |-> 0]
    /\ migrateBoundary = [r \in TokenRanges |-> {}]

    /\ lastWrite =
        [ kind        |-> "None",
          principal   |-> SomePrincipal,
          coordinator |-> SomeNode,
          mutation    |-> SomeMutation,
          level       |-> "ONE",
          authorized  |-> FALSE,
          completed   |-> FALSE ]

    /\ lastRead =
        [ kind        |-> "None",
          principal   |-> SomePrincipal,
          coordinator |-> SomeNode,
          item        |-> SomeItem,
          level       |-> "ONE",
          routing     |-> {},
          responders  |-> {},
          result      |-> {},
          frontier    |-> {},
          authorized  |-> FALSE,
          executed    |-> FALSE ]

    /\ lastMigrate =
        [ kind        |-> "None",
          principal   |-> SomePrincipal,
          coordinator |-> SomeNode,
          range       |-> SomeRange,
          planned     |-> {},
          mode        |-> "Bootstrap",
          authorized  |-> FALSE ]

    /\ lastAuth =
        [ kind        |-> "None",
          admin       |-> SomePrincipal,
          coordinator |-> SomeNode,
          targetRole  |-> SomeRole,
          resource    |-> TopologyResource,
          permission  |-> "SELECT",
          authorized  |-> FALSE ]

GrantPermission(admin, coordinator, targetRole, resource, permission) ==
    /\ admin \in Principals
    /\ coordinator \in Nodes
    /\ targetRole \in Roles
    /\ resource \in Resources
    /\ permission \in PermissionKinds
    /\ nodeAvailable[coordinator]
    /\ CanAuthorize(authView[coordinator], admin, resource)
    /\ permissionStore' =
        [permissionStore EXCEPT
            ![targetRole][resource] = @ \cup {permission}]
    /\ lastAuth' =
        [ kind        |-> "Grant",
          admin       |-> admin,
          coordinator |-> coordinator,
          targetRole  |-> targetRole,
          resource    |-> resource,
          permission  |-> permission,
          authorized  |-> TRUE ]
    /\ UNCHANGED << authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate >>

RevokePermission(admin, coordinator, targetRole, resource, permission) ==
    /\ admin \in Principals
    /\ coordinator \in Nodes
    /\ targetRole \in Roles
    /\ resource \in Resources
    /\ permission \in PermissionKinds
    /\ nodeAvailable[coordinator]
    /\ CanAuthorize(authView[coordinator], admin, resource)
    /\ permissionStore' =
        [permissionStore EXCEPT
            ![targetRole][resource] = @ \ {permission}]
    /\ lastAuth' =
        [ kind        |-> "Revoke",
          admin       |-> admin,
          coordinator |-> coordinator,
          targetRole  |-> targetRole,
          resource    |-> resource,
          permission  |-> permission,
          authorized  |-> TRUE ]
    /\ UNCHANGED << authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate >>

RejectGrantOrRevoke(admin, coordinator, targetRole, resource, permission) ==
    /\ admin \in Principals
    /\ coordinator \in Nodes
    /\ targetRole \in Roles
    /\ resource \in Resources
    /\ permission \in PermissionKinds
    /\ ~CanAuthorize(authView[coordinator], admin, resource)
    /\ lastAuth' =
        [ kind        |-> "Rejected",
          admin       |-> admin,
          coordinator |-> coordinator,
          targetRole  |-> targetRole,
          resource    |-> resource,
          permission  |-> permission,
          authorized  |-> FALSE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate >>

RefreshAuthCache(n) ==
    /\ n \in Nodes
    /\ authView' = [authView EXCEPT ![n] = permissionStore]
    /\ UNCHANGED << permissionStore,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

SetNodeAvailability(n, available) ==
    /\ n \in Nodes
    /\ available \in BOOLEAN
    /\ nodeAvailable' = [nodeAvailable EXCEPT ![n] = available]
    /\ UNCHANGED << permissionStore,
                   authView,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

ReceiveWrite(p, coordinator, m, level) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ m \in Mutations
    /\ level \in WriteLevels
    /\ nodeAvailable[coordinator]
    /\ m \notin writeFrontier
    /\ CanModify(authView[coordinator], p, ItemTable(mutationItem[m]))
    /\ writeFrontier' = writeFrontier \cup {m}
    /\ writeTargets' =
        [writeTargets EXCEPT
            ![m] = activeReplicas[ItemRange(mutationItem[m])]]
    /\ writeLevel' = [writeLevel EXCEPT ![m] = level]
    /\ writeCoordinator' = [writeCoordinator EXCEPT ![m] = coordinator]
    /\ writeAuthor' = [writeAuthor EXCEPT ![m] = p]
    /\ writeSucceeded' = writeSucceeded
    /\ acked' = acked
    /\ lastWrite' =
        [ kind        |-> "Accepted",
          principal   |-> p,
          coordinator |-> coordinator,
          mutation    |-> m,
          level       |-> level,
          authorized  |-> TRUE,
          completed   |-> FALSE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

RejectWrite(p, coordinator, m, level) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ m \in Mutations
    /\ level \in WriteLevels
    /\ ~CanModify(authView[coordinator], p, ItemTable(mutationItem[m]))
    /\ lastWrite' =
        [ kind        |-> "Rejected",
          principal   |-> p,
          coordinator |-> coordinator,
          mutation    |-> m,
          level       |-> level,
          authorized  |-> FALSE,
          completed   |-> FALSE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

LogReplica(m, n) ==
    /\ m \in writeFrontier
    /\ n \in writeTargets[m]
    /\ nodeAvailable[n]
    /\ m \notin commitLog[n]
    /\ commitLog' = [commitLog EXCEPT ![n] = @ \cup {m}]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

ApplyReplica(m, n) ==
    /\ m \in writeFrontier
    /\ m \in commitLog[n]
    /\ m \notin replicaApplied[n]
    /\ replicaApplied' = [replicaApplied EXCEPT ![n] = @ \cup {m}]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

ReplicaAck(m, n) ==
    /\ m \in writeFrontier
    /\ n \in writeTargets[m]
    /\ m \in replicaApplied[n]
    /\ n \notin acked[m]
    /\ acked' = [acked EXCEPT ![m] = @ \cup {n}]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

CompleteWrite(m) ==
    /\ m \in writeFrontier
    /\ ~writeSucceeded[m]
    /\ Cardinality(acked[m]) >= Required(writeLevel[m], writeTargets[m])
    /\ writeSucceeded' = [writeSucceeded EXCEPT ![m] = TRUE]
    /\ lastWrite' =
        [ kind        |-> "Completed",
          principal   |-> writeAuthor[m],
          coordinator |-> writeCoordinator[m],
          mutation    |-> m,
          level       |-> writeLevel[m],
          authorized  |-> TRUE,
          completed   |-> TRUE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

StoreHint(m, holder, target) ==
    /\ m \in writeFrontier
    /\ holder \in Nodes
    /\ target \in writeTargets[m]
    /\ ~nodeAvailable[target]
    /\ m \notin hintStore[holder]
    /\ hintStore' = [hintStore EXCEPT ![holder] = @ \cup {m}]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

ReplayHint(holder, m, target) ==
    /\ holder \in Nodes
    /\ m \in hintStore[holder]
    /\ target \in writeTargets[m]
    /\ nodeAvailable[target]
    /\ m \notin replicaApplied[target]
    /\ commitLog' = [commitLog EXCEPT ![target] = @ \cup {m}]
    /\ replicaApplied' = [replicaApplied EXCEPT ![target] = @ \cup {m}]
    /\ hintStore' = [hintStore EXCEPT ![holder] = @ \ {m}]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

SyncReplica(m, target, method) ==
    /\ m \in writeFrontier
    /\ target \in Nodes
    /\ method \in SyncMethods
    /\ nodeAvailable[target]
    /\ LegalSyncTarget(m, target)
    /\ m \notin replicaApplied[target]
    /\ \E source \in Nodes : m \in replicaApplied[source]
    /\ commitLog' = [commitLog EXCEPT ![target] = @ \cup {m}]
    /\ replicaApplied' = [replicaApplied EXCEPT ![target] = @ \cup {m}]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

StartMigrate(p, coordinator, r, planned, mode) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ r \in TokenRanges
    /\ planned \subseteq Nodes
    /\ mode \in MigrateModes
    /\ nodeAvailable[coordinator]
    /\ CanManageTopology(authView[coordinator], p)
    /\ migrateState[r] = "Stable"
    /\ ValidReplicaSet(rangeKeyspace[r], planned)
    /\ planned # activeReplicas[r]
    /\ plannedReplicas' = [plannedReplicas EXCEPT ![r] = planned]
    /\ migrateState' = [migrateState EXCEPT ![r] = "Streaming"]
    /\ migrateEpoch' = [migrateEpoch EXCEPT ![r] = @ + 1]
    /\ lastMigrate' =
        [ kind        |-> "Start",
          principal   |-> p,
          coordinator |-> coordinator,
          range       |-> r,
          planned     |-> planned,
          mode        |-> mode,
          authorized  |-> TRUE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastAuth >>

RejectTopologyChange(p, coordinator, r, planned, mode) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ r \in TokenRanges
    /\ planned \subseteq Nodes
    /\ mode \in MigrateModes
    /\ ~CanManageTopology(authView[coordinator], p)
    /\ lastMigrate' =
        [ kind        |-> "Rejected",
          principal   |-> p,
          coordinator |-> coordinator,
          range       |-> r,
          planned     |-> planned,
          mode        |-> mode,
          authorized  |-> FALSE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastAuth >>

AdvanceMigrate(r, source, target, m) ==
    /\ r \in TokenRanges
    /\ source \in Nodes
    /\ target \in Nodes
    /\ m \in MigrateFrontier(r)
    /\ migrateState[r] = "Streaming"
    /\ source \in activeReplicas[r]
    /\ target \in plannedReplicas[r]
    /\ nodeAvailable[source]
    /\ nodeAvailable[target]
    /\ m \in replicaApplied[source]
    /\ m \notin replicaApplied[target]
    /\ commitLog' = [commitLog EXCEPT ![target] = @ \cup {m}]
    /\ replicaApplied' = [replicaApplied EXCEPT ![target] = @ \cup {m}]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastMigrate,
                   lastAuth >>

ActivateMigrate(p, coordinator, r) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ r \in TokenRanges
    /\ nodeAvailable[coordinator]
    /\ CanManageTopology(authView[coordinator], p)
    /\ migrateState[r] = "Streaming"
    /\ CoveredBy(plannedReplicas[r], MigrateFrontier(r))
    /\ activeReplicas' = [activeReplicas EXCEPT ![r] = plannedReplicas[r]]
    /\ migrateState' = [migrateState EXCEPT ![r] = "Activated"]
    /\ migrateBoundary' =
        [migrateBoundary EXCEPT ![r] = MigrateFrontier(r)]
    /\ lastMigrate' =
        [ kind        |-> "Activate",
          principal   |-> p,
          coordinator |-> coordinator,
          range       |-> r,
          planned     |-> plannedReplicas[r],
          mode        |-> "Bootstrap",
          authorized  |-> TRUE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   plannedReplicas,
                   migrateEpoch,
                   lastWrite,
                   lastRead,
                   lastAuth >>

CleanupMigrate(p, coordinator, r) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ r \in TokenRanges
    /\ nodeAvailable[coordinator]
    /\ CanManageTopology(authView[coordinator], p)
    /\ migrateState[r] = "Activated"
    /\ migrateState' = [migrateState EXCEPT ![r] = "Stable"]
    /\ plannedReplicas' = [plannedReplicas EXCEPT ![r] = activeReplicas[r]]
    /\ lastMigrate' =
        [ kind        |-> "Cleanup",
          principal   |-> p,
          coordinator |-> coordinator,
          range       |-> r,
          planned     |-> activeReplicas[r],
          mode        |-> "Bootstrap",
          authorized  |-> TRUE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastRead,
                   lastAuth >>

ExecuteRead(p, coordinator, i, level, responders) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ i \in Items
    /\ level \in ReadLevels
    /\ responders \subseteq Nodes
    /\ nodeAvailable[coordinator]
    /\ CanSelect(authView[coordinator], p, ItemTable(i))
    /\ responders \subseteq AvailableReplicas(ItemRange(i))
    /\ ReadResponsesOK(level, activeReplicas[ItemRange(i)], responders)
    /\ MigrationSafe(ItemRange(i))
    /\ lastRead' =
        [ kind        |-> "Success",
          principal   |-> p,
          coordinator |-> coordinator,
          item        |-> i,
          level       |-> level,
          routing     |-> activeReplicas[ItemRange(i)],
          responders  |-> responders,
          result      |-> FinalQueryFrontier(TRUE, i, responders),
          frontier    |-> FinalQueryFrontier(TRUE, i, responders),
          authorized  |-> TRUE,
          executed    |-> TRUE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastMigrate,
                   lastAuth >>

RejectRead(p, coordinator, i, level) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ i \in Items
    /\ level \in ReadLevels
    /\ ~CanSelect(authView[coordinator], p, ItemTable(i))
    /\ lastRead' =
        [ kind        |-> "Rejected",
          principal   |-> p,
          coordinator |-> coordinator,
          item        |-> i,
          level       |-> level,
          routing     |-> {},
          responders  |-> {},
          result      |-> {},
          frontier    |-> {},
          authorized  |-> FALSE,
          executed    |-> FALSE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastMigrate,
                   lastAuth >>

UnavailableRead(p, coordinator, i, level) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ i \in Items
    /\ level \in ReadLevels
    /\ nodeAvailable[coordinator]
    /\ CanSelect(authView[coordinator], p, ItemTable(i))
    /\ Cardinality(AvailableReplicas(ItemRange(i))) <
        Required(level, activeReplicas[ItemRange(i)])
    /\ lastRead' =
        [ kind        |-> "Unavailable",
          principal   |-> p,
          coordinator |-> coordinator,
          item        |-> i,
          level       |-> level,
          routing     |-> activeReplicas[ItemRange(i)],
          responders  |-> {},
          result      |-> {},
          frontier    |-> {},
          authorized  |-> TRUE,
          executed    |-> FALSE ]
    /\ UNCHANGED << permissionStore,
                   authView,
                   nodeAvailable,
                   writeFrontier,
                   writeTargets,
                   writeLevel,
                   writeCoordinator,
                   writeAuthor,
                   writeSucceeded,
                   acked,
                   commitLog,
                   replicaApplied,
                   hintStore,
                   activeReplicas,
                   plannedReplicas,
                   migrateState,
                   migrateEpoch,
                   migrateBoundary,
                   lastWrite,
                   lastMigrate,
                   lastAuth >>

Next ==
    \/ \E admin \in Principals :
        \E coordinator \in Nodes :
            \E targetRole \in Roles :
                \E resource \in Resources :
                    \E permission \in PermissionKinds :
                        GrantPermission(admin, coordinator, targetRole,
                                        resource, permission)
    \/ \E admin \in Principals :
        \E coordinator \in Nodes :
            \E targetRole \in Roles :
                \E resource \in Resources :
                    \E permission \in PermissionKinds :
                        RevokePermission(admin, coordinator, targetRole,
                                         resource, permission)
    \/ \E admin \in Principals :
        \E coordinator \in Nodes :
            \E targetRole \in Roles :
                \E resource \in Resources :
                    \E permission \in PermissionKinds :
                        RejectGrantOrRevoke(admin, coordinator, targetRole,
                                            resource, permission)
    \/ \E n \in Nodes : RefreshAuthCache(n)
    \/ \E n \in Nodes :
        \E available \in BOOLEAN : SetNodeAvailability(n, available)

    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E m \in Mutations :
                \E level \in WriteLevels :
                    ReceiveWrite(p, coordinator, m, level)
    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E m \in Mutations :
                \E level \in WriteLevels :
                    RejectWrite(p, coordinator, m, level)
    \/ \E m \in Mutations :
        \E n \in Nodes : LogReplica(m, n)
    \/ \E m \in Mutations :
        \E n \in Nodes : ApplyReplica(m, n)
    \/ \E m \in Mutations :
        \E n \in Nodes : ReplicaAck(m, n)
    \/ \E m \in Mutations : CompleteWrite(m)
    \/ \E m \in Mutations :
        \E holder \in Nodes :
            \E target \in Nodes : StoreHint(m, holder, target)
    \/ \E holder \in Nodes :
        \E m \in Mutations :
            \E target \in Nodes : ReplayHint(holder, m, target)
    \/ \E m \in Mutations :
        \E target \in Nodes :
            \E method \in SyncMethods : SyncReplica(m, target, method)

    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E r \in TokenRanges :
                \E planned \in SUBSET Nodes :
                    \E mode \in MigrateModes :
                        StartMigrate(p, coordinator, r, planned, mode)
    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E r \in TokenRanges :
                \E planned \in SUBSET Nodes :
                    \E mode \in MigrateModes :
                        RejectTopologyChange(p, coordinator, r, planned, mode)
    \/ \E r \in TokenRanges :
        \E source \in Nodes :
            \E target \in Nodes :
                \E m \in Mutations :
                    AdvanceMigrate(r, source, target, m)
    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E r \in TokenRanges :
                ActivateMigrate(p, coordinator, r)
    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E r \in TokenRanges :
                CleanupMigrate(p, coordinator, r)

    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E i \in Items :
                \E level \in ReadLevels :
                    \E responders \in SUBSET Nodes :
                        ExecuteRead(p, coordinator, i, level, responders)
    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E i \in Items :
                \E level \in ReadLevels :
                    RejectRead(p, coordinator, i, level)
    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E i \in Items :
                \E level \in ReadLevels :
                    UnavailableRead(p, coordinator, i, level)

Spec ==
    Init /\ [][Next]_GlobalVars

GlobalTypeInvariant ==
    /\ StaticAssumptions
    /\ permissionStore \in [Roles -> [Resources -> SUBSET PermissionKinds]]
    /\ authView \in [Nodes -> [Roles -> [Resources -> SUBSET PermissionKinds]]]
    /\ nodeAvailable \in [Nodes -> BOOLEAN]

    /\ writeFrontier \subseteq Mutations
    /\ writeTargets \in [Mutations -> SUBSET Nodes]
    /\ writeLevel \in [Mutations -> WriteLevels]
    /\ writeCoordinator \in [Mutations -> Nodes]
    /\ writeAuthor \in [Mutations -> Principals]
    /\ writeSucceeded \in [Mutations -> BOOLEAN]
    /\ acked \in [Mutations -> SUBSET Nodes]

    /\ commitLog \in [Nodes -> SUBSET Mutations]
    /\ replicaApplied \in [Nodes -> SUBSET Mutations]
    /\ hintStore \in [Nodes -> SUBSET Mutations]

    /\ activeReplicas \in [TokenRanges -> SUBSET Nodes]
    /\ plannedReplicas \in [TokenRanges -> SUBSET Nodes]
    /\ migrateState \in [TokenRanges -> MigrateStates]
    /\ migrateEpoch \in [TokenRanges -> Nat]
    /\ migrateBoundary \in [TokenRanges -> SUBSET Mutations]
    /\ \A r \in TokenRanges :
        /\ ValidReplicaSet(rangeKeyspace[r], activeReplicas[r])
        /\ ValidReplicaSet(rangeKeyspace[r], plannedReplicas[r])

    /\ lastWrite \in WriteRecordT
    /\ lastRead \in ReadRecordT
    /\ lastMigrate \in MigrateRecordT
    /\ lastAuth \in AuthRecordT

AuthSafety ==
    /\ lastWrite.kind \in {"None", "Rejected"}
       \/ lastWrite.authorized
    /\ lastRead.kind \in {"None", "Rejected"}
       \/ lastRead.authorized
    /\ lastMigrate.kind \in {"None", "Rejected"}
       \/ lastMigrate.authorized
    /\ lastAuth.kind \in {"None", "Rejected"}
       \/ lastAuth.authorized
    /\ lastRead.kind = "Rejected" =>
        /\ lastRead.result = {}
        /\ lastRead.frontier = {}
        /\ ~lastRead.executed
    /\ lastWrite.kind = "Rejected" => ~lastWrite.completed

MemtableAfterCommitLog ==
    \A n \in Nodes :
        replicaApplied[n] \subseteq commitLog[n]

ReplicaNotAheadOfWrite ==
    \A n \in Nodes :
        replicaApplied[n] \subseteq writeFrontier

WriteSafety ==
    /\ MemtableAfterCommitLog
    /\ ReplicaNotAheadOfWrite
    /\ \A m \in Mutations :
        /\ acked[m] \subseteq writeTargets[m]
        /\ \A n \in acked[m] : m \in replicaApplied[n]
    /\ \A m \in Mutations :
        writeSucceeded[m] =>
            /\ m \in writeFrontier
            /\ Cardinality(acked[m]) >=
                Required(writeLevel[m], writeTargets[m])

ReadSafety ==
    /\ lastRead.kind = "Success" =>
        /\ lastRead.authorized
        /\ lastRead.executed
        /\ ReadResponsesOK(lastRead.level,
                           lastRead.routing,
                           lastRead.responders)
        /\ lastRead.result = lastRead.frontier
    /\ lastRead.kind = "Unavailable" =>
        /\ lastRead.authorized
        /\ ~lastRead.executed
        /\ lastRead.result = {}
    /\ lastRead.kind = "Rejected" =>
        /\ ~lastRead.authorized
        /\ lastRead.result = {}

MigrateSafety ==
    /\ \A r \in TokenRanges :
        /\ MigrateFrontier(r) \subseteq writeFrontier
        /\ migrateState[r] = "Streaming" =>
            activeReplicas[r] # plannedReplicas[r]
        /\ migrateState[r] \in {"Activated", "Stable"} =>
            CoveredBy(activeReplicas[r], migrateBoundary[r])
    /\ \A r \in TokenRanges :
        migrateState[r] = "Activated" =>
            migrateBoundary[r] \subseteq MigrateFrontier(r)
    /\ lastMigrate.kind = "Rejected" =>
        ~lastMigrate.authorized

FrontierSafety ==
    /\ \A n \in Nodes :
        replicaApplied[n] \subseteq writeFrontier
    /\ \A m \in Mutations :
        writeSucceeded[m] => m \in writeFrontier
    /\ \A r \in TokenRanges :
        MigrateFrontier(r) \subseteq writeFrontier
    /\ \A r \in TokenRanges :
        CoveredBy(activeReplicas[r], migrateBoundary[r])
    /\ lastRead.kind = "Success" =>
        lastRead.result = lastRead.frontier

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ AuthSafety
    /\ WriteSafety
    /\ ReadSafety
    /\ MigrateSafety
    /\ FrontierSafety

=============================================================================
