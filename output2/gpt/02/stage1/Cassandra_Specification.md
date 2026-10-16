# Cassandra Frontier-based Formal Modeling Specification

## 1. Specification Objectives

This document defines the Frontier-based formal modeling specification for Apache Cassandra, for subsequent automatic generation of Cassandra TLA+ models and TLC configurations.

The purpose of this model is not to reproduce Cassandra's source code, network protocols, storage file formats, or all operational procedures, but to abstract and verify the following safety boundaries:

1. Only authorized principals can successfully read, write, or perform topology changes;
2. Writes must be routed by the coordinator node to the current replica set;
3. Replica acknowledgments must be based on the replica having recorded and applied the corresponding mutation;
4. The write consistency level determines the number of replica responses required for the coordinator node to acknowledge success to the client;
5. The read consistency level determines how many replica responses the coordinator node must obtain before returning results;
6. Read results must be resolved from versions in the actually responding replicas using Cassandra's Last-Write-Wins (LWW) rule;
7. Late replicas, hint delivery, read repair, and anti-entropy repair can make replicas eventually converge, but cannot create mutations that were not accepted;
8. Data range migrations caused by bootstrap, decommission, move, replace, and related streaming must not lose data already safely accepted within the migrated range after routing switches;
9. All successful read results must lie within the final visible boundary jointly constrained by authorization, write, replica, read consistency, and migration safety.

This specification uses the Cassandra 5.0 official documentation snapshot as the basis for business semantics. The Frontier method is used only to organize the boundary relationships of writes, commits, replicas, reads, and migrations.

---

## 2. Abstraction Scope

### 2.1 Semantics Included in the Model

The model should include the following Cassandra semantics:

- Partition routing based on a consistent-hash token ring;
- Mapping from token ranges to replica node sets;
- Keyspace-level replication strategy and replication factor;
- The coordinator node receives requests, locates the token range to which the partition belongs, and sends mutations to replicas;
- Multi-master replicas: any replica owning the partition can accept a mutation;
- Mutation timestamps and LWW conflict resolution;
- Write commit log recording, memtable application, and replica acknowledgment;
- ONE, QUORUM, and ALL as representative write consistency and read consistency levels;
- Writes are sent to the current replica set, and the coordinator node waits for responses according to the write consistency level;
- Reads involve the coordinator node collecting enough replica responses and performing version resolution;
- A unified synchronization abstraction for late replicas, hinted handoff, read repair, or anti-entropy repair;
- bootstrap, decommission, move, replace, streaming, and routing switchover of token ranges;
- Abstraction of authorization semantics such as Cassandra roles, permission inheritance, SELECT, MODIFY, and AUTHORIZE;
- Rejection branches for unauthorized write, read, and migration requests;
- Write, replica, query, migration, and final query Frontier.

### 2.2 Content Explicitly Not Modeled

The following content is not part of the first version model:

1. CQL parsing, syntax validation, query optimizer, and driver protocol;
2. Cross-partition queries, cross-partition transactions, distributed joins, and foreign keys;
3. Lightweight transactions (LWT) and the Paxos protocol;
4. The batchlog protocol for logged batches;
5. counters, materialized views, secondary indexes, SAI, user-defined functions, and aggregate functions;
6. transient replication；
7. gossip's `(generation, version)` vector clock details;
8. The calculation method of the Phi Accrual Failure Detector and inconsistent failure judgments across different nodes;
9. The time windows of speculative retry and the specific replica selection algorithm;
10. The file format, expiration window, and replay scheduling details of hinted handoff;
11. The internal processes of Merkle trees, repair hash algorithms, incremental repair, and subrange repair;
12. commit log segments, fsync timing, SSTable file format, Bloom filters, compaction, and caching;
13. TLS, password validation, JMX security, CIDR restrictions, and authentication protocols;
14. The exact token allocation algorithm for virtual nodes;
15. The execution protocol of the `nodetool` command;
16. Operational risks from forced decommission causing the replica count to fall below the replication factor;
17. All actual implementation details of parallel range movement.

The model can retain an abstract state of “node temporarily unresponsive,” but it does not verify whether the failure detection algorithm is correct, nor does it assume that all nodes have exactly the same immediate view of UP/DOWN status.

---

## 3. Core Modeling Principles

### 3.1 Single partition semantics

The first version of the model uses single partition operations as the basic read and write unit. Each read request and write request targets one partition, and therefore can be handled by the token range and replica set corresponding to that partition.

This is the primary high-performance query model described in Cassandra's official documentation: data is partitioned by partition key, and well-performing queries typically provide a partition key; Cassandra does not provide cross-partition transactions.

The model should not abstract operations across multiple partitions into atomic transactions.

### 3.2 mutation rather than “mutable object” is the version unit

Cassandra uses timestamp versioning for mutation and resolves conflicts with the LWW rule. The basic write object in the model should be `Mutation`, rather than representing writes only with a Boolean state of “whether a data item exists”.

Each mutation contains at least:

- The data item it belongs to;
- The table it belongs to;
- The keyspace it belongs to;
- The partition it belongs to;
- The token range it belongs to;
- The logical value or deletion marker;
- The timestamp or, in a finite model, a totally ordered version number;
- The coordinating node that initiated this mutation;
- The write consistency level;
- The current write processing status.

Deletion should be abstracted as a tombstone mutation, rather than directly removing the data item from the state. This preserves the LWW semantics that “deletion is also a timestamped mutation”.

### 3.3 LWW resolution rule

For the same logical data item, a replica may temporarily hold multiple mutations. The replica's currently readable version is the mutation with the highest version among its applied mutations.

The model should adopt a deterministic total order comparison relation, for example:

1. First compare the mutation timestamp;
2. When timestamps are the same in a finite model, use a preset unique version sequence number as a stable abstract tie-breaker.

This tie-breaker is intended to make the “winning version” uniquely determined in the finite-state model, and does not represent the complete implementation details in the official Cassandra documentation for all cases with identical timestamps.

After a read coordinator obtains responses from multiple replicas, it should resolve the response versions for the same data item again according to the same LWW relation and return the winning version among them; if the winning version is a tombstone, the logical read result should appear as if the data item does not exist or has been deleted.

---

## 4. Entities, Constants, and Mappings

### 4.1 Principal and Role

`Principal` denotes the subject that performs client or administrative operations. In Cassandra, this corresponds to an authenticated database role, user, or client session holding that role.

`Role` denotes a Cassandra database role. A role can:

- have the LOGIN permission;
- have the SUPERUSER status;
- be granted other roles;
- inherit permissions and SUPERUSER status from granted roles;
- not inherit the LOGIN permission from granted roles.

The first version of the model may merge `Principal` with the directly logged-in role, or may explicitly retain:

- `principalRole : Principal -> Role`
- `roleMembers : Role -> SUBSET Role`

Role grant relations must be acyclic to correspond to the semantics that the Cassandra role hierarchy is a directed acyclic graph.

### 4.2 Keyspace and Table

`Keyspace` is a data container and is associated with a replication strategy.

`Table` belongs to a keyspace:

- `tableKeyspace : Table -> Keyspace`

In the model, permission decisions, replication factors, token range replica sets, and data item ownership should all be traceable to the keyspace to which the table belongs.

The first version of the model does not need to represent column types, clustering keys, collection types, or schema evolution details.

### 4.3 Partition, Token, and TokenRange

`Partition` is a Cassandra data partition identified by a partition key.

`Token` is a ring position obtained by hashing a partition key through a partitioner.

`TokenRange` is a contiguous range on the token ring and is the basic data range unit for routing, replica selection, and migration.

The following mappings are recommended:

- `partitionToken : Partition -> Token`
- `partitionRange : Partition -> TokenRange`
- `rangeKeyspace : TokenRange -> Keyspace`

and maintain:

- each partition belongs to exactly one token range;
- Partitions in the same token range have the same current routing replica set;
- A token range belongs to a keyspace so that different keyspaces can use different replication strategies.

The model does not need to compute the actual Murmur3 hash, nor does it need to represent the full arithmetic of a continuous integer ring. A finite model can directly treat `partitionRange` as a given constant mapping.

