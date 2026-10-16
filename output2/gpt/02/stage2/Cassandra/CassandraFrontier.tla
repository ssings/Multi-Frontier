------------------------- MODULE CassandraFrontier -------------------------

EXTENDS Naturals, FiniteSets

CONSTANTS
    Principals,
    Roles,
    Nodes,
    Keyspaces,
    Tables,
    Partitions,
    TokenRanges,
    DataItems,
    Mutations,
    ReadRequests,

    principalRole,
    roleMembers,
    roleReach,
    superusers,

    tableKeyspace,
    itemTable,
    itemPartition,
    partitionRange,
    rangeKeyspace,

    mutationItem,
    mutationVersion,
    mutationRank,
    mutationKind,

    replicationFactor,
    InitialRouting,
    InitialPermissions,

    readPrincipal,
    readCoordinator,
    readItem,
    readLevel,

    authorizationEnabled

AllKeyspaces == "ALL_KEYSPACES"
NoMutation == "NO_MUTATION"

PermissionT ==
    {"SELECT", "MODIFY", "AUTHORIZE", "MANAGE_TOPOLOGY"}

WriteStates ==
    {"None", "Accepted", "Dispatched", "Acknowledged", "Rejected"}

ReadStates ==
    {"None", "Dispatched", "Completed", "Rejected"}

ConsistencyLevels ==
    {"ONE", "QUORUM", "ALL"}

MigrateStates ==
    {"Stable", "Streaming", "Activated"}

MigrateKinds ==
    {"Bootstrap", "Decommission", "Move", "Replace"}

Resources ==
    Tables \cup Keyspaces \cup {AllKeyspaces}

MutationOrNone ==
    Mutations \cup {NoMutation}

AnyPrincipal ==
    CHOOSE p \in Principals : TRUE

AnyRole ==
    CHOOSE r \in Roles : TRUE

AnyNode ==
    CHOOSE n \in Nodes : TRUE

AnyRange ==
    CHOOSE ra \in TokenRanges : TRUE

AnyTable ==
    CHOOSE t \in Tables : TRUE

AnyMutation ==
    CHOOSE m \in Mutations : TRUE

AnyRead ==
    CHOOSE rd \in ReadRequests : TRUE

AnyResource ==
    CHOOSE x \in Resources : TRUE

MutationRange(m) ==
    partitionRange[itemPartition[mutationItem[m]]]

MutationTable(m) ==
    itemTable[mutationItem[m]]

MutationKeyspace(m) ==
    tableKeyspace[MutationTable(m)]

RequiredResponses(level, n) ==
    CASE level = "ONE" -> 1
      [] level = "QUORUM" -> (n + 1) \div 2
      [] level = "ALL" -> n

Later(m1, m2) ==
    \/ mutationVersion[m1] > mutationVersion[m2]
    \/ /\ mutationVersion[m1] = mutationVersion[m2]
       /\ mutationRank[m1] > mutationRank[m2]

LWW(s) ==
    IF s = {}
    THEN NoMutation
    ELSE CHOOSE m \in s :
        \A x \in s : ~Later(x, m)

LogicalResult(m) ==
    IF m = NoMutation \/ mutationKind[m] = "Tombstone"
    THEN NoMutation
    ELSE m

ValidPermission(resource, perm) ==
    /\ resource \in Resources
    /\ perm \in PermissionT
    /\ \/ perm \in {"SELECT", "MODIFY", "AUTHORIZE"}
       \/ /\ perm = "MANAGE_TOPOLOGY"
          /\ resource \in Keyspaces \cup {AllKeyspaces}

RolesOfPrincipal(p) ==
    roleReach[principalRole[p]]

IsSuperuser(p) ==
    \E r \in RolesOfPrincipal(p) : r \in superusers

DirectPermissions(p, resource) ==
    UNION {permissions[r][resource] : r \in RolesOfPrincipal(p)}

HasResourcePermission(p, resource, perm) ==
    \/ ~authorizationEnabled
    \/ IsSuperuser(p)
    \/ perm \in DirectPermissions(p, resource)

CanTable(p, table, perm) ==
    \/ ~authorizationEnabled
    \/ IsSuperuser(p)
    \/ perm \in DirectPermissions(p, table)
    \/ perm \in DirectPermissions(p, tableKeyspace[table])
    \/ perm \in DirectPermissions(p, AllKeyspaces)

CanAuthorize(p, resource) ==
    IF resource \in Tables
    THEN CanTable(p, resource, "AUTHORIZE")
    ELSE
        \/ ~authorizationEnabled
        \/ IsSuperuser(p)
        \/ "AUTHORIZE" \in DirectPermissions(p, resource)
        \/ "AUTHORIZE" \in DirectPermissions(p, AllKeyspaces)

CanTopology(p, ra) ==
    \/ ~authorizationEnabled
    \/ IsSuperuser(p)
    \/ "MANAGE_TOPOLOGY" \in DirectPermissions(p, rangeKeyspace[ra])
    \/ "MANAGE_TOPOLOGY" \in DirectPermissions(p, AllKeyspaces)

LocalMutations(node, item) ==
    {m \in replicaApplied[node] : mutationItem[m] = item}

LocalWinner(node, item) ==
    LWW(LocalMutations(node, item))

