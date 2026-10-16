------------------------- MODULE CassandraFrontier --------------------------

EXTENDS CCore

VARIABLES
    permission,
    writeState,
    writeEpoch,
    writeReplicas,
    writeLevel,
    writeCoordinator,
    writePrincipal,
    writeAuthorized,
    pendingDelivery,
    commitLogged,
    memtableApplied,
    ackSet,
    lastWrite,
    lastRead,
    activeEpoch,
    migrateState,
    sourceEpoch,
    targetEpoch,
    sourceReplicas,
    targetReplicas,
    protectedFrontier,
    lastMigrate,
    lastAdmin

Vars ==
    << permission,
       writeState,
       writeEpoch,
       writeReplicas,
       writeLevel,
       writeCoordinator,
       writePrincipal,
       writeAuthorized,
       pendingDelivery,
       commitLogged,
       memtableApplied,
       ackSet,
       lastWrite,
       lastRead,
       activeEpoch,
       migrateState,
       sourceEpoch,
       targetEpoch,
       sourceReplicas,
       targetReplicas,
       protectedFrontier,
       lastMigrate,
       lastAdmin >>

WriteRecordT ==
    [ kind       : {"None", "Receive", "Reject", "Complete", "Fail"},
      principal  : Principals,
      coordinator: Nodes,
      mutation   : Mutations,
      level      : ConsistencyLevels,
      authorized : BOOLEAN,
      succeeded  : BOOLEAN ]

ReadRecordT ==
    [ status      : ReadStates,
      principal   : Principals,
      coordinator : Nodes,
      partition   : Partitions,
      level       : ConsistencyLevels,
      epoch       : Epochs,
      replicas    : SUBSET Nodes,
      responses   : SUBSET Nodes,
      authorized  : BOOLEAN,
      routeSafe   : BOOLEAN,
      result      : SUBSET Mutations ]

MigrateRecordT ==
    [ kind       : {"None", "Start", "Reject", "Activate", "Finish", "Cleanup"},
      operator   : Principals,
      range      : TokenRanges,
      source     : Epochs,
      target     : Epochs,
      authorized : BOOLEAN,
      activated  : BOOLEAN ]

AdminRecordT ==
    [ kind       : {"None", "Grant", "Revoke", "Reject"},
      actor      : Principals,
      target     : Principals,
      resource   : Resources,
      permission : PermissionKinds,
      authorized : BOOLEAN ]

CanSelect(p, t) ==
    /\ p \in Principals
    /\ t \in Tables
    /\ "SELECT" \in permission[p][t]
       \/ "SELECT" \in permission[p][tableKeyspace[t]]

CanModify(p, t) ==
    /\ p \in Principals
    /\ t \in Tables
    /\ "MODIFY" \in permission[p][t]
       \/ "MODIFY" \in permission[p][tableKeyspace[t]]

CanAuthorize(p, resource) ==
    /\ p \in Principals
    /\ resource \in Resources
    /\ "AUTHORIZE" \in permission[p][resource]
       \/ /\ resource \in Tables
          /\ "AUTHORIZE" \in permission[p][tableKeyspace[resource]]

CanOperateTopology(p) ==
    p \in TopologyOperators