### 4.4 Node, Endpoint, and vnode

`Node` represents a physical node in a Cassandra cluster, corresponding to the physical node represented by the Host ID in official terminology.

The exact mapping of `Endpoint`, IP, port, and Host ID is not part of the first version of the model. The model only needs to ensure that one replica resides on one `Node`.

A physical node can own multiple tokens, i.e., vnodes. The model can express this relationship through the following mapping:

- `nodeTokens : Node -> SUBSET Token`

However, the first version does not need to verify whether the vnode allocation algorithm is balanced.

### 4.5 Replica

`Replica` represents the replica position of a token range in a keyspace on a physical node.

To reduce the state space, Replica objects need not be defined separately, and replicas can be directly represented by `(TokenRange, Node)` pairs. If an explicit Replica set is used, then the following is required:

- `replicaRange : Replica -> TokenRange`
- `replicaNode : Replica -> Node`

For a keyspace and token range, the current replica set that can participate in request processing is denoted as:

- `routingReplicas[keyspace][range]`

The nodes in this set must be distinct. The model does not require implementing the actual node-selection algorithms of SimpleStrategy or NetworkTopologyStrategy; instead, the replica set is treated as a configuration result derived from the replication strategy and token metadata.

### 4.6 Data Item and Mutation

`DataItem` is a logical read and write object. It can be abstracted as a row, column, or cell within a partition.

It is recommended to use:

- `itemTable : DataItem -> Table`
- `itemPartition : DataItem -> Partition`
- `mutationItem : Mutation -> DataItem`
- `mutationVersion : Mutation -> Version`
- `mutationKind : Mutation -> {"Value", "Tombstone"}`

and maintain:

- `tableKeyspace[itemTable[x]] = rangeKeyspace[partitionRange[itemPartition[x]]]`；
- A mutation updates only one DataItem;
- Different mutations for the same DataItem may occur concurrently;
- A tombstone participates in LWW selection like a normal value mutation.

### 4.7 Coordinator

`Coordinator` is a Cassandra node that receives client CQL read/write requests and coordinates replica requests.

Each read/write request should record the coordinator node:

- `writeCoordinator : WriteRequest -> Node`
- `readCoordinator : ReadRequest -> Node`

The coordinator node is not required to be a replica of the partition. The coordinator node is responsible for:

1. Check whether the request principal is authorized;
2. Find the token range based on the partition key;
3. Determine the current routing replica set;
4. Send mutation or read requests to replicas;
5. Wait for replica responses that satisfy the consistency level;
6. Perform LWW resolution on read responses;
7. Return success, results, or rejection to the client after the condition is reached.

### 4.8 Replica Set and Replication Factor

Each keyspace has a replication factor and its corresponding replica selection result.

The model needs at least:

- `replicationFactor : Keyspace -> Nat`
- `routingReplicas : Keyspace -> TokenRange -> SUBSET Node`

For each `(keyspace, range)` in a stable topology, the following should hold:

- `Cardinality(routingReplicas[keyspace][range]) = replicationFactor[keyspace]`。

If the model allows node unavailability, the replica set itself does not change because a node is temporarily unresponsive; unavailability only affects whether a particular read or write can obtain enough responses.

---

## 5. Authorization, Permissions, and Rejected Operations

## 5.1 Authorization Modes

Cassandra authentication and authorization can be disabled. If `AllowAllAuthenticator` is used, authentication is disabled and the permission system effectively does not take effect; if `AllowAllAuthorizer` is used, all roles are considered to have all permissions.

The model should use an explicit constant or state:

- `authorizationEnabled : BOOLEAN`

Its semantics are:

- When `authorizationEnabled = FALSE`, all accepted Principals can perform operations within the model scope;
- When `authorizationEnabled = TRUE`, successful operations must pass permission checks.

The model does not verify passwords, authentication handshakes, or certificates; it only assumes that a request is already bound to a Principal.

## 5.2 Permission Resource Hierarchy

Data resources in Cassandra have a hierarchy, including at least:

- ALL KEYSPACES；
- KEYSPACE；
- TABLE。

The first version of the model may restrict the resource hierarchy to:

- `AllKeyspaces`；
- `KeyspaceResource(keyspace)`；
- `TableResource(table)`。

Permissions propagate downward from higher levels. For example, having SELECT permission on a keyspace means having SELECT permission on all tables within that keyspace.

The following permission types are recommended to be retained:

- `SELECT`: allows reads;
- `MODIFY`: allows data modifications such as INSERT, UPDATE, DELETE, and TRUNCATE;
- `AUTHORIZE`: allows granting or revoking permissions on resources;
- `MANAGE_TOPOLOGY`: An operational abstraction permission in the model, used to start or switch token range migration;
- `SUPERUSER`: Can be considered to have all permissions within the model.

Here, `MANAGE_TOPOLOGY` is not a direct item-by-item replication of `nodetool` topology operations in the Cassandra CQL permission table, but a controlled management permission introduced for the bootstrap, decommission, move, and replace operations of this model. This abstraction should be clearly distinguished from CQL data permissions.

## 5.3 Effective Permissions

Effective permissions should simultaneously consider:

1. Principal's current login role;
2. Roles transitively obtainable in the role inheritance graph;
3. Directly granted permissions;
4. Propagation from the keyspace or all-keyspaces level to the table level;
5. SUPERUSER status;
6. Whether authorization is enabled.

Definitional semantics are:

- Successful reads require having `SELECT` on the target table or an equivalent higher-level permission;
- Successful writes require having `MODIFY` on the target table or an equivalent higher-level permission;
- Successful permission grant or revoke requires having `AUTHORIZE` on the target resource or SUPERUSER;
- Successful migration requires having `MANAGE_TOPOLOGY` in the model or SUPERUSER.

## 5.4 Grant and Revoke

The model should include permission grant and revoke actions:

- `GrantPermission(admin, role, resource, permission)`
- `RevokePermission(admin, role, resource, permission)`

Preconditions:

- `admin` has `AUTHORIZE` permission on the target resource, or is SUPERUSER;
- The permission requested to be granted applies to the target resource type;
- The role and resource exist.

The model need not implement the entire CQL permission applicability matrix, but must not allow obviously meaningless permission combinations to become successful authorizations, for example using `SELECT` as a function execution permission.

Permission modifications should affect authorization decisions for subsequent operations. Whether historical successful operations are legal should be judged by the authorization result recorded when the operation was executed, and should not be retroactively judged as unauthorized because of a later Revoke.

## 5.5 Unauthorized Operations

The model must include the following rejection branches:

- `RejectWrite`
- `RejectRead`
- `RejectMigrate`
- `RejectGrantOrRevoke`

Unauthorized writes must not change:

- write reception state;
- mutation set accepted by the coordinator;
- commit log of any replica;
- memtable or applied data of any replica;
- replica acknowledgment set;
- client write completion state;
- token range routing replica set;
- migration state.

Unauthorized reads must not change data, replica, routing, and migration states. They may only record the rejection result, or set the query result to empty and mark it as failed.

Unauthorized migrations must not change:

- current routing replica set;
- target replica set;
- streaming data;
- topology epoch;
- migration phase.

## 5.6 Historical Operation Record

At least the following should be retained:

- `lastWrite`
- `lastRead`
- `lastMigrate`
- `lastAuthChange`

Each successful or rejected record must contain at least:

- operation type;
- Principal；
- target table or token range;
- consistency level or migration type;
- `authorized`；
- `executed`；
- success or rejection result.

For successful operations, `authorized = TRUE` must indicate that authorization passed in the state where the operation occurred, rather than being recalculated based on future states.

---

## 6. Write Path Specification

## 6.1 Write Consistency Levels

The first version model has fixed support for:

- `ONE`
- `QUORUM`
- `ALL`

For a token range with replica count `N`:

- `RequiredWriteAcks(ONE, N) = 1`
- `RequiredWriteAcks(QUORUM, N) = floor(N / 2) + 1`
- `RequiredWriteAcks(ALL, N) = N`

Optional extension levels include TWO, THREE, LOCAL_ONE, LOCAL_QUORUM, EACH_QUORUM, and ANY, but the first version does not require implementing them.