ResponseMutations(rd) ==
    {responseValue[rd][n] :
        n \in readResponses[rd] /\ responseValue[rd][n] # NoMutation}

ResolvedReadWinner(rd) ==
    LWW(ResponseMutations(rd))

MigrationSafeForRead(rd) ==
    /\ readRouteSafe[rd]
    /\ readTargets[rd] # {}

WriteFrontier ==
    accepted

LocalLogFrontier(node) ==
    commitLog[node]

ReplicaFrontier(node) ==
    replicaApplied[node]

CommitFrontier(level) ==
    {m \in accepted :
        /\ writeState[m] = "Acknowledged"
        /\ writeLevel[m] = level}

QueryFrontier(rd) ==
    ResolvedReadWinner(rd)

MigrateFrontier(ra) ==
    {m \in WriteFrontier : MutationRange(m) = ra}

FinalQueryFrontier(rd) ==
    IF /\ readAuthorized[rd]
       /\ MigrationSafeForRead(rd)
       /\ Cardinality(readResponses[rd]) >=
          RequiredResponses(readLevel[rd], Cardinality(readTargets[rd]))
    THEN QueryFrontier(rd)
    ELSE NoMutation

LastWriteT ==
    [principal : Principals,
     mutation : Mutations,
     authorized : BOOLEAN,
     executed : BOOLEAN]

LastReadT ==
    [principal : Principals,
     request : ReadRequests,
     authorized : BOOLEAN,
     executed : BOOLEAN]

LastMigrateT ==
    [principal : Principals,
     range : TokenRanges,
     phase : {"None", "Start", "Advance", "Activate", "Finish", "Reject"},
     authorized : BOOLEAN,
     executed : BOOLEAN]

LastAuthChangeT ==
    [admin : Principals,
     target : Roles,
     resource : Resources,
     permission : PermissionT,
     authorized : BOOLEAN,
     executed : BOOLEAN]

VARIABLES
    permissions,

    writeState,
    writePrincipal,
    writeCoordinatorState,
    writeLevel,
    writeTargets,
    accepted,
    writeAuthorized,

    commitLog,
    memtable,
    sstable,
    replicaApplied,
    ackSet,

    readState,
    readTargets,
    readResponses,
    responseValue,
    readWinner,
    readResult,
    readAuthorized,
    readRouteSafe,

    migrateStage,
    migrateKind,
    oldRouting,
    targetRouting,
    routing,
    activationFrontier,
    migratePrincipal,
    migrateAuthorized,
    topologyEpoch,

    lastWrite,
    lastRead,
    lastMigrate,
    lastAuthChange

AuthVars ==
    <<permissions, lastAuthChange>>

StorageVars ==
    <<commitLog, memtable, sstable, replicaApplied>>

WriteVars ==
    <<writeState, writePrincipal, writeCoordinatorState, writeLevel,
      writeTargets, accepted, writeAuthorized, StorageVars, ackSet,
      lastWrite>>

ReadVars ==
    <<readState, readTargets, readResponses, responseValue,
      readWinner, readResult, readAuthorized, readRouteSafe, lastRead>>

MigrateVars ==
    <<migrateStage, migrateKind, oldRouting, targetRouting, routing,
      activationFrontier, migratePrincipal, migrateAuthorized,
      topologyEpoch, lastMigrate>>

GlobalVars ==
    <<AuthVars, WriteVars, ReadVars, MigrateVars>>

CoreOK ==
    /\ Principals # {}
    /\ Roles # {}
    /\ Nodes # {}
    /\ Keyspaces # {}
    /\ Tables # {}
    /\ Partitions # {}
    /\ TokenRanges # {}
    /\ DataItems # {}
    /\ Mutations # {}
    /\ ReadRequests # {}

    /\ authorizationEnabled \in BOOLEAN

    /\ principalRole \in [Principals -> Roles]
    /\ roleMembers \in [Roles -> SUBSET Roles]
    /\ roleReach \in [Roles -> SUBSET Roles]
    /\ superusers \subseteq Roles

    /\ \A r \in Roles : r \in roleReach[r]
    /\ \A r \in Roles :
        roleMembers[r] \subseteq roleReach[r]
    /\ \A r \in Roles :
        \A inherited \in roleReach[r] :
            roleReach[inherited] \subseteq roleReach[r]
    /\ \A r1 \in Roles :
        \A r2 \in Roles :
            /\ r1 # r2
            => ~(r1 \in roleReach[r2] /\ r2 \in roleReach[r1])

    /\ tableKeyspace \in [Tables -> Keyspaces]
    /\ itemTable \in [DataItems -> Tables]
    /\ itemPartition \in [DataItems -> Partitions]
    /\ partitionRange \in [Partitions -> TokenRanges]
    /\ rangeKeyspace \in [TokenRanges -> Keyspaces]

    /\ mutationItem \in [Mutations -> DataItems]
    /\ mutationVersion \in [Mutations -> Nat]
    /\ mutationRank \in [Mutations -> Nat]
    /\ mutationKind \in [Mutations -> {"Value", "Tombstone"}]

    /\ \A m1 \in Mutations :
        \A m2 \in Mutations :
            mutationRank[m1] = mutationRank[m2] => m1 = m2

    /\ \A m \in Mutations :
        MutationKeyspace(m) = rangeKeyspace[MutationRange(m)]

    /\ replicationFactor \in [Keyspaces -> Nat]
    /\ \A ks \in Keyspaces : replicationFactor[ks] > 0

    /\ InitialRouting \in [TokenRanges -> SUBSET Nodes]
    /\ \A ra \in TokenRanges :
        Cardinality(InitialRouting[ra]) =
            replicationFactor[rangeKeyspace[ra]]

    /\ InitialPermissions \in [Roles -> [Resources -> SUBSET PermissionT]]
    /\ \A r \in Roles :
        \A resource \in Resources :
            \A perm \in InitialPermissions[r][resource] :
                ValidPermission(resource, perm)

    /\ readPrincipal \in [ReadRequests -> Principals]
    /\ readCoordinator \in [ReadRequests -> Nodes]
    /\ readItem \in [ReadRequests -> DataItems]
    /\ readLevel \in [ReadRequests -> ConsistencyLevels]

Init ==
    /\ CoreOK

    /\ permissions = InitialPermissions

    /\ writeState = [m \in Mutations |-> "None"]
    /\ writePrincipal = [m \in Mutations |-> AnyPrincipal]
    /\ writeCoordinatorState = [m \in Mutations |-> AnyNode]
    /\ writeLevel = [m \in Mutations |-> "ONE"]
    /\ writeTargets = [m \in Mutations |-> {}]
    /\ accepted = {}
    /\ writeAuthorized = [m \in Mutations |-> FALSE]

    /\ commitLog = [n \in Nodes |-> {}]
    /\ memtable = [n \in Nodes |-> {}]
    /\ sstable = [n \in Nodes |-> {}]
    /\ replicaApplied = [n \in Nodes |-> {}]
    /\ ackSet = [m \in Mutations |-> {}]

    /\ readState = [rd \in ReadRequests |-> "None"]
    /\ readTargets = [rd \in ReadRequests |-> {}]
    /\ readResponses = [rd \in ReadRequests |-> {}]
    /\ responseValue =
        [rd \in ReadRequests |-> [n \in Nodes |-> NoMutation]]
    /\ readWinner = [rd \in ReadRequests |-> NoMutation]
    /\ readResult = [rd \in ReadRequests |-> NoMutation]
    /\ readAuthorized = [rd \in ReadRequests |-> FALSE]
    /\ readRouteSafe = [rd \in ReadRequests |-> FALSE]

    /\ migrateStage = [ra \in TokenRanges |-> "Stable"]
    /\ migrateKind = [ra \in TokenRanges |-> "Bootstrap"]
    /\ oldRouting = InitialRouting
    /\ targetRouting = InitialRouting
    /\ routing = InitialRouting
    /\ activationFrontier = [ra \in TokenRanges |-> {}]
    /\ migratePrincipal = [ra \in TokenRanges |-> AnyPrincipal]
    /\ migrateAuthorized = [ra \in TokenRanges |-> FALSE]
    /\ topologyEpoch = 0

    /\ lastWrite =
        [principal |-> AnyPrincipal,
         mutation |-> AnyMutation,
         authorized |-> FALSE,
         executed |-> FALSE]

    /\ lastRead =
        [principal |-> AnyPrincipal,
         request |-> AnyRead,
         authorized |-> FALSE,
         executed |-> FALSE]

    /\ lastMigrate =
        [principal |-> AnyPrincipal,
         range |-> AnyRange,
         phase |-> "None",
         authorized |-> FALSE,
         executed |-> FALSE]

    /\ lastAuthChange =
        [admin |-> AnyPrincipal,
         target |-> AnyRole,
         resource |-> AnyResource,
         permission |-> "SELECT",
         authorized |-> FALSE,
         executed |-> FALSE]

GrantPermission(admin, target, resource, perm) ==
    /\ admin \in Principals
    /\ target \in Roles
    /\ resource \in Resources
    /\ perm \in PermissionT
    /\ ValidPermission(resource, perm)
    /\ CanAuthorize(admin, resource)
    /\ perm \notin permissions[target][resource]

    /\ permissions' =
        [permissions EXCEPT ![target][resource] = @ \cup {perm}]

    /\ lastAuthChange' =
        [admin |-> admin,
         target |-> target,
         resource |-> resource,
         permission |-> perm,
         authorized |-> TRUE,
         executed |-> TRUE]

    /\ UNCHANGED WriteVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

RevokePermission(admin, target, resource, perm) ==
    /\ admin \in Principals
    /\ target \in Roles
    /\ resource \in Resources
    /\ perm \in PermissionT
    /\ ValidPermission(resource, perm)
    /\ CanAuthorize(admin, resource)
    /\ perm \in permissions[target][resource]

    /\ permissions' =
        [permissions EXCEPT ![target][resource] = @ \ {perm}]

    /\ lastAuthChange' =
        [admin |-> admin,
         target |-> target,
         resource |-> resource,
         permission |-> perm,
         authorized |-> TRUE,
         executed |-> TRUE]

    /\ UNCHANGED WriteVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

RejectGrantOrRevoke(admin, target, resource, perm) ==
    /\ admin \in Principals
    /\ target \in Roles
    /\ resource \in Resources
    /\ perm \in PermissionT
    /\ \/ ~ValidPermission(resource, perm)
       \/ ~CanAuthorize(admin, resource)

    /\ lastAuthChange' =
        [admin |-> admin,
         target |-> target,
         resource |-> resource,
         permission |-> perm,
         authorized |-> FALSE,
         executed |-> FALSE]

    /\ UNCHANGED permissions
    /\ UNCHANGED WriteVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

ReceiveWrite(p, coordinator, m, level) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ m \in Mutations
    /\ level \in ConsistencyLevels
    /\ writeState[m] = "None"
    /\ CanTable(p, MutationTable(m), "MODIFY")
    /\ routing[MutationRange(m)] # {}

    /\ writeState' = [writeState EXCEPT ![m] = "Accepted"]
    /\ writePrincipal' = [writePrincipal EXCEPT ![m] = p]
    /\ writeCoordinatorState' =
        [writeCoordinatorState EXCEPT ![m] = coordinator]
    /\ writeLevel' = [writeLevel EXCEPT ![m] = level]
    /\ accepted' = accepted \cup {m}
    /\ writeAuthorized' = [writeAuthorized EXCEPT ![m] = TRUE]

    /\ lastWrite' =
        [principal |-> p,
         mutation |-> m,
         authorized |-> TRUE,
         executed |-> TRUE]

    /\ UNCHANGED writeTargets
    /\ UNCHANGED StorageVars
    /\ UNCHANGED ackSet
    /\ UNCHANGED AuthVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

RejectWrite(p, coordinator, m, level) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ m \in Mutations
    /\ level \in ConsistencyLevels
    /\ writeState[m] = "None"
    /\ ~CanTable(p, MutationTable(m), "MODIFY")

    /\ writeState' = [writeState EXCEPT ![m] = "Rejected"]

    /\ lastWrite' =
        [principal |-> p,
         mutation |-> m,
         authorized |-> FALSE,
         executed |-> FALSE]

    /\ UNCHANGED writePrincipal
    /\ UNCHANGED writeCoordinatorState
    /\ UNCHANGED writeLevel
    /\ UNCHANGED writeTargets
    /\ UNCHANGED accepted
    /\ UNCHANGED writeAuthorized
    /\ UNCHANGED StorageVars
    /\ UNCHANGED ackSet
    /\ UNCHANGED AuthVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

DispatchWrite(m) ==
    /\ m \in Mutations
    /\ writeState[m] = "Accepted"
    /\ writeTargets[m] = {}
    /\ routing[MutationRange(m)] # {}

    /\ writeState' = [writeState EXCEPT ![m] = "Dispatched"]
    /\ writeTargets' =
        [writeTargets EXCEPT ![m] = routing[MutationRange(m)]]

    /\ UNCHANGED writePrincipal
    /\ UNCHANGED writeCoordinatorState
    /\ UNCHANGED writeLevel
    /\ UNCHANGED accepted
    /\ UNCHANGED writeAuthorized
    /\ UNCHANGED StorageVars
    /\ UNCHANGED ackSet
    /\ UNCHANGED lastWrite
    /\ UNCHANGED AuthVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

ReplicaReceiveWrite(m, node) ==
    /\ m \in Mutations
    /\ node \in Nodes
    /\ m \in accepted
    /\ writeState[m] = "Dispatched"
    /\ node \in writeTargets[m]
    /\ m \notin replicaApplied[node]

    /\ commitLog' = [commitLog EXCEPT ![node] = @ \cup {m}]
    /\ memtable' = [memtable EXCEPT ![node] = @ \cup {m}]
    /\ sstable' = sstable
    /\ replicaApplied' =
        [replicaApplied EXCEPT ![node] = @ \cup {m}]

    /\ UNCHANGED writeState
    /\ UNCHANGED writePrincipal
    /\ UNCHANGED writeCoordinatorState
    /\ UNCHANGED writeLevel
    /\ UNCHANGED writeTargets
    /\ UNCHANGED accepted
    /\ UNCHANGED writeAuthorized
    /\ UNCHANGED ackSet
    /\ UNCHANGED lastWrite
    /\ UNCHANGED AuthVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

ReplicaAck(m, node) ==
    /\ m \in Mutations
    /\ node \in Nodes
    /\ writeState[m] = "Dispatched"
    /\ node \in writeTargets[m]
    /\ m \in replicaApplied[node]
    /\ node \notin ackSet[m]

    /\ ackSet' = [ackSet EXCEPT ![m] = @ \cup {node}]

    /\ UNCHANGED writeState
    /\ UNCHANGED writePrincipal
    /\ UNCHANGED writeCoordinatorState
    /\ UNCHANGED writeLevel
    /\ UNCHANGED writeTargets
    /\ UNCHANGED accepted
    /\ UNCHANGED writeAuthorized
    /\ UNCHANGED StorageVars
    /\ UNCHANGED lastWrite
    /\ UNCHANGED AuthVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

CompleteWrite(m) ==
    /\ m \in Mutations
    /\ writeState[m] = "Dispatched"
    /\ Cardinality(ackSet[m]) >=
        RequiredResponses(writeLevel[m], Cardinality(writeTargets[m]))

    /\ writeState' = [writeState EXCEPT ![m] = "Acknowledged"]

    /\ lastWrite' =
        [principal |-> writePrincipal[m],
         mutation |-> m,
         authorized |-> writeAuthorized[m],
         executed |-> TRUE]

    /\ UNCHANGED writePrincipal
    /\ UNCHANGED writeCoordinatorState
    /\ UNCHANGED writeLevel
    /\ UNCHANGED writeTargets
    /\ UNCHANGED accepted
    /\ UNCHANGED writeAuthorized
    /\ UNCHANGED StorageVars
    /\ UNCHANGED ackSet
    /\ UNCHANGED AuthVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

SyncReplica(m, source, target) ==
    /\ m \in Mutations
    /\ source \in Nodes
    /\ target \in Nodes
    /\ m \in accepted
    /\ m \in replicaApplied[source]
    /\ m \notin replicaApplied[target]
    /\ \/ target \in routing[MutationRange(m)]
       \/ /\ migrateStage[MutationRange(m)] = "Streaming"
          /\ target \in targetRouting[MutationRange(m)]

    /\ commitLog' = [commitLog EXCEPT ![target] = @ \cup {m}]
    /\ memtable' = [memtable EXCEPT ![target] = @ \cup {m}]
    /\ sstable' = sstable
    /\ replicaApplied' =
        [replicaApplied EXCEPT ![target] = @ \cup {m}]

    /\ UNCHANGED writeState
    /\ UNCHANGED writePrincipal
    /\ UNCHANGED writeCoordinatorState
    /\ UNCHANGED writeLevel
    /\ UNCHANGED writeTargets
    /\ UNCHANGED accepted
    /\ UNCHANGED writeAuthorized
    /\ UNCHANGED ackSet
    /\ UNCHANGED lastWrite
    /\ UNCHANGED AuthVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

FlushMemtable(node) ==
    /\ node \in Nodes
    /\ memtable[node] # {}

    /\ commitLog' = commitLog
    /\ memtable' = [memtable EXCEPT ![node] = {}]
    /\ sstable' = [sstable EXCEPT ![node] = @ \cup memtable[node]]
    /\ replicaApplied' = replicaApplied

    /\ UNCHANGED writeState
    /\ UNCHANGED writePrincipal
    /\ UNCHANGED writeCoordinatorState
    /\ UNCHANGED writeLevel
    /\ UNCHANGED writeTargets
    /\ UNCHANGED accepted
    /\ UNCHANGED writeAuthorized
    /\ UNCHANGED ackSet
    /\ UNCHANGED lastWrite
    /\ UNCHANGED AuthVars
    /\ UNCHANGED ReadVars
    /\ UNCHANGED MigrateVars

DispatchRead(rd) ==
    /\ rd \in ReadRequests
    /\ readState[rd] = "None"
    /\ CanTable(readPrincipal[rd], itemTable[readItem[rd]], "SELECT")
    /\ routing[partitionRange[itemPartition[readItem[rd]]]] # {}

    /\ readState' = [readState EXCEPT ![rd] = "Dispatched"]
    /\ readTargets' =
        [readTargets EXCEPT
            ![rd] = routing[partitionRange[itemPartition[readItem[rd]]]]]
    /\ readAuthorized' = [readAuthorized EXCEPT ![rd] = TRUE]
    /\ readRouteSafe' = [readRouteSafe EXCEPT ![rd] = TRUE]

    /\ UNCHANGED readResponses
    /\ UNCHANGED responseValue
    /\ UNCHANGED readWinner
    /\ UNCHANGED readResult
    /\ UNCHANGED lastRead
    /\ UNCHANGED AuthVars
    /\ UNCHANGED WriteVars
    /\ UNCHANGED MigrateVars

ReplicaReadResponse(rd, node) ==
    /\ rd \in ReadRequests
    /\ node \in Nodes
    /\ readState[rd] = "Dispatched"
    /\ node \in readTargets[rd]
    /\ node \notin readResponses[rd]

    /\ readResponses' =
        [readResponses EXCEPT ![rd] = @ \cup {node}]
    /\ responseValue' =
        [responseValue EXCEPT ![rd][node] = LocalWinner(node, readItem[rd])]

    /\ UNCHANGED readState
    /\ UNCHANGED readTargets
    /\ UNCHANGED readWinner
    /\ UNCHANGED readResult
    /\ UNCHANGED readAuthorized
    /\ UNCHANGED readRouteSafe
    /\ UNCHANGED lastRead
    /\ UNCHANGED AuthVars
    /\ UNCHANGED WriteVars
    /\ UNCHANGED MigrateVars

CompleteRead(rd) ==
    /\ rd \in ReadRequests
    /\ readState[rd] = "Dispatched"
    /\ readAuthorized[rd]
    /\ Cardinality(readResponses[rd]) >=
        RequiredResponses(readLevel[rd], Cardinality(readTargets[rd]))

    /\ readState' = [readState EXCEPT ![rd] = "Completed"]
    /\ readWinner' =
        [readWinner EXCEPT ![rd] = ResolvedReadWinner(rd)]
    /\ readResult' =
        [readResult EXCEPT ![rd] = LogicalResult(ResolvedReadWinner(rd))]

    /\ lastRead' =
        [principal |-> readPrincipal[rd],
         request |-> rd,
         authorized |-> TRUE,
         executed |-> TRUE]

    /\ UNCHANGED readTargets
    /\ UNCHANGED readResponses
    /\ UNCHANGED responseValue
    /\ UNCHANGED readAuthorized
    /\ UNCHANGED readRouteSafe
    /\ UNCHANGED AuthVars
    /\ UNCHANGED WriteVars
    /\ UNCHANGED MigrateVars

RejectRead(rd) ==
    /\ rd \in ReadRequests
    /\ readState[rd] = "None"
    /\ ~CanTable(readPrincipal[rd], itemTable[readItem[rd]], "SELECT")

    /\ readState' = [readState EXCEPT ![rd] = "Rejected"]
    /\ readWinner' = [readWinner EXCEPT ![rd] = NoMutation]
    /\ readResult' = [readResult EXCEPT ![rd] = NoMutation]

    /\ lastRead' =
        [principal |-> readPrincipal[rd],
         request |-> rd,
         authorized |-> FALSE,
         executed |-> FALSE]

    /\ UNCHANGED readTargets
    /\ UNCHANGED readResponses
    /\ UNCHANGED responseValue
    /\ UNCHANGED readAuthorized
    /\ UNCHANGED readRouteSafe
    /\ UNCHANGED AuthVars
    /\ UNCHANGED WriteVars
    /\ UNCHANGED MigrateVars

StartMigrate(p, ra, kind, target) ==
    /\ p \in Principals
    /\ ra \in TokenRanges
    /\ kind \in MigrateKinds
    /\ target \in SUBSET Nodes
    /\ migrateStage[ra] = "Stable"
    /\ CanTopology(p, ra)
    /\ target # {}
    /\ target # routing[ra]
    /\ Cardinality(target) = replicationFactor[rangeKeyspace[ra]]

    /\ migrateStage' = [migrateStage EXCEPT ![ra] = "Streaming"]
    /\ migrateKind' = [migrateKind EXCEPT ![ra] = kind]
    /\ oldRouting' = [oldRouting EXCEPT ![ra] = routing[ra]]
    /\ targetRouting' = [targetRouting EXCEPT ![ra] = target]
    /\ activationFrontier' = [activationFrontier EXCEPT ![ra] = {}]
    /\ migratePrincipal' = [migratePrincipal EXCEPT ![ra] = p]
    /\ migrateAuthorized' = [migrateAuthorized EXCEPT ![ra] = TRUE]

    /\ lastMigrate' =
        [principal |-> p,
         range |-> ra,
         phase |-> "Start",
         authorized |-> TRUE,
         executed |-> TRUE]

    /\ UNCHANGED routing
    /\ UNCHANGED topologyEpoch
    /\ UNCHANGED AuthVars
    /\ UNCHANGED WriteVars
    /\ UNCHANGED ReadVars

RejectMigrate(p, ra, kind, target) ==
    /\ p \in Principals
    /\ ra \in TokenRanges
    /\ kind \in MigrateKinds
    /\ target \in SUBSET Nodes
    /\ ~CanTopology(p, ra)

    /\ lastMigrate' =
        [principal |-> p,
         range |-> ra,
         phase |-> "Reject",
         authorized |-> FALSE,
         executed |-> FALSE]

    /\ UNCHANGED migrateStage
    /\ UNCHANGED migrateKind
    /\ UNCHANGED oldRouting
    /\ UNCHANGED targetRouting
    /\ UNCHANGED routing
    /\ UNCHANGED activationFrontier
    /\ UNCHANGED migratePrincipal
    /\ UNCHANGED migrateAuthorized
    /\ UNCHANGED topologyEpoch
    /\ UNCHANGED AuthVars
    /\ UNCHANGED WriteVars
    /\ UNCHANGED ReadVars

AdvanceMigrate(ra, source, target, m) ==
    /\ ra \in TokenRanges
    /\ source \in Nodes
    /\ target \in Nodes
    /\ m \in Mutations
    /\ migrateStage[ra] = "Streaming"
    /\ m \in MigrateFrontier(ra)
    /\ source \in oldRouting[ra] \cup targetRouting[ra]
    /\ m \in replicaApplied[source]
    /\ target \in targetRouting[ra]
    /\ m \notin replicaApplied[target]

    /\ commitLog' = [commitLog EXCEPT ![target] = @ \cup {m}]
    /\ memtable' = [memtable EXCEPT ![target] = @ \cup {m}]
    /\ sstable' = sstable
    /\ replicaApplied' =
        [replicaApplied EXCEPT ![target] = @ \cup {m}]

    /\ lastMigrate' =
        [principal |-> migratePrincipal[ra],
         range |-> ra,
         phase |-> "Advance",
         authorized |-> migrateAuthorized[ra],
         executed |-> TRUE]

    /\ UNCHANGED AuthVars
    /\ UNCHANGED writeState
    /\ UNCHANGED writePrincipal
    /\ UNCHANGED writeCoordinatorState
    /\ UNCHANGED writeLevel
    /\ UNCHANGED writeTargets
    /\ UNCHANGED accepted
    /\ UNCHANGED writeAuthorized
    /\ UNCHANGED ackSet
    /\ UNCHANGED lastWrite
    /\ UNCHANGED ReadVars
    /\ UNCHANGED migrateStage
    /\ UNCHANGED migrateKind
    /\ UNCHANGED oldRouting
    /\ UNCHANGED targetRouting
    /\ UNCHANGED routing
    /\ UNCHANGED activationFrontier
    /\ UNCHANGED migratePrincipal
    /\ UNCHANGED migrateAuthorized
    /\ UNCHANGED topologyEpoch

ActivateMigrate(ra) ==
    /\ ra \in TokenRanges
    /\ migrateStage[ra] = "Streaming"
    /\ \A node \in targetRouting[ra] :
        MigrateFrontier(ra) \subseteq replicaApplied[node]

    /\ migrateStage' = [migrateStage EXCEPT ![ra] = "Activated"]
    /\ routing' = [routing EXCEPT ![ra] = targetRouting[ra]]
    /\ activationFrontier' =
        [activationFrontier EXCEPT ![ra] = MigrateFrontier(ra)]
    /\ topologyEpoch' = topologyEpoch + 1

    /\ lastMigrate' =
        [principal |-> migratePrincipal[ra],
         range |-> ra,
         phase |-> "Activate",
         authorized |-> migrateAuthorized[ra],
         executed |-> TRUE]

    /\ UNCHANGED migrateKind
    /\ UNCHANGED oldRouting
    /\ UNCHANGED targetRouting
    /\ UNCHANGED migratePrincipal
    /\ UNCHANGED migrateAuthorized
    /\ UNCHANGED AuthVars
    /\ UNCHANGED WriteVars
    /\ UNCHANGED ReadVars

FinishMigrate(ra) ==
    /\ ra \in TokenRanges
    /\ migrateStage[ra] = "Activated"

    /\ migrateStage' = [migrateStage EXCEPT ![ra] = "Stable"]

    /\ lastMigrate' =
        [principal |-> migratePrincipal[ra],
         range |-> ra,
         phase |-> "Finish",
         authorized |-> migrateAuthorized[ra],
         executed |-> TRUE]

    /\ UNCHANGED migrateKind
    /\ UNCHANGED oldRouting
    /\ UNCHANGED targetRouting
    /\ UNCHANGED routing
    /\ UNCHANGED activationFrontier
    /\ UNCHANGED migratePrincipal
    /\ UNCHANGED migrateAuthorized
    /\ UNCHANGED topologyEpoch
    /\ UNCHANGED AuthVars
    /\ UNCHANGED WriteVars
    /\ UNCHANGED ReadVars

Next ==
    \/ \E admin \in Principals :
        \E target \in Roles :
            \E resource \in Resources :
                \E perm \in PermissionT :
                    GrantPermission(admin, target, resource, perm)

    \/ \E admin \in Principals :
        \E target \in Roles :
            \E resource \in Resources :
                \E perm \in PermissionT :
                    RevokePermission(admin, target, resource, perm)

    \/ \E admin \in Principals :
        \E target \in Roles :
            \E resource \in Resources :
                \E perm \in PermissionT :
                    RejectGrantOrRevoke(admin, target, resource, perm)

    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E m \in Mutations :
                \E level \in ConsistencyLevels :
                    ReceiveWrite(p, coordinator, m, level)

    \/ \E p \in Principals :
        \E coordinator \in Nodes :
            \E m \in Mutations :
                \E level \in ConsistencyLevels :
                    RejectWrite(p, coordinator, m, level)

    \/ \E m \in Mutations : DispatchWrite(m)

    \/ \E m \in Mutations :
        \E node \in Nodes :
            ReplicaReceiveWrite(m, node)

    \/ \E m \in Mutations :
        \E node \in Nodes :
            ReplicaAck(m, node)

    \/ \E m \in Mutations : CompleteWrite(m)

    \/ \E m \in Mutations :
        \E source \in Nodes :
            \E target \in Nodes :
                SyncReplica(m, source, target)

    \/ \E node \in Nodes : FlushMemtable(node)

    \/ \E rd \in ReadRequests : DispatchRead(rd)

    \/ \E rd \in ReadRequests :
        \E node \in Nodes :
            ReplicaReadResponse(rd, node)

    \/ \E rd \in ReadRequests : CompleteRead(rd)

    \/ \E rd \in ReadRequests : RejectRead(rd)

    \/ \E p \in Principals :
        \E ra \in TokenRanges :
            \E kind \in MigrateKinds :
                \E target \in SUBSET Nodes :
                    StartMigrate(p, ra, kind, target)

    \/ \E p \in Principals :
        \E ra \in TokenRanges :
            \E kind \in MigrateKinds :
                \E target \in SUBSET Nodes :
                    RejectMigrate(p, ra, kind, target)

    \/ \E ra \in TokenRanges :
        \E source \in Nodes :
            \E target \in Nodes :
                \E m \in Mutations :
                    AdvanceMigrate(ra, source, target, m)

    \/ \E ra \in TokenRanges : ActivateMigrate(ra)

    \/ \E ra \in TokenRanges : FinishMigrate(ra)

Spec ==
    Init /\ [][Next]_GlobalVars

GlobalTypeInvariant ==
    /\ CoreOK

    /\ permissions \in [Roles -> [Resources -> SUBSET PermissionT]]

    /\ writeState \in [Mutations -> WriteStates]
    /\ writePrincipal \in [Mutations -> Principals]
    /\ writeCoordinatorState \in [Mutations -> Nodes]
    /\ writeLevel \in [Mutations -> ConsistencyLevels]
    /\ writeTargets \in [Mutations -> SUBSET Nodes]
    /\ accepted \subseteq Mutations
    /\ writeAuthorized \in [Mutations -> BOOLEAN]

    /\ commitLog \in [Nodes -> SUBSET Mutations]
    /\ memtable \in [Nodes -> SUBSET Mutations]
    /\ sstable \in [Nodes -> SUBSET Mutations]
    /\ replicaApplied \in [Nodes -> SUBSET Mutations]
    /\ ackSet \in [Mutations -> SUBSET Nodes]

    /\ readState \in [ReadRequests -> ReadStates]
    /\ readTargets \in [ReadRequests -> SUBSET Nodes]
    /\ readResponses \in [ReadRequests -> SUBSET Nodes]
    /\ responseValue \in
        [ReadRequests -> [Nodes -> MutationOrNone]]
    /\ readWinner \in [ReadRequests -> MutationOrNone]
    /\ readResult \in [ReadRequests -> MutationOrNone]
    /\ readAuthorized \in [ReadRequests -> BOOLEAN]
    /\ readRouteSafe \in [ReadRequests -> BOOLEAN]

    /\ migrateStage \in [TokenRanges -> MigrateStates]
    /\ migrateKind \in [TokenRanges -> MigrateKinds]
    /\ oldRouting \in [TokenRanges -> SUBSET Nodes]
    /\ targetRouting \in [TokenRanges -> SUBSET Nodes]
    /\ routing \in [TokenRanges -> SUBSET Nodes]
    /\ activationFrontier \in [TokenRanges -> SUBSET Mutations]
    /\ migratePrincipal \in [TokenRanges -> Principals]
    /\ migrateAuthorized \in [TokenRanges -> BOOLEAN]
    /\ topologyEpoch \in Nat

    /\ lastWrite \in LastWriteT
    /\ lastRead \in LastReadT
    /\ lastMigrate \in LastMigrateT
    /\ lastAuthChange \in LastAuthChangeT

RoleHierarchySafety ==
    /\ \A r \in Roles : r \in roleReach[r]
    /\ \A r \in Roles :
        roleMembers[r] \subseteq roleReach[r]
    /\ \A r \in Roles :
        \A inherited \in roleReach[r] :
            roleReach[inherited] \subseteq roleReach[r]
    /\ \A r1 \in Roles :
        \A r2 \in Roles :
            /\ r1 # r2
            => ~(r1 \in roleReach[r2] /\ r2 \in roleReach[r1])

RoutingSafety ==
    /\ \A ra \in TokenRanges :
        /\ routing[ra] # {}
        /\ Cardinality(routing[ra]) =
            replicationFactor[rangeKeyspace[ra]]

    /\ \A m \in Mutations :
        ackSet[m] \subseteq writeTargets[m]

    /\ \A rd \in ReadRequests :
        readResponses[rd] \subseteq readTargets[rd]

AuthorizationSafety ==
    /\ accepted \subseteq {m \in Mutations : writeAuthorized[m]}

    /\ \A m \in Mutations :
        writeState[m] = "Acknowledged" =>
            writeAuthorized[m]

    /\ \A rd \in ReadRequests :
        readState[rd] = "Completed" =>
            readAuthorized[rd]

    /\ \A ra \in TokenRanges :
        migrateStage[ra] # "Stable" =>
            migrateAuthorized[ra]

    /\ lastWrite.executed => lastWrite.authorized
    /\ lastRead.executed => lastRead.authorized
    /\ lastMigrate.executed => lastMigrate.authorized
    /\ lastAuthChange.executed => lastAuthChange.authorized

AuthSafety ==
    AuthorizationSafety

WritePathSafety ==
    /\ WriteFrontier = accepted

    /\ \A node \in Nodes :
        /\ LocalLogFrontier(node) \subseteq WriteFrontier
        /\ memtable[node] \subseteq ReplicaFrontier(node)
        /\ sstable[node] \subseteq ReplicaFrontier(node)
        /\ ReplicaFrontier(node) \subseteq WriteFrontier

    /\ \A m \in Mutations :
        /\ ackSet[m] \subseteq writeTargets[m]
        /\ \A node \in ackSet[m] : m \in ReplicaFrontier(node)
        /\ writeState[m] = "Acknowledged" =>
            Cardinality(ackSet[m]) >=
                RequiredResponses(writeLevel[m], Cardinality(writeTargets[m]))

    /\ \A m \in CommitFrontier("ALL") :
        ackSet[m] = writeTargets[m]

ReplicaSafety ==
    /\ \A node \in Nodes :
        /\ LocalLogFrontier(node) \subseteq WriteFrontier
        /\ ReplicaFrontier(node) \subseteq WriteFrontier

    /\ \A rd \in ReadRequests :
        \A node \in readResponses[rd] :
            \/ responseValue[rd][node] = NoMutation
            \/ /\ responseValue[rd][node] \in ReplicaFrontier(node)
               /\ responseValue[rd][node] \in WriteFrontier

ReadConsistencySafety ==
    /\ \A rd \in ReadRequests :
        readState[rd] = "Completed" =>
            /\ readAuthorized[rd]
            /\ MigrationSafeForRead(rd)
            /\ Cardinality(readResponses[rd]) >=
                RequiredResponses(readLevel[rd], Cardinality(readTargets[rd]))
            /\ readWinner[rd] = QueryFrontier(rd)
            /\ readWinner[rd] = FinalQueryFrontier(rd)
            /\ readResult[rd] = LogicalResult(FinalQueryFrontier(rd))
            /\ \A node \in readResponses[rd] :
                node \in readTargets[rd]

MigrateSafety ==
    /\ \A ra \in TokenRanges :
        /\ MigrateFrontier(ra) \subseteq WriteFrontier
        /\ migrateStage[ra] = "Streaming" =>
            /\ routing[ra] = oldRouting[ra]
            /\ targetRouting[ra] # {}
            /\ Cardinality(targetRouting[ra]) =
                replicationFactor[rangeKeyspace[ra]]

        /\ migrateStage[ra] = "Activated" =>
            /\ routing[ra] = targetRouting[ra]
            /\ \A node \in routing[ra] :
                activationFrontier[ra] \subseteq ReplicaFrontier(node)

        /\ migrateStage[ra] = "Stable" =>
            /\ routing[ra] = targetRouting[ra]
            /\ \A node \in routing[ra] :
                activationFrontier[ra] \subseteq ReplicaFrontier(node)

FrontierSafety ==
    /\ \A node \in Nodes :
        /\ LocalLogFrontier(node) \subseteq WriteFrontier
        /\ ReplicaFrontier(node) \subseteq WriteFrontier

    /\ \A level \in ConsistencyLevels :
        CommitFrontier(level) \subseteq WriteFrontier

    /\ \A rd \in ReadRequests :
        /\ QueryFrontier(rd) \in MutationOrNone
        /\ FinalQueryFrontier(rd) \in MutationOrNone
        /\ readState[rd] = "Completed" =>
            readResult[rd] = LogicalResult(FinalQueryFrontier(rd))

    /\ \A ra \in TokenRanges :
        MigrateFrontier(ra) \subseteq WriteFrontier

NoInventedData ==
    /\ \A node \in Nodes :
        /\ commitLog[node] \subseteq accepted
        /\ memtable[node] \subseteq accepted
        /\ sstable[node] \subseteq accepted
        /\ replicaApplied[node] \subseteq accepted

    /\ \A m \in Mutations :
        ackSet[m] # {} => m \in accepted

    /\ \A rd \in ReadRequests :
        /\ readWinner[rd] # NoMutation =>
            readWinner[rd] \in accepted
        /\ readResult[rd] # NoMutation =>
            readResult[rd] \in accepted

QuorumIntersectionSafety ==
    \A m \in Mutations :
        \A rd \in ReadRequests :
            /\ writeState[m] = "Acknowledged"
            /\ readState[rd] = "Completed"
            /\ MutationRange(m) =
                partitionRange[itemPartition[readItem[rd]]]
            /\ MutationTable(m) = itemTable[readItem[rd]]
            /\ writeTargets[m] = readTargets[rd]
            /\ RequiredResponses(
                   writeLevel[m], Cardinality(writeTargets[m])) +
               RequiredResponses(
                   readLevel[rd], Cardinality(readTargets[rd]))
               > Cardinality(writeTargets[m])
            => ackSet[m] \cap readResponses[rd] # {}

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ RoleHierarchySafety
    /\ RoutingSafety
    /\ AuthorizationSafety
    /\ WritePathSafety
    /\ ReplicaSafety
    /\ ReadConsistencySafety
    /\ MigrateSafety
    /\ FrontierSafety
    /\ NoInventedData
    /\ QuorumIntersectionSafety

=============================================================================