WriteFrontier ==
    {m \in Mutations : writeState[m] # "None"}

LocalPersistenceFrontier(n) ==
    commitLogged[n]

ReplicaFrontier(n, r) ==
    {m \in memtableApplied[n] : RangeOfMutation(m) = r}

CommitFrontier ==
    {m \in Mutations : writeState[m] = "Succeeded"}

RequiredWriteAcks(m) ==
    RequiredResponses(Cardinality(writeReplicas[m]), writeLevel[m])

RequiredReadResponses(q) ==
    RequiredResponses(Cardinality(q.replicas), q.level)

ReadResponseMutations(q) ==
    UNION {memtableApplied[n] : n \in q.responses}

QueryFrontier(q) ==
    ResolvedPutsFor(ReadResponseMutations(q), q.partition)

MigrateFrontier(r) ==
    WinnerSet({m \in CommitFrontier : RangeOfMutation(m) = r})

TargetCoversMigrate(r) ==
    \A m \in MigrateFrontier(r) :
        \A n \in targetReplicas[r] :
            \E x \in memtableApplied[n] :
                /\ mutationItem[x] = mutationItem[m]
                /\ mutationTimestamp[x] >= mutationTimestamp[m]

ProtectedCoveredByActive(r) ==
    \A m \in protectedFrontier[r] :
        \A n \in ReplicaSet(activeEpoch[r], r) :
            \E x \in memtableApplied[n] :
                /\ mutationItem[x] = mutationItem[m]
                /\ mutationTimestamp[x] >= mutationTimestamp[m]

LegalSyncTarget(m, n) ==
    \/ n \in writeReplicas[m]
    \/ \E r \in TokenRanges :
        /\ RangeOfMutation(m) = r
        /\ migrateState[r] = "Streaming"
        /\ n \in targetReplicas[r]

FinalQueryFrontier(q) ==
    IF /\ q.authorized
       /\ q.routeSafe
       /\ q.responses \subseteq q.replicas
       /\ Cardinality(q.responses) >= RequiredReadResponses(q)
    THEN QueryFrontier(q)
    ELSE {}

Init ==
    /\ CoreAssumption
    /\ permission \in
        [Principals -> [Resources -> SUBSET PermissionKinds]]
    /\ writeState = [m \in Mutations |-> "None"]
    /\ writeEpoch = [m \in Mutations |-> InitialEpoch]
    /\ writeReplicas = [m \in Mutations |-> {}]
    /\ writeLevel = [m \in Mutations |-> "ONE"]
    /\ writeCoordinator = [m \in Mutations |-> AnyNode]
    /\ writePrincipal = [m \in Mutations |-> AnyPrincipal]
    /\ writeAuthorized = [m \in Mutations |-> FALSE]
    /\ pendingDelivery = [m \in Mutations |-> {}]
    /\ commitLogged = [n \in Nodes |-> {}]
    /\ memtableApplied = [n \in Nodes |-> {}]
    /\ ackSet = [m \in Mutations |-> {}]
    /\ lastWrite =
        [ kind        |-> "None",
          principal   |-> AnyPrincipal,
          coordinator |-> AnyNode,
          mutation    |-> AnyMutation,
          level       |-> "ONE",
          authorized  |-> FALSE,
          succeeded   |-> FALSE ]
    /\ lastRead =
        [ status      |-> "Idle",
          principal   |-> AnyPrincipal,
          coordinator |-> AnyNode,
          partition   |-> AnyPartition,
          level       |-> "ONE",
          epoch       |-> InitialEpoch,
          replicas    |-> {},
          responses   |-> {},
          authorized  |-> FALSE,
          routeSafe   |-> FALSE,
          result      |-> {} ]
    /\ activeEpoch = [r \in TokenRanges |-> InitialEpoch]
    /\ migrateState = [r \in TokenRanges |-> "Stable"]
    /\ sourceEpoch = [r \in TokenRanges |-> InitialEpoch]
    /\ targetEpoch = [r \in TokenRanges |-> InitialEpoch]
    /\ sourceReplicas =
        [r \in TokenRanges |-> ReplicaSet(InitialEpoch, r)]
    /\ targetReplicas =
        [r \in TokenRanges |-> ReplicaSet(InitialEpoch, r)]
    /\ protectedFrontier = [r \in TokenRanges |-> {}]
    /\ lastMigrate =
        [ kind       |-> "None",
          operator   |-> AnyPrincipal,
          range      |-> AnyRange,
          source     |-> InitialEpoch,
          target     |-> InitialEpoch,
          authorized |-> FALSE,
          activated  |-> FALSE ]
    /\ lastAdmin =
        [ kind       |-> "None",
          actor      |-> AnyPrincipal,
          target     |-> AnyPrincipal,
          resource   |-> AnyResource,
          permission |-> "SELECT",
          authorized |-> FALSE ]

GrantPermission(admin, target, resource, perm) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ resource \in Resources
    /\ perm \in PermissionKinds
    /\ CanAuthorize(admin, resource)
    /\ permission' =
        [permission EXCEPT ![target][resource] = @ \cup {perm}]
    /\ lastAdmin' =
        [ kind       |-> "Grant",
          actor      |-> admin,
          target     |-> target,
          resource   |-> resource,
          permission |-> perm,
          authorized |-> TRUE ]
    /\ UNCHANGED
        << writeState, writeEpoch, writeReplicas, writeLevel,
           writeCoordinator, writePrincipal, writeAuthorized,
           pendingDelivery, commitLogged, memtableApplied, ackSet,
           lastWrite, lastRead, activeEpoch, migrateState,
           sourceEpoch, targetEpoch, sourceReplicas, targetReplicas,
           protectedFrontier, lastMigrate >>

RevokePermission(admin, target, resource, perm) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ resource \in Resources
    /\ perm \in PermissionKinds
    /\ CanAuthorize(admin, resource)
    /\ permission' =
        [permission EXCEPT ![target][resource] = @ \ {perm}]
    /\ lastAdmin' =
        [ kind       |-> "Revoke",
          actor      |-> admin,
          target     |-> target,
          resource   |-> resource,
          permission |-> perm,
          authorized |-> TRUE ]
    /\ UNCHANGED
        << writeState, writeEpoch, writeReplicas, writeLevel,
           writeCoordinator, writePrincipal, writeAuthorized,
           pendingDelivery, commitLogged, memtableApplied, ackSet,
           lastWrite, lastRead, activeEpoch, migrateState,
           sourceEpoch, targetEpoch, sourceReplicas, targetReplicas,
           protectedFrontier, lastMigrate >>

RejectAdmin(admin, target, resource, perm) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ resource \in Resources
    /\ perm \in PermissionKinds
    /\ ~CanAuthorize(admin, resource)
    /\ lastAdmin' =
        [ kind       |-> "Reject",
          actor      |-> admin,
          target     |-> target,
          resource   |-> resource,
          permission |-> perm,
          authorized |-> FALSE ]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, lastRead, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastMigrate >>

ReceiveWrite(p, coordinator, m, level) ==
    LET r == RangeOfMutation(m) IN
    LET e == activeEpoch[r] IN
    LET replicas == ReplicaSet(e, r) IN
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ m \in Mutations
    /\ level \in ConsistencyLevels
    /\ writeState[m] = "None"
    /\ CanModify(p, TableOfMutation(m))
    /\ writeState' = [writeState EXCEPT ![m] = "Accepted"]
    /\ writeEpoch' = [writeEpoch EXCEPT ![m] = e]
    /\ writeReplicas' = [writeReplicas EXCEPT ![m] = replicas]
    /\ writeLevel' = [writeLevel EXCEPT ![m] = level]
    /\ writeCoordinator' =
        [writeCoordinator EXCEPT ![m] = coordinator]
    /\ writePrincipal' = [writePrincipal EXCEPT ![m] = p]
    /\ writeAuthorized' = [writeAuthorized EXCEPT ![m] = TRUE]
    /\ pendingDelivery' = [pendingDelivery EXCEPT ![m] = replicas]
    /\ lastWrite' =
        [ kind        |-> "Receive",
          principal   |-> p,
          coordinator |-> coordinator,
          mutation    |-> m,
          level       |-> level,
          authorized  |-> TRUE,
          succeeded   |-> FALSE ]
    /\ UNCHANGED
        << permission, commitLogged, memtableApplied, ackSet,
           lastRead, activeEpoch, migrateState, sourceEpoch,
           targetEpoch, sourceReplicas, targetReplicas,
           protectedFrontier, lastMigrate, lastAdmin >>

RejectWrite(p, coordinator, m, level) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ m \in Mutations
    /\ level \in ConsistencyLevels
    /\ writeState[m] = "None"
    /\ ~CanModify(p, TableOfMutation(m))
    /\ lastWrite' =
        [ kind        |-> "Reject",
          principal   |-> p,
          coordinator |-> coordinator,
          mutation    |-> m,
          level       |-> level,
          authorized  |-> FALSE,
          succeeded   |-> FALSE ]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastRead, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastMigrate, lastAdmin >>

ReplicaReceiveAndApply(m, n) ==
    /\ m \in Mutations
    /\ n \in Nodes
    /\ writeState[m] = "Accepted"
    /\ n \in pendingDelivery[m]
    /\ n \in writeReplicas[m]
    /\ m \notin memtableApplied[n]
    /\ pendingDelivery' =
        [pendingDelivery EXCEPT ![m] = @ \ {n}]
    /\ commitLogged' =
        [commitLogged EXCEPT ![n] = @ \cup {m}]
    /\ memtableApplied' =
        [memtableApplied EXCEPT ![n] = @ \cup {m}]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, ackSet, lastWrite, lastRead, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastMigrate, lastAdmin >>

ReplicaAck(m, n) ==
    /\ m \in Mutations
    /\ n \in Nodes
    /\ writeState[m] = "Accepted"
    /\ n \in writeReplicas[m]
    /\ m \in memtableApplied[n]
    /\ n \notin ackSet[m]
    /\ ackSet' = [ackSet EXCEPT ![m] = @ \cup {n}]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, lastWrite, lastRead, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastMigrate, lastAdmin >>

CompleteWrite(m) ==
    /\ m \in Mutations
    /\ writeState[m] = "Accepted"
    /\ Cardinality(ackSet[m]) >= RequiredWriteAcks(m)
    /\ writeState' = [writeState EXCEPT ![m] = "Succeeded"]
    /\ lastWrite' =
        [ kind        |-> "Complete",
          principal   |-> writePrincipal[m],
          coordinator |-> writeCoordinator[m],
          mutation    |-> m,
          level       |-> writeLevel[m],
          authorized  |-> writeAuthorized[m],
          succeeded   |-> TRUE ]
    /\ UNCHANGED
        << permission, writeEpoch, writeReplicas, writeLevel,
           writeCoordinator, writePrincipal, writeAuthorized,
           pendingDelivery, commitLogged, memtableApplied, ackSet,
           lastRead, activeEpoch, migrateState, sourceEpoch,
           targetEpoch, sourceReplicas, targetReplicas,
           protectedFrontier, lastMigrate, lastAdmin >>

FailWrite(m) ==
    /\ m \in Mutations
    /\ writeState[m] = "Accepted"
    /\ Cardinality(ackSet[m]) < RequiredWriteAcks(m)
    /\ writeState' = [writeState EXCEPT ![m] = "Failed"]
    /\ lastWrite' =
        [ kind        |-> "Fail",
          principal   |-> writePrincipal[m],
          coordinator |-> writeCoordinator[m],
          mutation    |-> m,
          level       |-> writeLevel[m],
          authorized  |-> writeAuthorized[m],
          succeeded   |-> FALSE ]
    /\ UNCHANGED
        << permission, writeEpoch, writeReplicas, writeLevel,
           writeCoordinator, writePrincipal, writeAuthorized,
           pendingDelivery, commitLogged, memtableApplied, ackSet,
           lastRead, activeEpoch, migrateState, sourceEpoch,
           targetEpoch, sourceReplicas, targetReplicas,
           protectedFrontier, lastMigrate, lastAdmin >>

SyncLateReplica(m, n) ==
    /\ m \in Mutations
    /\ n \in Nodes
    /\ m \in WriteFrontier
    /\ LegalSyncTarget(m, n)
    /\ m \notin memtableApplied[n]
    /\ commitLogged' =
        [commitLogged EXCEPT ![n] = @ \cup {m}]
    /\ memtableApplied' =
        [memtableApplied EXCEPT ![n] = @ \cup {m}]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, ackSet, lastWrite,
           lastRead, activeEpoch, migrateState, sourceEpoch,
           targetEpoch, sourceReplicas, targetReplicas,
           protectedFrontier, lastMigrate, lastAdmin >>

ReadRequest(p, coordinator, partition, level) ==
    LET r == RangeOfPartition(partition) IN
    LET e == activeEpoch[r] IN
    LET replicas == ReplicaSet(e, r) IN
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ partition \in Partitions
    /\ level \in ConsistencyLevels
    /\ lastRead.status # "Pending"
    /\ CanSelect(p, partitionTable[partition])
    /\ lastRead' =
        [ status      |-> "Pending",
          principal   |-> p,
          coordinator |-> coordinator,
          partition   |-> partition,
          level       |-> level,
          epoch       |-> e,
          replicas    |-> replicas,
          responses   |-> {},
          authorized  |-> TRUE,
          routeSafe   |-> TRUE,
          result      |-> {} ]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastMigrate, lastAdmin >>

RejectRead(p, coordinator, partition, level) ==
    /\ p \in Principals
    /\ coordinator \in Nodes
    /\ partition \in Partitions
    /\ level \in ConsistencyLevels
    /\ lastRead.status # "Pending"
    /\ ~CanSelect(p, partitionTable[partition])
    /\ lastRead' =
        [ status      |-> "Rejected",
          principal   |-> p,
          coordinator |-> coordinator,
          partition   |-> partition,
          level       |-> level,
          epoch       |-> activeEpoch[RangeOfPartition(partition)],
          replicas    |-> {},
          responses   |-> {},
          authorized  |-> FALSE,
          routeSafe   |-> FALSE,
          result      |-> {} ]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastMigrate, lastAdmin >>

ReplicaReadResponse(n) ==
    /\ lastRead.status = "Pending"
    /\ n \in lastRead.replicas
    /\ n \notin lastRead.responses
    /\ lastRead' =
        [lastRead EXCEPT !.responses = @ \cup {n}]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastMigrate, lastAdmin >>

CompleteRead ==
    LET answer == QueryFrontier(lastRead) IN
    /\ lastRead.status = "Pending"
    /\ Cardinality(lastRead.responses)
        >= RequiredReadResponses(lastRead)
    /\ lastRead' =
        [lastRead EXCEPT
            !.status = "Succeeded",
            !.result = answer]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastMigrate, lastAdmin >>

FailRead ==
    /\ lastRead.status = "Pending"
    /\ Cardinality(lastRead.responses)
        < RequiredReadResponses(lastRead)
    /\ lastRead' =
        [lastRead EXCEPT
            !.status = "Failed",
            !.result = {}]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastMigrate, lastAdmin >>

StartMigrate(operator, r, newEpoch) ==
    /\ operator \in Principals
    /\ r \in TokenRanges
    /\ newEpoch \in Epochs
    /\ CanOperateTopology(operator)
    /\ migrateState[r] = "Stable"
    /\ newEpoch # activeEpoch[r]
    /\ ReplicaSet(newEpoch, r) # ReplicaSet(activeEpoch[r], r)
    /\ migrateState' =
        [migrateState EXCEPT ![r] = "Streaming"]
    /\ sourceEpoch' =
        [sourceEpoch EXCEPT ![r] = activeEpoch[r]]
    /\ targetEpoch' =
        [targetEpoch EXCEPT ![r] = newEpoch]
    /\ sourceReplicas' =
        [sourceReplicas EXCEPT ![r] = ReplicaSet(activeEpoch[r], r)]
    /\ targetReplicas' =
        [targetReplicas EXCEPT ![r] = ReplicaSet(newEpoch, r)]
    /\ lastMigrate' =
        [ kind       |-> "Start",
          operator   |-> operator,
          range      |-> r,
          source     |-> activeEpoch[r],
          target     |-> newEpoch,
          authorized |-> TRUE,
          activated  |-> FALSE ]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, lastRead, activeEpoch,
           protectedFrontier, lastAdmin >>

RejectMigrate(operator, r, newEpoch) ==
    /\ operator \in Principals
    /\ r \in TokenRanges
    /\ newEpoch \in Epochs
    /\ ~CanOperateTopology(operator)
    /\ lastMigrate' =
        [ kind       |-> "Reject",
          operator   |-> operator,
          range      |-> r,
          source     |-> activeEpoch[r],
          target     |-> newEpoch,
          authorized |-> FALSE,
          activated  |-> FALSE ]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, lastRead, activeEpoch,
           migrateState, sourceEpoch, targetEpoch, sourceReplicas,
           targetReplicas, protectedFrontier, lastAdmin >>

StreamRangeData(r, source, target, m) ==
    /\ r \in TokenRanges
    /\ source \in Nodes
    /\ target \in Nodes
    /\ m \in Mutations
    /\ migrateState[r] = "Streaming"
    /\ source \in sourceReplicas[r]
    /\ target \in targetReplicas[r]
    /\ RangeOfMutation(m) = r
    /\ m \in memtableApplied[source]
    /\ m \in WriteFrontier
    /\ m \notin memtableApplied[target]
    /\ commitLogged' =
        [commitLogged EXCEPT ![target] = @ \cup {m}]
    /\ memtableApplied' =
        [memtableApplied EXCEPT ![target] = @ \cup {m}]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, ackSet, lastWrite,
           lastRead, activeEpoch, migrateState, sourceEpoch,
           targetEpoch, sourceReplicas, targetReplicas,
           protectedFrontier, lastMigrate, lastAdmin >>

CatchUpMigrate(r, source, target, m) ==
    StreamRangeData(r, source, target, m)

ActivateMigrate(r) ==
    /\ r \in TokenRanges
    /\ migrateState[r] = "Streaming"
    /\ TargetCoversMigrate(r)
    /\ activeEpoch' =
        [activeEpoch EXCEPT ![r] = targetEpoch[r]]
    /\ migrateState' =
        [migrateState EXCEPT ![r] = "Activated"]
    /\ protectedFrontier' =
        [protectedFrontier EXCEPT ![r] = MigrateFrontier(r)]
    /\ lastMigrate' =
        [ kind       |-> "Activate",
          operator   |-> AnyPrincipal,
          range      |-> r,
          source     |-> sourceEpoch[r],
          target     |-> targetEpoch[r],
          authorized |-> TRUE,
          activated  |-> TRUE ]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, lastRead, sourceEpoch,
           targetEpoch, sourceReplicas, targetReplicas, lastAdmin >>

FinishMigrate(r) ==
    /\ r \in TokenRanges
    /\ migrateState[r] = "Activated"
    /\ migrateState' =
        [migrateState EXCEPT ![r] = "CleanupEligible"]
    /\ lastMigrate' =
        [ kind       |-> "Finish",
          operator   |-> AnyPrincipal,
          range      |-> r,
          source     |-> sourceEpoch[r],
          target     |-> targetEpoch[r],
          authorized |-> TRUE,
          activated  |-> TRUE ]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, lastRead, activeEpoch,
           sourceEpoch, targetEpoch, sourceReplicas, targetReplicas,
           protectedFrontier, lastAdmin >>

CompleteCleanup(r) ==
    /\ r \in TokenRanges
    /\ migrateState[r] = "CleanupEligible"
    /\ ProtectedCoveredByActive(r)
    /\ migrateState' =
        [migrateState EXCEPT ![r] = "Stable"]
    /\ lastMigrate' =
        [ kind       |-> "Cleanup",
          operator   |-> AnyPrincipal,
          range      |-> r,
          source     |-> sourceEpoch[r],
          target     |-> targetEpoch[r],
          authorized |-> TRUE,
          activated  |-> TRUE ]
    /\ UNCHANGED
        << permission, writeState, writeEpoch, writeReplicas,
           writeLevel, writeCoordinator, writePrincipal,
           writeAuthorized, pendingDelivery, commitLogged,
           memtableApplied, ackSet, lastWrite, lastRead, activeEpoch,
           sourceEpoch, targetEpoch, sourceReplicas, targetReplicas,
           protectedFrontier, lastAdmin >>

Next ==
    \/ \E admin \in Principals :
        \E target \in Principals :
            \E resource \in Resources :
                \E perm \in PermissionKinds :
                    GrantPermission(admin, target, resource, perm)
    \/ \E admin \in Principals :
        \E target \in Principals :
            \E resource \in Resources :
                \E perm \in PermissionKinds :
                    RevokePermission(admin, target, resource, perm)
    \/ \E admin \in Principals :
        \E target \in Principals :
            \E resource \in Resources :
                \E perm \in PermissionKinds :
                    RejectAdmin(admin, target, resource, perm)
    \/ \E p \in Principals :
        \E n \in Nodes :
            \E m \in Mutations :
                \E level \in ConsistencyLevels :
                    ReceiveWrite(p, n, m, level)
    \/ \E p \in Principals :
        \E n \in Nodes :
            \E m \in Mutations :
                \E level \in ConsistencyLevels :
                    RejectWrite(p, n, m, level)
    \/ \E m \in Mutations :
        \E n \in Nodes :
            ReplicaReceiveAndApply(m, n)
    \/ \E m \in Mutations :
        \E n \in Nodes :
            ReplicaAck(m, n)
    \/ \E m \in Mutations :
        CompleteWrite(m)
    \/ \E m \in Mutations :
        FailWrite(m)
    \/ \E m \in Mutations :
        \E n \in Nodes :
            SyncLateReplica(m, n)
    \/ \E p \in Principals :
        \E n \in Nodes :
            \E partition \in Partitions :
                \E level \in ConsistencyLevels :
                    ReadRequest(p, n, partition, level)
    \/ \E p \in Principals :
        \E n \in Nodes :
            \E partition \in Partitions :
                \E level \in ConsistencyLevels :
                    RejectRead(p, n, partition, level)
    \/ \E n \in Nodes :
        ReplicaReadResponse(n)
    \/ CompleteRead
    \/ FailRead
    \/ \E operator \in Principals :
        \E r \in TokenRanges :
            \E e \in Epochs :
                StartMigrate(operator, r, e)
    \/ \E operator \in Principals :
        \E r \in TokenRanges :
            \E e \in Epochs :
                RejectMigrate(operator, r, e)
    \/ \E r \in TokenRanges :
        \E source \in Nodes :
            \E target \in Nodes :
                \E m \in Mutations :
                    StreamRangeData(r, source, target, m)
    \/ \E r \in TokenRanges :
        \E source \in Nodes :
            \E target \in Nodes :
                \E m \in Mutations :
                    CatchUpMigrate(r, source, target, m)
    \/ \E r \in TokenRanges :
        ActivateMigrate(r)
    \/ \E r \in TokenRanges :
        FinishMigrate(r)
    \/ \E r \in TokenRanges :
        CompleteCleanup(r)

Spec ==
    Init /\ [][Next]_Vars

GlobalTypeInvariant ==
    /\ CoreTypeOK
    /\ permission \in
        [Principals -> [Resources -> SUBSET PermissionKinds]]
    /\ writeState \in [Mutations -> WriteStates]
    /\ writeEpoch \in [Mutations -> Epochs]
    /\ writeReplicas \in [Mutations -> SUBSET Nodes]
    /\ writeLevel \in [Mutations -> ConsistencyLevels]
    /\ writeCoordinator \in [Mutations -> Nodes]
    /\ writePrincipal \in [Mutations -> Principals]
    /\ writeAuthorized \in [Mutations -> BOOLEAN]
    /\ pendingDelivery \in [Mutations -> SUBSET Nodes]
    /\ commitLogged \in [Nodes -> SUBSET Mutations]
    /\ memtableApplied \in [Nodes -> SUBSET Mutations]
    /\ ackSet \in [Mutations -> SUBSET Nodes]
    /\ lastWrite \in WriteRecordT
    /\ lastRead \in ReadRecordT
    /\ activeEpoch \in [TokenRanges -> Epochs]
    /\ migrateState \in [TokenRanges -> MigrateStates]
    /\ sourceEpoch \in [TokenRanges -> Epochs]
    /\ targetEpoch \in [TokenRanges -> Epochs]
    /\ sourceReplicas \in [TokenRanges -> SUBSET Nodes]
    /\ targetReplicas \in [TokenRanges -> SUBSET Nodes]
    /\ protectedFrontier \in [TokenRanges -> SUBSET Mutations]
    /\ lastMigrate \in MigrateRecordT
    /\ lastAdmin \in AdminRecordT
    /\ \A m \in Mutations :
        writeState[m] # "None" =>
            /\ writeReplicas[m] = ReplicaSet(writeEpoch[m], RangeOfMutation(m))
            /\ pendingDelivery[m] \subseteq writeReplicas[m]
    /\ \A r \in TokenRanges :
        /\ sourceReplicas[r] = ReplicaSet(sourceEpoch[r], r)
        /\ targetReplicas[r] = ReplicaSet(targetEpoch[r], r)

AuthSafety ==
    /\ lastWrite.kind = "None"
       \/ lastWrite.kind = "Reject"
       \/ /\ lastWrite.authorized
          /\ (lastWrite.kind # "Complete" \/ lastWrite.succeeded)
    /\ lastRead.status # "Succeeded"
       \/ /\ lastRead.authorized
          /\ lastRead.routeSafe
    /\ lastMigrate.kind = "None"
       \/ lastMigrate.kind = "Reject"
       \/ lastMigrate.authorized
    /\ lastAdmin.kind = "None"
       \/ lastAdmin.kind = "Reject"
       \/ lastAdmin.authorized

WritePathSafety ==
    /\ \A n \in Nodes :
        memtableApplied[n] \subseteq commitLogged[n]
    /\ \A n \in Nodes :
        commitLogged[n] \subseteq WriteFrontier
    /\ \A m \in Mutations :
        /\ ackSet[m] \subseteq writeReplicas[m]
        /\ \A n \in ackSet[m] : m \in memtableApplied[n]
    /\ \A m \in CommitFrontier :
        Cardinality(ackSet[m]) >= RequiredWriteAcks(m)
    /\ CommitFrontier \subseteq WriteFrontier

ReplicaSafety ==
    /\ \A n \in Nodes :
        LocalPersistenceFrontier(n) \subseteq WriteFrontier
    /\ \A n \in Nodes :
        \A r \in TokenRanges :
            ReplicaFrontier(n, r) \subseteq WriteFrontier
    /\ \A n \in Nodes :
        WinnerSet(memtableApplied[n]) \subseteq memtableApplied[n]

ReadSafety ==
    lastRead.status # "Succeeded"
    \/
    /\ lastRead.authorized
    /\ lastRead.routeSafe
    /\ lastRead.responses \subseteq lastRead.replicas
    /\ Cardinality(lastRead.responses) >= RequiredReadResponses(lastRead)
    /\ lastRead.result = QueryFrontier(lastRead)
    /\ lastRead.result = FinalQueryFrontier(lastRead)
    /\ \A m \in lastRead.result :
        /\ mutationKind[m] = "Put"
        /\ m \in ReadResponseMutations(lastRead)
        /\ m \in WriteFrontier

MigrateSafety ==
    /\ \A r \in TokenRanges :
        ProtectedCoveredByActive(r)
    /\ \A r \in TokenRanges :
        migrateState[r] = "Streaming" =>
            /\ activeEpoch[r] = sourceEpoch[r]
            /\ sourceReplicas[r] = ReplicaSet(sourceEpoch[r], r)
            /\ targetReplicas[r] = ReplicaSet(targetEpoch[r], r)
    /\ \A r \in TokenRanges :
        migrateState[r] \in {"Activated", "CleanupEligible"} =>
            activeEpoch[r] = targetEpoch[r]
    /\ \A r \in TokenRanges :
        migrateState[r] = "Streaming" =>
            sourceEpoch[r] # targetEpoch[r]

FrontierSafety ==
    /\ CommitFrontier \subseteq WriteFrontier
    /\ \A n \in Nodes :
        LocalPersistenceFrontier(n) \subseteq WriteFrontier
    /\ \A n \in Nodes :
        \A r \in TokenRanges :
            ReplicaFrontier(n, r)
                \subseteq LocalPersistenceFrontier(n)
    /\ \A m \in CommitFrontier :
        \A n \in ackSet[m] :
            m \in ReplicaFrontier(n, RangeOfMutation(m))
    /\ \A r \in TokenRanges :
        migrateState[r] = "Streaming" =>
            TargetCoversMigrate(r)
            \/ ~TargetCoversMigrate(r)
    /\ lastRead.status # "Succeeded"
       \/ lastRead.result = FinalQueryFrontier(lastRead)

====