In particular, `ANY` applies only to Cassandra write operations and can be satisfied by the coordinator node storing a hint. If the first version does not model a hint as an alternative acknowledgment for write completion, it must not disguise `ANY` as `ONE`.

## 6.2 Write Request States

It is recommended to represent the write processing state of each mutation as a finite enumeration:

- `None`: not yet accepted by the coordinator node;
- `Accepted`: the coordinator node has passed the authorization check and accepted the request;
- `Dispatched`: write requests have been issued to the current replica set;
- `Acknowledged`: sufficient replica acknowledgments have been received, and the coordinator node can return success to the client;
- `Rejected`: rejected due to authorization failure or an invalid request.

State can be modeled per mutation or per independent `WriteRequest`; however, it must be able to be associated with a unique mutation.

`Acknowledged` in this specification denotes an abstract commit state meaning 'the consistency level of this write request is satisfied and success can be returned to the client'; it does not mean that Cassandra has a single global transaction commit point, nor that all replicas have been persisted to SSTable.

## 6.3 ReceiveWrite

The preconditions of `ReceiveWrite(principal, coordinator, mutation, writeLevel)` include at least:

1. `principal`, `coordinator`, `mutation`, and `writeLevel` belong to the model definition domain;
2. the table, partition, and token range corresponding to the mutation are valid;
3. Principal has `MODIFY` permission on the target table;
4. the mutation is not yet in an accepted or completed state;
5. the current token range has a non-empty routing replica set.

Successful effects:

1. the mutation state enters `Accepted`;
2. record the coordinator node and write consistency level for this mutation;
3. add the mutation to `AcceptedMutations`;
4. Compute its owning keyspace, token range, and current routing replica set;
5. Save `authorized = TRUE` in the write-success history record;
6. In this action, the mutation must not be directly considered as acknowledged by all replicas.

## 6.4 DispatchWrite

`DispatchWrite(mutation)` sends the accepted mutation to its current routing replica set.

The official semantics are: regardless of the consistency level chosen, write operations are sent to all replicas; the consistency level only determines how many responses the coordinator node waits for before returning to the client.

Therefore, the model must satisfy:

- For a dispatched mutation, the target set equals the mutation's current routing replica set at dispatch time;
- A mutation must not be sent to only one replica merely because the write consistency level is ONE;
- The write consistency level only affects the acknowledgment threshold of the subsequent `CompleteWrite`.

The model does not need to explicitly represent each network message; `pendingWriteDelivery[mutation]` or an equivalent set may be used to represent pending delivery replicas.

## 6.5 ReplicaReceiveWrite: commit log and memtable

`ReplicaReceiveWrite(mutation, node)` indicates that a replica node has received the mutation and completed the local write steps within the scope of this model.

Preconditions:

1. The mutation has been accepted by the coordinator node;
2. The node belongs to the current write-target replica set of the mutation;
3. The node has not yet completed local application of the mutation.

The successful effects should include at least:

1. Record the mutation in the node's local `commitLog` abstract set;
2. Record the mutation in the node's `memtable` or local applied mutation set;
3. Add the mutation to the replica's `replicaApplied` set;
4. Generate the replica's eligibility to acknowledge to the coordinator node;
5. Do not apply any mutation that is not in `AcceptedMutations`.

Recommended state variables:

- `commitLog : Node -> SUBSET Mutation`
- `memtable : Node -> SUBSET Mutation`
- `replicaApplied : Node -> SUBSET Mutation`

And maintain:

- `memtable[node] ⊆ replicaApplied[node]`；
- `replicaApplied[node] ⊆ AcceptedMutations`；
- `commitLog[node] ⊆ AcceptedMutations`。

In this specification, a commit log record indicates that the node has placed the mutation into the local commit log write path. Because Cassandra's `commitlog_sync` can be configured as `batch` or `periodic`, the first version of the model does not automatically equate “recorded in the commit log” with “already fsynced to stable storage”.

If the subsequent model explicitly adds persistence semantics, then the following should be satisfied:

- In `batch` mode, the replica needs commit log fsync before contributing an acknowledgment to the client path;
- In `periodic` mode, acknowledgment before periodic fsync is allowed, so a crash may lose data within the most recent synchronization period.

If the first version does not model node crash and recovery, the `fsynced` state may be omitted, but this limitation must be explicitly stated in the model description.

## 6.6 ReplicaAck

`ReplicaAck(mutation, node)` indicates that the coordinator node receives a replica acknowledgment from node for mutation.

Precondition:

1. node has executed `ReplicaReceiveWrite`;
2. mutation already exists in this node's `replicaApplied[node]`;
3. node is a member of the write target set for this mutation;
4. node has not yet been counted in the acknowledgment set for this mutation.

Effects:

- `ackSet[mutation] := ackSet[mutation] ∪ {node}`。

Recommended constraints:

- `ackSet[mutation] ⊆ WriteTargets[mutation]`；
- `ackSet[mutation] ⊆ {node : mutation ∈ replicaApplied[node]}`。

Therefore, “a replica that has not recorded or applied the mutation” is not allowed to produce an acknowledgment.

## 6.7 CompleteWrite

`CompleteWrite(mutation)` is the action by which the coordinator node returns write success to the client.

Precondition:

1. mutation has been accepted and distributed;
2. `Cardinality(ackSet[mutation]) >= RequiredWriteAcks(writeLevel[mutation], N)`；
3. `N` is the size of the replica set used for this write;
4. The request principal has already passed authorization check upon receipt.

Effects:

1. mutation state enters `Acknowledged`;
2. mutation is added to `CommitFrontier(writeLevel)` or an equivalent completed write set;
3. record the most recent successful write;
4. do not modify the mutation content on the replica;
5. It is not required that all replicas have received this mutation, unless the write consistency level is ALL.

## 6.8 Accepted but not yet completed writes

Cassandra replicas may have already applied a mutation, while the coordinator node has not yet returned success to the client. For example, some replicas have already processed the write, but the QUORUM or ALL acknowledgment threshold has not yet been reached.

Therefore, the model must distinguish:

- `AcceptedMutations`: accepted by the coordinator node;
- `replicaApplied[node]`: a replica has applied it locally;
- `AcknowledgedMutations`: the coordinator node has confirmed success according to the selected write consistency level.

Read semantics should be based on the versions already applied in the replicas that actually respond to reads, and cannot simply assume that “only writes acknowledged successful to the client can possibly be read”.

If “concurrent reads while a write has not completed” is prohibited in order to compress the first version state space, that restriction must be explicitly written into the model assumptions, and must not be expressed as Cassandra's general semantics.

## 6.9 Flush and SSTable

Cassandra flushes the memtable to an immutable SSTable. The first version model may use the following abstraction:

- `FlushMemtable(node)` migrates part or all of `memtable[node]` to `sstableData[node]`;
- flush must not lose a mutation;
- after flush, the mutation still belongs to `replicaApplied[node]`;
- The physical details of cleaning up the corresponding commit log are not modeled.

Suggested relations:

- `replicaApplied[node] = memtable[node] ∪ sstableData[node]`, or at least `replicaApplied[node]` covers both;
- flush and compaction must not change the LWW winning version of any data item.

---

## 7. Replica Propagation and Final Synchronization

## 7.1 Replicas May Temporarily Diverge

Cassandra is an eventually consistent system. Different replicas may temporarily hold different versions, and some replicas may not yet have received a mutation.

The model must allow:

- a mutation is applied by only some replicas;
- replicas differ in the current LWW winning version for the same DataItem;
- under a low write consistency level, the coordinator node has confirmed success, but the remaining replicas have not yet synchronized;
- during migration, the applied data of the old replica and the target replica are temporarily different.

The model must not require all replicas to be immediately identical in every state.

## 7.2 Unified synchronization action

All of the following Cassandra mechanisms can be uniformly abstracted as replica catch-up actions in the first version model:

- hinted handoff；
- read repair；
- anti-entropy repair；
- streaming；
- Resend after node recovery;
- Data flow during range movement.

The unified action may be called:

- `SyncReplica(mutation, node)`；
- or `SynchronizeReplica(source, target, mutation)`.

Preconditions:

1. mutation has been accepted by the coordinator node;
2. The target node corresponds to the mutation's current replica, a migration target replica, or a replica allowed to receive recovery data;
3. The target node has not yet applied the mutation;
4. The mutation exists on the source side or in the pending synchronization set.

Effects:

1. mutation is added to the target node's `commitLog` or equivalent receiving state;
2. mutation is added to the target node's `replicaApplied`;
3. If the synchronization is triggered by a read, it may additionally be recorded as read repair;
4. The version of mutation must not be modified;
5. The target replica must not obtain an unaccepted mutation.

The first version may not distinguish the specific message formats of hint, repair, and streaming; but it must preserve the safety relation that "synchronization will not cross the accepted write boundary".

## 7.3 Final convergence condition

Under the following environmental assumptions, replicas can eventually converge:

1. The target replica remains reachable;
2. Synchronization actions are no longer permanently discarded;
3. The relevant token range no longer migrates indefinitely;
4. There are no writes to the same data item that are generated infinitely and whose versions continuously increase;
5. Repair, hint replay, or equivalent synchronization actions for lagging replicas will eventually occur.

Under these assumptions, for every accepted mutation of a stable token range, the current routing replicas should eventually apply the mutation, or at least apply a winning version of the same DataItem no lower than that mutation.

This property is a liveness property, requires fairness assumptions, and cannot be treated only as a safety invariant without fairness conditions.

---

## 8. Consistent Read Specification

## 8.1 Read Consistency Levels

The first version of the model has fixed support:

- `ONE`
- `QUORUM`
- `ALL`

For a token range whose current replica count is `N`:

- `RequiredReadResponses(ONE, N) = 1`
- `RequiredReadResponses(QUORUM, N) = floor(N / 2) + 1`
- `RequiredReadResponses(ALL, N) = N`

The read consistency level indicates the number of replica responses that the coordinator node must obtain before completing a read request; it does not indicate that all replicas have the same version at the beginning of the read.

## 8.2 ReadRequest

Each read request should contain at least:

- request principal;
- coordinator node;
- table；
- partition；
- set of DataItems to read;
- read consistency level;
- routing replica set used at the beginning of the request or during request processing;
- actual responding replica set;
- local winning version returned by each responding replica;
- final resolved result;
- authorization result and execution result.

To avoid mixing query algorithm issues into the consistency model, the first version may restrict reads to:

1. point read of a single DataItem; or
2. complete read of a fixed DataItem set within a given partition.

If the model adopts fixed DataItem set reads, a successful read should return the complete logical result obtained on that set by LWW resolution from the responding replicas, and must not arbitrarily return a subset thereof.

## 8.3 DispatchRead

Preconditions for `DispatchRead(readRequest)`:

1. the request principal has `SELECT` permission on the target table;
2. the target partition is mapped to a token range;
3. a routing replica set exists for the current token range;
4. The read request has not yet been executed or completed.

The coordinator node typically sends read requests only to replicas sufficient to satisfy the consistency level; in the case of speculative retry, it may additionally read replicas.

The first version of the model may allow the responding replica set to be any subset of the routing replica set, provided that the number of responses meets the read consistency level upon eventual success. It must not require the response set to be fixed equal to a particular node order.

## 8.4 ReplicaReadResponse

`ReplicaReadResponse(readRequest, node)` indicates that a replica returns a local read result.

Preconditions:

1. node belongs to the routing replica set used for this read request;
2. node is able to respond to this request;
3. node has a local `replicaApplied` state for the target DataItem, or its local state indicates that the item does not exist;
4. node has not yet produced a duplicate response for this read request.

Effects:

1. For each queried DataItem, return the version with the maximum LWW among the mutations currently applied at node;
2. If the local maximum version is a tombstone, the response is a deletion state;
3. Mutations not applied by node must not be returned;
4. Add node to the `readResponseSet` of this read request.

## 8.5 CompleteRead

Preconditions for `CompleteRead(readRequest)`:

1. `Cardinality(readResponseSet[readRequest]) >= RequiredReadResponses(readLevel, N)`；
2. The request principal passes SELECT authorization at execution time;
3. Each replica response included in the result comes from a valid routing replica;
4. For all target DataItems, the coordinator node has collected the necessary responses and completed LWW resolution.

Effects:

1. For each read DataItem, select the version with the maximum LWW among the versions returned by all participating responding replicas;
2. If the maximum version is a tombstone, the normal value of the item is not returned in the result;
3. Save the complete read result;
4. Record `lastRead.authorized = TRUE`;
5. Optionally create read repair candidates, but read repair itself should be an independent state advancement action.

## 8.6 Semantics of ONE, QUORUM, and ALL

### ONE

ONE requires only one replica to respond.

Therefore:

- A read may read an older version from a lagging replica;
- A read is not guaranteed to intersect with a previous low-consistency write;
- The read result must still be the LWW winning version of the data applied by the actual responding replica;
- A read must not return a mutation not applied by that replica.

### QUORUM

QUORUM requires more than half of the replicas to respond.

If both the write and the read use QUORUM on the same stable replica set, the read quorum and the write quorum must intersect.

If a mutation has been acknowledged by a QUORUM write, the response set of a subsequent QUORUM read intersects the write acknowledgment set. The replicas in that intersection have at least applied that mutation. Therefore, the LWW result of the read should be:

- the mutation itself; or
- a higher-version mutation on the same DataItem; or
- a higher-version tombstone.

Must not return a fabricated version higher than the versions visible in all replicas participating in the read response.

### ALL

ALL requires all replicas in the current routing replica set to respond.

For a write ALL, the coordinator must receive acknowledgments from all current replicas before returning success to the client.

For a read ALL, the coordinator must receive responses from all current replicas before completing the read.

The success of ALL depends on all current replicas being able to respond; therefore, when nodes are unavailable, ALL may fail to complete. The model should not incorrectly relax the response condition of ALL in order to guarantee liveness.

## 8.7 Intersection Property of R + W > N

Under the following conditions:

1. The write and the read target the same token range;
2. The write and the read use the same stable routing replica set;
3. The size of the write acknowledgment set is `W`;
4. The size of the read response set is `R`;
5. `R + W > N`；
6. The write has completed;
7. No higher-version mutation overwrites the data item;

The read response set and the write acknowledgment set must have a nonempty intersection. This property can be used to verify the quorum intersection semantics described in Cassandra documentation.

The model should express this property as a conditional safety property, and must not unconditionally claim that any QUORUM read always returns the 'globally last client write'. Reasons include:

- Concurrent or subsequent higher-version mutations may exist;
- Token range migration may occur;
- Consistency levels with different datacenter scopes may be used;
- The value actually read is the LWW-resolved value;
- Cassandra is an eventually consistent system and does not provide global linearizable semantics for ordinary writes.

---

## 9. Data Range Migration Specification

## 9.1 Unified Migration Abstraction

The following Cassandra operations all involve token range data movement:

- bootstrap: a new node joins the ring and receives the token range data it will be responsible for;
- decommission: a live node leaves, and the original ranges are transferred to other nodes;
- remove: a dead node is removed, and the remaining replicas take on the data;
- move: a single-token node changes its ring position;
- replace: a new node replaces a dead node;
- rebuild: data is streamed from other nodes;
- repair: range data is synchronized between replicas.

The first version of the model abstracts bootstrap, decommission, move, and replace uniformly as `RangeMigrate`, but the migration type must be preserved:

- `Bootstrap`
- `Decommission`
- `Move`
- `Replace`

Optional extensions:

- `Remove`
- `Rebuild`
- `Repair`

Each migration targets a single `(Keyspace, TokenRange)` or a finite token range set. To control the state space, it is recommended that the first version allow only one token range to be in a migration state at a time.

## 9.2 Routing to a Replica Set Rather Than a Single Owner

Cassandra uses multiple replicas for a token range rather than a single data owner.

Therefore, the model must not use the semantics 'a shard can have only one active owner' to replace Cassandra's replication semantics.

Use:

- `oldRoutingReplicas[keyspace][range]`
- `targetRoutingReplicas[keyspace][range]`
- `routingReplicas[keyspace][range]`

Where:

- `oldRoutingReplicas` is the set of replicas before migration starts;
- `targetRoutingReplicas` is the set of replicas that should serve the range after migration completes;
- `routingReplicas` is the set of replicas used for current request routing.

In the stable phase:

- `routingReplicas = oldRoutingReplicas`；
- After migration ends, `routingReplicas = targetRoutingReplicas`.

Old nodes may still retain redundant data after migration. The official documentation explicitly states that, for safety, Cassandra does not automatically delete old data on nodes that have lost ranges after range movement; cleanup must be performed after confirming that the new nodes are healthy. Therefore, the model must not treat “old nodes still hold replica data” as violating unique ownership.

## 9.3 Migration Phases

The following phases are recommended:

- `Stable`: no migration is in progress, and the current routing replica set serves requests normally;
- `Streaming`: the target replica is receiving range data from the source replica or other existing replicas;
- `ReadyToActivate`: the target replica has reached the safe switchover condition;
- `Activated`: the routing replica set has switched to the target set;
- `CleanupEligible`: the switchover is complete, old replicas may retain redundant data, and cleanup can be performed after operational confirmation;
- `Stable`: returns to the stable state after cleanup or when cleanup is not required.

To control the state space of the first version, `ReadyToActivate` can also be represented as a derived predicate within the `Streaming` state instead of being stored separately.

## 9.4 StartMigrate

Preconditions for `StartMigrate(principal, keyspace, range, migrateKind, targetReplicas)`:

1. Principal has `MANAGE_TOPOLOGY` or SUPERUSER permission;
2. The range is currently in `Stable`;
3. The current routing replica set is non-empty;
4. The target replica set is non-empty;
5. The target replica set conforms to the replication factor or predefined topology targets in the model;
6. For replace, the target node represents the configuration replacing the original node; for bootstrap, the target set usually contains a new node; for decommission, the target set does not contain the departing node;
7. Two independent migrations are not allowed to exist for the same range at the same time.

Effects:

1. Record `migrateKind`;
2. Save `oldRoutingReplicas`;
3. Save `targetRoutingReplicas`;
4. Set the phase to `Streaming`;
5. Create the migration-safe data set for this range;
6. Keep `routingReplicas` as the old set until activation;
7. Record `lastMigrate.authorized = TRUE`.

## 9.5 MigrateFrontier

For a `(keyspace, range)` in migration, `MigrateFrontier` represents the data boundary that the target replica must catch up to before the switch.

The first version should adopt a conservative set definition:

- `MigrateFrontier(keyspace, range)` includes at least all mutations within the range that have already entered `WriteFrontier`;
- For mutations that have completed write-consistency confirmation, they must be included unconditionally;
- For mutations that have already been applied on the old replica but have not yet completed client confirmation, if the mutation has been accepted by the coordinating node, it should also be included in the conservative model to avoid missing data that has already begun propagating during the migration switch.

Due to LWW semantics, the actual implementation can recover the winning version by streaming the current SSTable, memtable, or their equivalent state. For ease of verification, the first-version model may directly require the target replica to cover the relevant mutation set within the migration range, or at least have, for each DataItem, a local winning version no lower than the highest version in MigrateFrontier.

The latter “covering by the highest version per DataItem” is closer to LWW semantics, but has higher implementation complexity. The first version prioritizes a conservative abstraction with full coverage of the mutation set.

## 9.6 AdvanceMigrate

`AdvanceMigrate(keyspace, range, source, target, mutation)` represents streaming or equivalent synchronization progress.

Preconditions:

1. The range is in `Streaming`;
2. target belongs to `targetRoutingReplicas`;
3. mutation belongs to the `MigrateFrontier` of this range;
4. source belongs to the old replica set, another replica set containing this mutation, or a legal synchronization source allowed by the model;
5. target has not yet applied this mutation.

Effects:

1. target adds the mutation to its local receiving state;
2. target adds the mutation to `commitLog[target]`, `memtable[target]`, or the equivalent `replicaApplied[target]`;
3. Record that the target has replicated the data;
4. Do not change the current `routingReplicas`;
5. Do not delete the data of old replicas.

The model may abstract one `AdvanceMigrate` as copying the entire `MigrateFrontier`, or may copy mutation by mutation. If one-time copying is adopted, it should be clear that this action represents the completion of full streaming, rather than that Cassandra's actual network transfer is completed in a single step.

## 9.7 New Writes During Migration

New mutations may continue to arrive during migration. The model must avoid the following errors:

- Copy the old snapshot first;
- Generate new writes during migration;
- Do not resynchronize;
- Switch directly to the target replica set that does not contain the new writes.

Therefore, one of the following two safe abstractions should be chosen:

1. Dynamic catch-up abstraction: recompute `MigrateFrontier` before each activation preparation; target replicas must cover the current Frontier;
2. Dual-write abstraction: send new writes to both the old replica set and the target replica set during migration, and check the confirmation state of target replicas before activation.

The first version recommends adopting the dynamic catch-up abstraction because it is easier to combine with the unified synchronization action:

- After a new mutation enters `WriteFrontier`, `MigrateFrontier` automatically expands;
- If the target has not yet covered the newly added mutation, `ActivateMigrate` cannot be executed;
- Subsequent `AdvanceMigrate` synchronizes the newly added mutation to the target;
- Switching is allowed only when the target covers the latest `MigrateFrontier`.

## 9.8 ActivateMigrate

`ActivateMigrate(keyspace, range)` represents switching request routing from the old replica set to the target replica set.

Preconditions must include:

1. The migration phase is `Streaming` or `ReadyToActivate`;
2. For each target node, the target replica has covered the `MigrateFrontier` of that range;
3. `targetRoutingReplicas` satisfies the replication factor or the predefined target topology in the model;
4. Each node in the target replica set can serve as a new routing replica;
5. There are currently no accepted mutations not included in MigrateFrontier;
6. The request routing switch is completed as an atomic action in the model.

Effects:

1. `routingReplicas[keyspace][range] := targetRoutingReplicas[keyspace][range]`；
2. Set the migration phase to `Activated`;
3. Update `topologyEpoch` or an equivalent topology version;
4. Retain existing data in the old replica and do not automatically delete it;
5. Make subsequent read/write requests use the new routing replica set.

This action is a critical boundary for migration safety. When the target replica has not reached MigrateFrontier, this action must never be allowed.

## 9.9 FinishMigrate and Cleanup

`FinishMigrate` preconditions:

- range is already in `Activated`;
- Routing is stably using the target replica set.

Effects:

- The migration phase enters `CleanupEligible` or returns directly to `Stable`;
- Retain redundant data in the old replica;
- Clean up temporary migration records, but must not clean up applied data on the new routing replica.

`CleanupOldRangeData(node, range)` is an optional action. Its preconditions include at least:

1. range has completed activation;
2. node does not belong to the current routing replica set;
3. The target replica has satisfied migration safety conditions;
4. cleanup does not delete data required by the current routing replica.

This action only represents redundant data cleanup after operations confirmation. It should not be modeled as automatically occurring during migration activation.

## 9.10 Special notes on Replace

The official documentation states: when replacing a dead node, the replacement node receives data from the remaining nodes through bootstrap; if the node offline time or the replacement process exceeds conditions such as hint window, the replacement node may miss writes, and repair must be performed to restore consistency.

The first version model does not need to represent hint window and IP address differences. But it should adopt conservative migration safety rules:

- The target replica of replace must cover `MigrateFrontier` before activation;
- If the model explicitly allows the replacement node to miss writes during migration, repair/sync must be allowed to catch up before entering stable state;
- The replacement node must not be treated as the only serviceable new replica before migration safety conditions are satisfied.

---

## 10. Frontier Layered Definitions

## 10.1 WriteFrontier

`WriteFrontier` denotes the set of mutations accepted by a legitimate coordinated write path.

Defining semantics:

- The mutation has passed write permission checks;
- The coordinating node has accepted the mutation;
- The mutation has been associated with the target token range and the set of write target replicas;
- The mutation has not yet been rejected.

Recommended definition:

- `WriteFrontier = AcceptedMutations`

WriteFrontier does not denote:

- All replicas have received the mutation;
- Any replica has acknowledged;
- The client has received write success;
- The mutation has been flushed to an SSTable;
- The mutation is already available on the migration target replica.

## 10.2 LocalLogFrontier

`LocalLogFrontier(node)` denotes the set of mutations that a node has written to the local commit log abstraction.

Recommended definition:

- `LocalLogFrontier(node) = commitLog[node]`

Must satisfy:

- For any node, `LocalLogFrontier(node)` is a subset of `WriteFrontier`.

This Frontier indicates that the local write path has recorded the mutation; it does not indicate that the mutation has completed fsync in periodic commit log mode.

## 10.3 ReplicaFrontier

`ReplicaFrontier(node)` denotes the set of mutations that node has currently applied locally and that can participate in read responses or subsequent synchronization.

Recommended definition:

- `ReplicaFrontier(node) = replicaApplied[node]`

Must satisfy:

- `ReplicaFrontier(node) ⊆ WriteFrontier`；
- A replica's acknowledgment of a mutation may only be based on the mutation belonging to that replica's ReplicaFrontier;
- The replica's currently readable version is derived from the LWW maximum mutation for the same DataItem in ReplicaFrontier.

## 10.4 CommitFrontier

`CommitFrontier(level)` denotes the set of mutations that the coordinating node has completed according to the specified write consistency level and successfully acknowledged to the client.

Recommended definition:

- `CommitFrontier(level) = { m ∈ WriteFrontier : writeLevel[m] = level /\ WriteCompleted[m] }`

where `WriteCompleted[m]` requires:

- `Cardinality(ackSet[m]) >= RequiredWriteAcks(level, ReplicaCount[m])`。

Must satisfy:

- `CommitFrontier(level) ⊆ WriteFrontier`；
- For any `m ∈ CommitFrontier(level)`, every replica in the acknowledgment set has already included `m` in its ReplicaFrontier;
- Every mutation in `CommitFrontier(ALL)` has been fully acknowledged by the current write target set.

CommitFrontier represents the write-success boundary observed by clients, and should not be misunderstood as Cassandra's global transaction commit log.

## 10.5 QueryFrontier

`QueryFrontier(readRequest)` represents the data boundary that the read request can legally resolve under the current actual responding replica set.

For a read request and a queried DataItem, QueryFrontier should be:

1. among the actual responding replicas for the read request;
2. the local winning mutation derived from `ReplicaFrontier(node)`;
3. the final winning mutation obtained after LWW resolution of all versions returned by the responses.

Therefore, QueryFrontier is a boundary dependent on the specific read request, read consistency level, and responding replica set, rather than a single global set.

For `ONE`, QueryFrontier comes from one actual responding replica.

For `QUORUM`, QueryFrontier comes from a responding replica set no smaller than quorum.

For `ALL`, QueryFrontier comes from responses from all current routing replicas.

QueryFrontier need not be a subset of CommitFrontier. A mutation that has been applied locally by a replica but not yet fully acknowledged to the client may appear in a read response. This distinction is part of Cassandra's asynchronous multi-replica write model.

However, QueryFrontier must depend only on ReplicaFrontier and must not contain any mutation that has not entered WriteFrontier.

## 10.6 MigrateFrontier

`MigrateFrontier(keyspace, range)` represents the data boundary that target replicas must cover before routing switch for the token range.

Recommended definition:

- all relevant mutations within the range that have entered WriteFrontier;
- at least all mutations whose write acknowledgments are complete;
- newly accepted mutations during migration automatically extend this Frontier.

Must satisfy:

- `MigrateFrontier(keyspace, range) ⊆ WriteFrontier`；
- Before activation, all target routing replicas must cover MigrateFrontier, or, for each DataItem, have a winning state with a version no lower than the highest version in that Frontier;
- ActivateMigrate must not occur when the target has not reached MigrateFrontier.

## 10.7 FinalQueryFrontier

`FinalQueryFrontier(readRequest)` represents the logical result boundary that a successful read can ultimately return.

It is the intersection of the following conditions:

1. The request principal has SELECT permission on the target table;
2. The data is served by an actual legitimate replica;
3. The response version belongs to the ReplicaFrontier of the corresponding replica;
4. The response version belongs to WriteFrontier;
5. The number of read responses satisfies the consistency level of the request;
6. The coordinator node resolves the responses using LWW rules;
7. The routing replica set for the current token range has been safely switched according to the migration phase;
8. If the range is migrating, the routing set used by this read is compatible with the current migration state.

Conceptually:

- `FinalQueryFrontier = AuthorizationBoundary ∩ QueryFrontier ∩ MigrationSafeBoundary`

Here, MigrationSafeBoundary does not require old replicas to physically delete data immediately after migration, but requires that the currently routed replica set already satisfies the migration activation condition.

## 10.8 Frontier chain

The main Frontier relationships in the Cassandra model are:

- `LocalLogFrontier(node) ⊆ WriteFrontier`
- `ReplicaFrontier(node) ⊆ WriteFrontier`
- `CommitFrontier(level) ⊆ WriteFrontier`
- The replicas in `ackSet[m]` must contain `m` in their ReplicaFrontier
- `QueryFrontier(readRequest)` is derived only from the ReplicaFrontier of the replicas that participate in responses
- `MigrateFrontier(keyspace, range) ⊆ WriteFrontier`
- After activation, the ReplicaFrontier of the new routing replica covers MigrateFrontier
- `ReadResult(readRequest)` must equal or be constrained by the LWW resolution result of `FinalQueryFrontier(readRequest)`

Here, QueryFrontier and CommitFrontier should not be forced into a simple subset relationship; they respectively represent "replica-local readable boundary" and "client write success boundary".

---

## 11. Safety properties to be verified

## 11.1 TypeOK

All variables always belong to declared types, including:

- Principal、Role、Node、Keyspace、Table、Partition、TokenRange、Mutation；
- permission mapping;
- mapping from token range to replica set;
- mutation state;
- commit log、memtable、SSTable、ReplicaFrontier；
- acknowledgment set;
- Read response set and read result;
- Migration state, source replica set, target replica set, and replicated data;
- All Frontier.

## 11.2 RoleHierarchySafety

Role grant relationships must remain acyclic.

For any role, it must not regain itself through direct or indirect role grants.

## 11.3 AuthorizationSafety

Any successful operation must be authorized at execution:

- Successful write has MODIFY;
- Successful read has SELECT;
- Successful grant/revoke has AUTHORIZE;
- Successful migration has MANAGE_TOPOLOGY or SUPERUSER;
- Unauthorized operations can only enter the reject branch.

After Revoke, `authorized = TRUE` records of historically successful operations should not be invalidated.

## 11.4 RoutingSafety

For each stable token range:

- The routing replica set is non-empty;
- The number of routing replicas matches the replication factor, unless the model explicitly enters a restricted operational exception state;
- Read/write requests are sent only to the routing replica set used by that request;
- Replica acknowledgments cannot come from nodes outside the target set of that mutation.

## 11.5 WritePathSafety

For any mutation:

1. Unauthorized mutations do not enter WriteFrontier;
2. Mutations that have not entered WriteFrontier must not enter any node's commit log;
3. Mutations that have not entered WriteFrontier must not enter any ReplicaFrontier;
4. Replica acknowledgments must have local application first;
5. Completed write acknowledgments must have sufficient replica acknowledgments first;
6. The write completion threshold must match the write consistency level of that mutation;
7. When write ALL completes, all target replicas have acknowledged;
8. commit log, memtable flush, and compaction must not create new mutations.

## 11.6 ReplicaSafety

For any node:

- `ReplicaFrontier(node) ⊆ WriteFrontier`；
- `LocalLogFrontier(node) ⊆ WriteFrontier`；
- The local LWW winning version of a replica must come from its ReplicaFrontier;
- Synchronization actions may only propagate mutations that have entered WriteFrontier;
- Replica synchronization must not change the version, DataItem, or tombstone properties of a mutation.

## 11.7 ReadConsistencySafety

For any successful read:

1. The reading principal has SELECT permission at the time the operation is executed;
2. The number of responding replicas meets the requirement of the read consistency level;
3. Each responding replica belongs to the routing replica set used by the request;
4. Each responding value comes from the ReplicaFrontier of that replica;
5. The returned result equals the result of LWW resolution over the actual responding versions;
6. No fictitious mutation that does not exist in any responding replica may be returned;
7. If the result is a normal value, the winning mutation for that value must not be overwritten by any higher-version mutation that participated in the response;
8. If the winning mutation is a tombstone, the read must not incorrectly return an old normal value.

## 11.8 QuorumIntersectionSafety

Under a stable replica set, if:

- A mutation has successfully completed at write level W;
- A subsequent read has successfully completed at read level R;
- `W + R > N`；
- Both target the same token range;
- No higher-version mutation exists for the same DataItem;

Then the read response set and the write acknowledgment set must intersect, and the read result must observe that mutation or a higher version.

This property should be checked against specific combinations such as QUORUM/QUORUM, ALL/ONE, and ONE/ALL.

## 11.9 MigrateSafety

For any range under migration:

1. The same range has at most one active migration at a time;
2. The old replica set saved at StartMigrate equals the routing replica set before migration;
3. Before ActivateMigrate, the current routing replica set remains the old set;
4. ActivateMigrate must not occur when the target replicas do not cover MigrateFrontier;
5. After ActivateMigrate, the routing replica set must equal the target replica set;
6. After activation, the new routing replica must retain the MigrateFrontier within the migration scope;
7. FinishMigrate and cleanup must not delete mutations required by the current routing replica;
8. The old replica retaining redundant data does not constitute an error;
9. If new writes expand MigrateFrontier during migration, the target must catch up before activation;
10. Mutations that have completed write acknowledgment must not be lost due to routing switches of bootstrap, decommission, move, or replace.

## 11.10 FrontierSafety

The following relationships must be verified in combination:

- `LocalLogFrontier(node) ⊆ WriteFrontier`
- `ReplicaFrontier(node) ⊆ WriteFrontier`
- `CommitFrontier(level) ⊆ WriteFrontier`
- Any acknowledged replica includes the corresponding mutation in ReplicaFrontier
- QueryFrontier is derived only from the ReplicaFrontier of replicas that actually responded to reads
- MigrateFrontier is a subset of WriteFrontier
- Before activation, the target replicas cover MigrateFrontier
- Successful read results satisfy FinalQueryFrontier

## 11.11 NoInventedData

Any mutation entering the following sets must be traceable to an authorized and accepted write:

- commitLog；
- memtable；
- SSTable abstract state;
- ReplicaFrontier；
- ackSet；
- read response；
- read result；
- migrate copied data；
- repair or hint abstract synchronization data.

This property prevents the model from fabricating data due to missing state constraints.

---

## 12. Liveness properties requiring fairness support

The following properties should not be treated as pure safety invariants. They require fairness assumptions to be imposed on synchronization, network delivery, migration actions, or node availability.

## 12.1 Writes eventually complete

If:

1. the mutation has been legally accepted;
2. the required number of target replicas eventually remain responsive;
3. write message delivery and replica acknowledgment actions satisfy weak fairness;

then the mutation can eventually reach the `Acknowledged` state at the corresponding write consistency level.

For ALL, all target replicas must eventually respond.

## 12.2 Replica eventual convergence

If:

1. token range is stable;
2. some mutation has entered WriteFrontier;
3. relevant replicas are eventually reachable;
4. SyncReplica, repair, or hint replay is not permanently starved;
5. no infinitely increasing new-version writes exist for the same data item;

then all current routing replicas eventually contain that mutation, or contain a winning mutation with a higher version of that DataItem.

## 12.3 Migration eventual completion

If:

1. RangeMigrate has started;
2. source and target nodes are eventually reachable;
3. streaming or synchronization actions are scheduled fairly;
4. no new mutations are generated indefinitely that prevent the target from catching up;
5. the target replica set continuously satisfies the target topology constraints;

then MigrateFrontier is eventually covered by the target, and the migration can eventually Activate and enter a stable state.

## 12.4 Read eventual completion

If:

1. the read request has passed authorization;
2. the number of routing replicas required to satisfy its read consistency level eventually respond;
3. read request dispatch and response processing are scheduled fairly;

then the read request can eventually complete.

This property does not mean that Cassandra is always available for ALL or QUORUM levels under network partitions or node failures; it only states that under the condition that enough replicas can respond and scheduling is fair, the model will not be permanently blocked without reason.

---

## 13. Official documentation basis and scenario traceability

| Modeling scenario | Official documentation basis | Adopted specification semantics |
|---|---|---|
| Partitioning, token ring, token range, replica selection | 《Dynamo and Tunable Consistency》 | Cassandra uses consistent hashing and a token ring; keys map to tokens, and multiple distinct physical nodes are selected along the ring as replicas; token ranges map to the same physical replica set. |
| vnode and physical node | 《Dynamo and Tunable Consistency》 | A physical node may own multiple tokens; the model may abstract nodeTokens, but does not validate the token allocation algorithm. |
| Multi-master replicas and LWW | 《Dynamo and Tunable Consistency》 | Each replica owning a key can independently accept mutations; mutations carry timestamps; conflicts for the same data item are resolved according to LWW rules; deletes also participate in versioning. |
| keyspace, table, partition, row | 《Architecture Overview》 | A keyspace is a replication configuration container; tables are partitioned by partition key; a single partition is the core high-performance access unit. |
| Cross-partition transactions are not modeled | 《Architecture Overview》；《Dynamo and Tunable Consistency》 | Cassandra does not support cross-partition transactions or distributed joins; the first version only models single-partition reads and writes. |
| commit log, memtable, SSTable write path | 《Storage Engine and Write Path》 | Writes are first recorded in the local commit log, then written to the memtable, and may later be flushed to an SSTable; the commit log is used for crash recovery. |
| periodic and batch commit log synchronization | 《Storage Engine and Write Path》 | In batch mode, writes are not acknowledged before the commit log fsync; in periodic mode, writes may be acknowledged first and synchronized periodically. The first version may omit modeling crashes, but must not unconditionally equate commit log records with fsync persistence. |
| Write sending and write consistency level | 《Dynamo and Tunable Consistency》 | Write operations are sent to all replicas; the consistency level determines how many responses the coordinating node waits for; ONE, QUORUM, and ALL correspond to 1, a majority, and all replicas, respectively. |
| Read consistency level | 《Dynamo and Tunable Consistency》 | The read coordinating node typically sends read requests to enough replicas to satisfy the consistency level; the response conditions for ONE, QUORUM, and ALL are defined by the replica count. |
| R + W > N | 《Dynamo and Tunable Consistency》 | When the read and write replica sets intersect, acknowledged writes are usually visible to subsequent reads; the model verifies this as a conditional property under stable replica sets and LWW conditions. |
| Eventual consistency and replica synchronization | 《Dynamo and Tunable Consistency》；《Guarantees and Eventual Consistency》 | Cassandra allows replicas to diverge temporarily and uses read repair, hinted handoff, anti-entropy repair, and so on to advance convergence; anti-entropy repair is used to guarantee eventual consistency. |
| role, permission inheritance, and permission resource hierarchy | 《Database Roles》 | Cassandra uses roles; roles may inherit other roles; the role graph is acyclic; permissions act on levels such as all keyspaces, keyspace, table, and propagate downward. |
| SELECT, MODIFY, and AUTHORIZE permissions | 《Database Roles》 | SELECT controls reads; MODIFY controls INSERT, UPDATE, DELETE, and TRUNCATE; AUTHORIZE controls GRANT and REVOKE. |
| Authorization enablement and AllowAll mode | 《Security》 | AllowAllAuthenticator performs no authentication; AllowAllAuthorizer performs no permission checks; after CassandraAuthorizer is enabled, permissions default to a whitelist and unauthorized requests are rejected. |
| Permission cache and dynamic permission changes | 《Security》；《Database Roles》 | Permission modifications become visible to existing sessions, but may be affected by cache refresh; the first version abstracts the authorization view as effective permissions at operation time and does not model cache latency. |
| bootstrap | 《Adding, replacing, moving and removing nodes》 | After a new node is assigned tokens, it streams data for the ranges it will be responsible for from existing replicas; default consistent range movement requires consistent transfer from the current primary replicas. |
| decommission, remove | 《Adding, replacing, moving and removing nodes》 | decommission transfers a node's ranges to other nodes and streams from the departing node; remove restores data for a dead node from the remaining replicas. |
| move | 《Adding, replacing, moving and removing nodes》 | A single-token node can perform move; cleanup may be needed after move. |
| replace | 《Adding, replacing, moving and removing nodes》 | A replacement node bootstraps data from other nodes; under some replacement timings, writes may be missed, and repair is needed to restore consistency. |
| streaming | 《Improved Streaming》 | streaming is used for repair, host replacement, range movement, bootstrap, rebuild, and cluster expansion; the first version abstracts it as the target replica catching up to MigrateFrontier. |
| cleanup does not automatically delete old data | 《Adding, replacing, moving and removing nodes》 | After range movement, Cassandra does not automatically delete old data on nodes that lost ranges; cleanup must be run after confirming that the new nodes are healthy. |
| Avoid concurrent range movement | 《Dynamo and Tunable Consistency》 | Cassandra avoids unnecessary concurrent range movement because it may break monotonic consistency and even cause data loss; the first version limits each range to at most one migration at a time. |

---

## 14. Suggested subsequent module partitioning

When generating the subsequent TLA+ model, the following module order is recommended. This order represents static dependency relationships, not runtime action order.

### 14.1 CassandraCore

Responsibilities:

- Define constant sets: Principals, Roles, Nodes, Keyspaces, Tables, Partitions, TokenRanges, DataItems, Mutations;
- Define enumerations: write state, migration state, read/write consistency level, permission type, migration type;
- Define static mappings: tableKeyspace, itemTable, itemPartition, partitionRange, mutationItem, mutationVersion, nodeTokens;
- Define replica topology constants or initial routing replica mapping;
- Define LWW version comparison;
- Define core type constraints and static consistency conditions.

### 14.2 CassandraAuth

Responsibilities:

- Define authorizationEnabled;
- Define role grant graph;
- Define direct permissions and effective permissions;
- Define permission checks for SELECT, MODIFY, AUTHORIZE, MANAGE_TOPOLOGY;
- Define GrantPermission, RevokePermission;
- Define authorization history records;
- Define common authorization semantics for denied operations.

### 14.3 CassandraWrite

Responsibilities:

- Define mutation write state;
- Define WriteFrontier;
- Define coordinator node receiving write requests;
- Define write distribution targets;
- Define commitLog, memtable, SSTable abstract states;
- Define ReplicaReceiveWrite, ReplicaAck, CompleteWrite;
- Define CommitFrontier;
- Define optional abstraction of FlushMemtable;
- Define safety properties of the write path.

### 14.4 CassandraReplica

Responsibilities:

- Define ReplicaFrontier;
- Define the replica-local LWW winning version;
- Define SyncReplica;
- Define the unified catch-up abstraction for repair, hint replay, and read repair;
- Define the safety property of replica synchronization and the liveness goal of eventual convergence.

### 14.5 CassandraMigrate

Responsibilities:

- Define RangeMigrate, migration types, and migration phases;
- Define the old routing replica, target routing replica, and current routing replica;
- Define MigrateFrontier;
- Define StartMigrate, AdvanceMigrate, ActivateMigrate, FinishMigrate, CleanupOldRangeData;
- Define the unified migration branches for bootstrap, decommission, move, and replace;
- Define the safety property of migration.

### 14.6 CassandraRead

Responsibilities:

- Define read requests, read response sets, and read results;
- Define the response count requirements for ONE, QUORUM, and ALL;
- Define DispatchRead, ReplicaReadResponse, CompleteRead, RejectRead;
- Define the LWW merge of response replica results;
- Define the concrete read eligibility sets;
- Do not directly reference FinalQueryFrontier defined in the final Frontier interface, to avoid reverse dependency.

### 14.7 CassandraFrontierInterface

Responsibilities:

- Uniformly define WriteFrontier, LocalLogFrontier, ReplicaFrontier, CommitFrontier, QueryFrontier, MigrateFrontier, FinalQueryFrontier;
- Do not declare new state variables;
- Do not define state advancement actions;
- Compose FrontierSafety;
- Promote the existing concrete read eligibility and result parsing in CassandraRead to FinalQueryFrontier.

### 14.8 CassandraIntegrated

Responsibilities:

- Compose all submodules;
- Define the complete set of state variables;
- Define the initial state;
- Define the disjunction of all actions;
- Define the system specification;
- Define the global TypeOK;
- Aggregate safety properties such as AuthorizationSafety, WritePathSafety, ReplicaSafety, ReadConsistencySafety, MigrateSafety, FrontierSafety;
- Expose the property names to be checked for subsequent TLC configuration.

---

## 15. Generation Constraints

Subsequent automatic model generation must obey the following constraints:

1. Do not generate Cassandra source code implementation, CQL parser, network protocol implementation, or real file formats;
2. Do not simplify Cassandra token range replica relationships to a single owner relationship;
3. Do not incorrectly interpret write consistency level as “sending writes only to that number of replicas”;
4. Writes must be sent to the current target replica set; the consistency level only determines the number of acknowledgements the coordinator node waits for;
5. Replica acknowledgement must be based on that replica having recorded and applied the mutation;
6. Do not unconditionally treat commit log records as batch fsync persistence;
7. Do not simplify `Acknowledged` to “all replicas have received it”;
8. Do not conflate replica-local applied data with client write success status;
9. Read results must come from the actual responding replicas and be resolved according to LWW rules;
10. A successful read request must satisfy the minimum number of responses for the selected consistency level;
11. For QUORUM semantics, visibility can only be verified under stable replica sets and quorum intersection conditions; do not incorrectly claim that ordinary Cassandra writes have global linearizability;
12. tombstone must participate in LWW as a versioned mutation, rather than directly deleting historical state;
13. Unauthorized writes, reads, and migrations must not modify protected state;
14. Before migration activation, the target replica must cover MigrateFrontier;
15. After migration completes, old nodes are allowed to retain redundant data; the existence of old data must not be treated as a dual-owner error;
16. cleanup can only delete redundant data that no longer belongs to the current routing replica set;
17. All replica, query, and migration Frontiers must be traceable to WriteFrontier;
18. Liveness conclusions must not be disguised as safety invariants without fairness assumptions;
19. Each action must fully specify state changes; unchanged variables must be explicitly kept unchanged in subsequent TLA+ models;
20. Critical invariants must not be defined as empty conditions, tautological conditions, or by forbidding all actions to evade verification.

---

## 16. Core correctness objectives

For any successfully completed Cassandra read, the model must guarantee that its result:

1. Is initiated by a Principal that has SELECT permission at the time the read is executed;
2. Targets a valid table, partition, and token range;
3. Is responded to by a sufficient number of replicas in the current routing replica set;
4. Each response version comes from a mutation already applied by the corresponding replica;
5. Each response mutation has entered WriteFrontier;
6. The final result is resolved from the actual response versions by the Cassandra LWW rule;
7. Satisfies the ONE, QUORUM, or ALL read condition specified by the request;
8. During token range migration, relies only on the routing replica set allowed to serve in the current migration phase;
9. After migration activation, does not rely on target replicas that have not reached MigrateFrontier;
10. Does not contain fictitious data that is unauthorized, not accepted, not applied by any responding replica, or superseded by a higher version.

For any successfully completed write, the model must guarantee:

1. The write principal has MODIFY permission when the operation occurs;
2. The coordinator node has located the mutation in the correct token range;
3. The mutation has been sent to the current target replica set for that range;
4. Each acknowledged replica has included the mutation in its local ReplicaFrontier;
5. The coordinator node returns success only after reaching the acknowledgment threshold of the selected write consistency level;
6. Completed writes can be read in subsequent reads that satisfy the replica set intersection condition, or be legitimately overwritten by a higher-version mutation;
7. Migration will not cause mutations that have already been safely accepted to be lost after routing switch.
