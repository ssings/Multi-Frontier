# Cassandra Frontier-based Formal Modeling Specification

## 1. Modeling Goals

This document defines the Frontier-based formal modeling specification for Apache Cassandra, used in the next stage to generate Cassandra's TLA+ model and TLC configuration.

The model goal is not to reproduce Cassandra source code, network protocols, or disk file formats, but to characterize and verify the following safety boundaries:

1. Only authorized roles can successfully execute protected CQL read/write operations;
2. Writes must first be routed through a coordinator node, and be accepted and applied on the local commit log and memtable paths of target replicas;
3. The write consistency level determines the number of replica responses required for the coordinator node to confirm success to the client, but does not change the semantics that 'write requests are sent to all target replicas';
4. Replicas may temporarily lag behind, but data visible in replicas cannot exceed writes already accepted by the system;
5. A read must be successfully returned only after responses from replicas satisfying the required number for the selected consistency level;
6. Concurrent or out-of-order updates to the same logical data item are resolved according to Cassandra's Last-Write-Wins (LWW) rule based on mutation timestamp;
7. Data flows involved in bootstrap, decommission, remove, move, replace, repair/rebuild can be unified as replica configuration migration of token ranges;
8. Before migration switchover, the target replica configuration must already cover successfully acknowledged data that needs to be retained;
9. Read results must simultaneously satisfy authorization, accepted writes, replica responses, consistency level, LWW resolution, and current routing/migration safety conditions.

This document uses the Cassandra 5.0 official documentation material snapshot as the source of business semantics. The Frontier in this document is a formal verification abstraction, not a product term exposed by Cassandra.

---

## 2. Abstraction Scope

### 2.1 Semantics Included in the Model

The model should include the following core Cassandra semantics:

- Partitioning and token range routing based on a consistent hashing token ring;
- A physical node may own multiple tokens, i.e., the vnode abstraction;
- The replication strategy of a Keyspace selects multiple distinct physical nodes as replicas for each token range;
- The coordinator node sends mutations to all target replicas of the range according to the token range mapped by the partition key;
- The local commit log and memtable application path of each replica;
- Write acknowledgment sets, write consistency levels, and conditions for the coordinator node to return success to the client;
- An abstraction of eventual synchronization driven by delayed replica reception, hint delivery, or repair;
- The three representative read consistency levels ONE, QUORUM, and ALL;
- Timestamped mutation and LWW resolution on the same logical data item;
- Authorization semantics such as SELECT, MODIFY, and AUTHORIZE based on roles, permissions, and resource hierarchies;
- Unified migration abstraction for range movements such as bootstrap, decommission, move, replace, and streaming;
- Frontier relationships among write, commit, replica, query, and migration;
- Distinction among success, rejection, and failure/timeout due to insufficient replica responses for write, read, and migration.

### 2.2 Content Explicitly Not Modeled

The following content is outside the scope of the first version model:

1. CQL syntax, query planning, secondary indexes, SAI, materialized views, and function execution;
2. Cross-partition transactions, distributed joins, foreign keys, and referential integrity;
3. LWT/Paxos prepare, promise, accept, and learn phases and linearizability proofs;
4. logged batch、batchlog、counter、transient replication；
5. TTL expiration, gc_grace, tombstone reclamation timing, compaction, SSTable file format, Bloom filter, cache, and index structures;
6. Physical fsync scheduling of commit log, segment truncation, archiving, replay, crash recovery, and disk failures;
7. Gossip generation/version vector clocks, Phi failure detector, seed node discovery, and per-node local UP/DOWN views;
8. Network message encoding, retry timeouts, and timing details of speculative retry;
9. Details of NetworkTopologyStrategy's rack and datacenter placement algorithms;
10. Exact implementation differences between SimpleStrategy and NetworkTopologyStrategy;
11. Authentication credentials, password hashing, TLS, JMX, permission cache refresh, and network source/CIDR restrictions;
12. Specific parameters of operational commands, traffic throttling, Zero Copy Streaming, and SSTable chunked transfer;
13. Transiently inconsistent token metadata/gossip views between Cassandra nodes.

The first version model abstracts the control plane's effective token map as a globally consistent logical configuration. This abstraction does not attempt to verify whether gossip eventually propagates correctly, but verifies whether, once the routing configuration switches, the replica data it points to satisfies migration safety conditions.

### 2.3 Key Abstraction Constraints

1. The model centers on single-partition read and write. A read request targets one Partition and returns the logical result of modeled data items within that partition.
2. Each DataItem represents a logical unit that can undergo independent LWW resolution. It can be abstracted as a column of a row, a row-level value, or another unit fixed by the modeling instance.
3. Each Mutation corresponds to the logical effect of one INSERT, UPDATE, or DELETE. DELETE is represented as a timestamped tombstone mutation.
4. To reduce the state space, the first version may assume that timestamps of different Mutations are totally ordered and unequal. Therefore, Cassandra's implementation-level tie-breaking details under identical timestamps are not modeled.
5. The model preserves the observable results of LWW, but does not save all historical versions, expired tombstones, and pre-compaction records in the SSTable.
6. "commit" in the model specifically means that the coordinator has collected the acknowledgements required by the write consistency level and reported success to the client; it is not Cassandra's cross-replica atomic commit protocol, nor does it mean that all replicas have been synchronized.

---

## 3. Core Entities, Mappings, and State

### 3.1 Role / Principal

`Principal` represents a Cassandra database role that initiates client requests or management requests.

A role can represent:

- A login user with the LOGIN permission;
- A role granted to other roles;
- An application service identity;
- A superuser;
- A control-plane principal representing trusted operators in the model.

The model does not distinguish between usernames and role names. A client connection directly carries its authenticated `Principal` in the model.

A role can inherit permissions through role grant relationships. The first version of the model may abstract the role inheritance closure in advance as an effective permission set, or may explicitly model an acyclic role grant graph; if explicitly modeled, it must ensure that role grant relationships remain acyclic.

### 3.2 Keyspace, Table, Partition, and DataItem

`Keyspace` is the configuration boundary of the replication strategy.

`Table` belongs to exactly one Keyspace:

- `tableKeyspace : Table -> Keyspace`

`Partition` represents a Cassandra partition determined by the partition key:

- `partitionTable : Partition -> Table`
- `partitionToken : Partition -> Token`
- `partitionRange : Partition -> TokenRange`

`DataItem` represents a logical data unit belonging to a Partition:

- `itemPartition : DataItem -> Partition`
- `itemTable(item) = partitionTable(itemPartition(item))`

The following must be maintained:

- Any DataItem belongs to exactly one Partition;
- Any Partition belongs to exactly one Table;
- The Table of a DataItem is consistent with the Table of its Partition.

### 3.3 Token, TokenRange, Node, and vnode

`Token` represents a position on the consistent hash ring.

`TokenRange` represents a data range on a contiguous token ring. The model does not require expanding the mathematical structure of the ring, but must ensure:

- Each Partition maps to a unique TokenRange;
- Each TokenRange can map to multiple replica nodes;
- A Node can own multiple Tokens, and therefore can serve as a candidate replica or routing node for multiple TokenRanges.

`Node` represents a Cassandra physical node or endpoint. A node can simultaneously serve as:

- the coordinator node for client requests;
- a replica of one or more TokenRanges;
- the source node for data stream migration;
- the target node for data stream migration;
- the staging node for hints.

The model does not introduce Cassandra's single-primary node concept. Cassandra replicas are multi-primary: any node that owns a replica of a Partition can independently receive a mutation for that Partition.

### 3.4 Replica Configuration and Routing Epoch

Replica configuration is jointly determined by Keyspace, TokenRange, and logical routing version:

- `ReplicaSet(epoch, keyspace, range) : SUBSET Node`

where:

- `epoch` is the token map / routing configuration version;
- The nodes in `ReplicaSet` must be distinct physical Nodes;
- `ReplicaSet` is non-empty;
- Under normal configuration, the number of replicas equals the abstract replication factor `RF` for that Keyspace on that TokenRange.

At a given moment, each Partition uses the current routing version:

- `activeEpoch : TokenRange -> Epoch`

When a write request is accepted by the coordinator node, its routing version and target replica set are recorded:

- `writeEpoch(mutation)`
- `writeReplicas(mutation) = ReplicaSet(writeEpoch(mutation), keyspace, range)`

Thus, subsequent topology changes do not change the write consistency level denominator of that mutation at that time.

### 3.5 Mutation, Version, and LWW

`Mutation` is a versioned modification of one DataItem:

- `mutationItem : Mutation -> DataItem`
- `mutationTimestamp : Mutation -> Timestamp`
- `mutationKind : Mutation -> {Put, Delete}`

For the same DataItem, Mutations are compared by timestamp. The mutation with the larger timestamp wins. Delete mutations also participate in the same LWW comparison.

Definition:

- `Winner(S)`: the Mutation with the maximum timestamp for the same DataItem in set `S`;
- If `Winner(S)` is Delete, the logical read result of that DataItem is missing;
- If `Winner(S)` is Put, the read result returns the logical value or version identifier represented by that Mutation.

The model does not need to store actual column values; returning a Mutation identifier or logical version is sufficient.

### 3.6 Coordinator Node

Every write request and read request is handled by a `coordinator : Node`.

The coordinator node's responsibilities in the model include:

1. Determine the target replica set based on the Partition's token and the current `activeEpoch`;
2. Send write mutations to all target replicas;
3. Aggregate write responses;
4. Select or wait for a sufficient number of read responses according to the read consistency level;
5. Perform LWW resolution on multiple versions in the read responses;
6. Record a successful result after the write/read consistency conditions are satisfied, or record a rejection or failure due to insufficient permission or insufficient responses.

The coordinator node can be a target replica or not a target replica.

---

## 4. Authorization, Rejection, and Historical Authorization

### 4.1 Authorized Resources and Permissions

Cassandra's permission resources have a hierarchy. The first version of the model focuses on the data resource hierarchy:

- `ALL KEYSPACES`
- `KEYSPACE`
- `TABLE`

Permissions can be inherited from higher levels downward. The model supports at least:

- `SELECT`: allows reading data in a Table;
- `MODIFY`: allows INSERT, UPDATE, DELETE;
- `AUTHORIZE`: allows granting or revoking permissions on the corresponding resource;
- `CREATE`, `ALTER`, `DROP`, `DESCRIBE` can be optional extensions.

Define the effective permission check:

- `CanSelect(principal, table)`
- `CanModify(principal, table)`
- `CanAuthorize(principal, resource)`

If role inheritance is adopted, these checks must be based on the role itself and the transitive closure of the roles granted to it.

`SUPERUSER` can be abstracted as having all applicable permissions on all modeled resources.

### 4.2 Permission State

The permission state includes at least:

- `permission : Principal -> Resource -> SUBSET PermissionKind`
- Optional `grantedRoles : Principal -> SUBSET Principal`

If `grantedRoles` is explicitly modeled, it must remain a directed acyclic graph. If role A is granted to role B, then B obtains A's inheritable permissions, but does not inherit A's LOGIN attribute.

### 4.3 Grant and Revoke

The model should include:

- `GrantPermission(admin, target, resource, permissionKind)`
- `RevokePermission(admin, target, resource, permissionKind)`

Preconditions:

- The executor has the `AUTHORIZE` permission on the target resource, or is a SUPERUSER;
- The permission type is applicable to the resource;
- The modified resource belongs to a resource hierarchy supported by the model.

After Grant/Revoke succeeds, it affects permission decisions for subsequent requests. The model does not require a client connection to be reestablished before permissions take effect.

### 4.4 Distinguishing Success, Rejection, and Timeout

The following three result categories must be distinguished:

1. `RejectedUnauthorized`: the request principal lacks the required permission;
2. `FailedInsufficientResponses` or `TimedOut`: the principal has permission, but the replica responses required by the consistency level were not collected within the response window allowed by the model;
3. `Succeeded`: the principal is authorized, and the success conditions for the corresponding operation are satisfied.

Unauthorized writes must not change:

- the globally accepted write set;
- the replica commit log history;
- the replica applied state;
- the write acknowledgment set;
- the routing configuration;
- the migration state.

Unauthorized reads must return empty results or explicit rejection results, and must not produce successful read records.

### 4.5 Historical Authorization Records

Each successful or failed operation records the authorization conclusion at execution time. For example:

- `lastWrite.authorized`
- `lastRead.authorized`
- `lastMigrate.authorized`

A subsequent Revoke must not retroactively make historically successful operations become “unauthorized at the time”. Therefore, safety properties must check the authorization result recorded when the operation occurred, rather than only using the current permission state to recheck historical operations.

### 4.6 Modeling Boundary for Topology Operations Authorization

Cassandra's official CQL permissions documentation defines database resource permissions such as SELECT, MODIFY, and AUTHORIZE, but the provided topology change materials do not define bootstrap, decommission, move, or replace as ordinary CQL `Migrate` permission operations.

Therefore, the migration initiation authorization in the model adopts the following restricted abstraction:

- `CanOperateTopology(principal)` represents authorization by a trusted operations principal or external control plane;
- It is a model environment precondition and does not claim to correspond to any specific CQL permission name in Cassandra;
- Migration requests that have not obtained this abstract operations authorization must enter the rejection branch and must not modify the routing configuration of token ranges, the migration source/destination, or data replication state.

---

## 5. Write Path and Write Consistency

### 5.1 Write Consistency Levels

The first version fixedly supports:

- `ONE`
- `QUORUM`
- `ALL`

For mutation `m`, its target replica set is `writeReplicas(m)`, and the number of replicas is:

- `N = Cardinality(writeReplicas(m))`

Required number of write acknowledgments:

- `RequiredWriteAcks(m, ONE) = 1`
- `RequiredWriteAcks(m, QUORUM) = floor(N / 2) + 1`
- `RequiredWriteAcks(m, ALL) = N`

By default, the model does not include `ANY`. The reason is that `ANY` applies only to writes and allows the coordinator node to store a hint as one of the success conditions, but a hint is not equivalent to the target replicas having applied the mutation. If `ANY` is later extended, a HintFrontier must be introduced separately, and hints must not be mistakenly treated as replica acknowledgments.

`LOCAL_ONE`, `LOCAL_QUORUM`, `EACH_QUORUM`, `TWO`, and `THREE` can be added in a multi-datacenter extended model; the first version does not model datacenter-local replica sets.

### 5.2 Write State

Each Mutation has at least the following logical states:

- `None`: has not yet been accepted by the coordinator node;
- `Accepted`: the coordinator node has accepted it and determined the target replica set;
- `Dispatched`: logically sent to all target replicas, with some messages possibly delayed;
- `ClientSucceeded`: the number of acknowledgments reaches the write consistency level, and the coordinator node has reported success to the client.

For each Mutation, each replica has at least the following local states:

- `NotReceived`；
- `CommitLogged`: the mutation has been written to the local commit log abstraction of the node;
- `MemtableApplied`: the mutation has been applied to the readable state in the node's memory;
- Optional `Flushed`: the logical result of the mutation has entered the persistent SSTable abstraction.

To avoid commit log cleanup breaking historical safety relationships, `commitLogged` in the model should represent 'the historical fact that it was once appended to the local commit log', rather than whether the current physical commit log segment still retains the record.

### 5.3 ReceiveWrite: Coordinator Node Receives a Write

`ReceiveWrite(principal, coordinator, mutation, level)` has at least the following preconditions:

1. `principal` has MODIFY permission on the Table to which `mutationItem(mutation)` belongs;
2. mutation has not yet been accepted;
3. coordinator is in Nodes;
4. the current Partition, TokenRange, and Keyspace mappings are valid;
5. the current `ReplicaSet(activeEpoch(range), keyspace, range)` is non-empty.

Successful effects:

1. record that the mutation has been accepted;
2. record `writeEpoch(mutation)`;
3. fix `writeReplicas(mutation)`;
4. record the requested write consistency level;
5. place mutation into the set to be sent to all target replicas;
6. record `authorized = TRUE` for the write operation;
7. cause mutation to enter WriteFrontier.

This action itself does not represent client write success, nor does it represent that any replica has acknowledged.

### 5.4 ReplicaReceiveAndApply: replica local write

`ReplicaReceiveAndApply(mutation, replicaNode)` has at least the following preconditions:

1. mutation has been accepted by the coordinator node;
2. `replicaNode ∈ writeReplicas(mutation)`, or the node is a legal receiving target of modeled hint/replay/repair;
3. mutation has not yet completed local application on that node.

The effects must follow the abstract order:

1. mutation enters the node's `CommitLogged` set;
2. mutation enters the node's `MemtableApplied` set;
3. the locally visible version of DataItem on that node is updated according to the LWW rule;
4. if that node belongs to the original target replicas of mutation, it contributes one replica acknowledgment to the coordinator node.

The model need not expand actual asynchronous disk I/O, but must not allow mutation to directly become the applied readable version of that replica without entering the local commit log abstraction.

### 5.5 ReplicaAck: Replica Acknowledgment

`ReplicaAck(mutation, replicaNode)` indicates that the coordinator node has received a write response from a legitimate replica.

The following must be satisfied:

- `replicaNode ∈ writeReplicas(mutation)`；
- mutation has completed `CommitLogged` and `MemtableApplied` on that node;
- The node has not yet repeated acknowledgment for that mutation.

Acknowledgment set:

- `ackSet : Mutation -> SUBSET Node`

The following must always be satisfied:

- `ackSet(mutation) ⊆ writeReplicas(mutation)`；
- Every node in `ackSet(mutation)` has locally applied the mutation.

### 5.6 CompleteWrite: Coordinator Node Acknowledges Success to Client

`CompleteWrite(mutation)` may be executed only if the following conditions hold:

- `Cardinality(ackSet(mutation)) >= RequiredWriteAcks(mutation, requestedWriteLevel(mutation))`

Effects:

- mutation enters `CommitFrontier`;
- The write operation records `succeeded = TRUE`;
- The write operation records the authorization result at execution time;
- It does not require all target replicas to have applied the mutation, unless the request level is ALL.

### 5.7 Write Failure and Incomplete Write

If the subject is authorized but the required number of acknowledgments is not reached within the abstract response window, the write request may enter `FailedInsufficientResponses` or `TimedOut`.

This failure must not roll back replica-local application that has already occurred. A mutation that has reached some replicas may still be read later, delivered via hint, or propagated during repair.

Therefore, the model must not incorrectly assume:

- “The client did not receive success” is equivalent to “no replica has stored the mutation”;
- “The client received success” is equivalent to “all replicas have stored the mutation”.

### 5.8 Commit Log Synchronization Mode Boundary

Official documentation states:

- In `batch` mode, Cassandra does not acknowledge a write before the commit log is fsynced to disk;
- In `periodic` mode, writes may be acknowledged before fsync, and an abnormal shutdown may lose at most one synchronization cycle or more of data.

The first version of the model only verifies the logical commit log append and memtable application order, and does not verify fsync, crash windows, or replay recovery. Therefore:

- `CommitLogged` should not be interpreted as having completed physical fsync;
- `ClientSucceeded` should not be interpreted as having been persisted under any crash scenario;
- To verify crash durability, subsequent models must add `commitlog_sync` modes, stable storage state, crash, and replay actions.

---

## 6. Replica propagation, late replicas, and eventual synchronization

### 6.1 Full sending and asynchronous arrival

For ordinary write consistency levels, the coordinator sends the write request to all target replicas of the Partition. The write consistency level only determines how many responses the coordinator waits for before replying to the client, and does not limit how many replicas the write request is sent to.

Therefore, the model must allow:

- all target replicas receive immediately;
- only a subset of replicas receive first;
- some replicas receive with delay;
- a replica is unreachable during the initial write request;
- a low-consistency write that has been successfully acknowledged may not yet be visible on other replicas.

### 6.2 PendingDelivery and Hint abstraction

The model may use:

- `pendingDelivery : Node -> SUBSET Mutation`
- `hintedMutation : Node -> SUBSET Mutation`

to represent a mutation that has not yet been delivered to the target replica, or a hint temporarily stored by another node and awaiting subsequent delivery.

For ONE, QUORUM, and ALL:

- a hint is not counted in `ackSet`;
- a hint does not mean that the target replica already has the mutation;
- subsequent replay of a hint can advance the target replica's ReplicaFrontier.

The first version does not need to model the maximum retention window for hints, hint file formats, or node failure detection logic.

### 6.3 SyncLateReplica

`SyncLateReplica(mutation, replicaNode)` represents a late replica receiving a mutation through delayed messages, hint replay, read repair, anti-entropy repair, or migration catch-up.

Preconditions:

1. the mutation already belongs to WriteFrontier;
2. `replicaNode` is a node in the current or historical valid replica configuration of the mutation, or a valid target node during migration;
3. The mutation has not yet completed local application on that node.

Effects:

1. First enter CommitLogged on that node;
2. Then enter MemtableApplied;
3. Update the local winning version of DataItem on that node according to LWW;
4. Must not fabricate a new client write success;
5. The backfilling of historical writes does not change the original `ackSet` and `ClientSucceeded` determination of that write.

### 6.4 Repair Abstraction

Cassandra uses best-effort mechanisms such as read repair and hinted handoff to promote replica convergence, and ensures eventual synchronization within the replica scope through anti-entropy repair and Merkle tree comparison.

The first version abstracts these mechanisms uniformly as a repeatable `RepairOrSync` action:

- The action may copy data only from accepted Mutation;
- The action may allow lagging replicas to receive missing mutations or winning versions with higher timestamps;
- The action must not cause a replica to produce a version that has not entered WriteFrontier;
- The action need not distinguish the specific implementations of read repair, full repair, sub-range repair, or incremental repair.

### 6.5 Preconditions for Convergence

"Eventually consistent" is not an unconditional safety invariant, but a liveness conclusion that depends on the environment and fairness. It requires at least:

1. For a given range, infinitely many new winning mutations are no longer continuously produced;
2. There exists a reachable replica that stores the winning version;
3. Late messages, hint replay, or repair actions will not be permanently starved;
4. The target replica eventually regains reachability or is replaced;
5. LWW timestamp comparison remains consistent.

---

## 7. Consistent Read

### 7.1 Read Consistency Levels

The first version supports reads:

- `ONE`
- `QUORUM`
- `ALL`

For the current read routing replica set `readReplicas`, let:

- `N = Cardinality(readReplicas)`

Required number of read responses:

- `RequiredReadResponses(ONE) = 1`
- `RequiredReadResponses(QUORUM) = floor(N / 2) + 1`
- `RequiredReadResponses(ALL) = N`

When reading, use the replica configuration corresponding to the current `activeEpoch`, not the historical replica configuration of some old write.

### 7.2 ReadRequest: Coordinator node receives a read request

The preconditions of `ReadRequest(principal, coordinator, partition, level)` include:

1. principal has SELECT permission on the Table to which Partition belongs;
2. coordinator is a valid Node;
3. level belongs to the supported read consistency levels;
4. The activeEpoch and ReplicaSet of the current TokenRange are valid.

After successful receipt, the coordinator node records:

- The Partition being read;
- Request level;
- Current read epoch;
- `readReplicas = ReplicaSet(activeEpoch(range), keyspace, range)`；
- The set of received read responses;
- `authorized = TRUE` when the operation occurs.

### 7.3 ReplicaReadResponse: Replica read response

A replica may contribute a response to a read only if the following conditions are satisfied:

1. It belongs to the `readReplicas` of the read;
2. It is in a responsive state in the model;
3. It returns the local LWW result resolved from its current `MemtableApplied` or persisted state.

Each response contains the locally winning Mutation of the modeled DataItem in the Partition, or indicates that the node currently does not have that DataItem.

The model should not allow the following to appear in replica responses:

- A Mutation not locally applied by the replica;
- A Mutation not belonging to WriteFrontier;
- A Mutation inferred without basis by other replicas.

### 7.4 CompleteRead: Read Success Condition

`CompleteRead(readRequest)` may be executed only if the following conditions hold:

- `Cardinality(readResponseSet(readRequest)) >= RequiredReadResponses(level)`

The coordinator node performs per-DataItem LWW resolution on the actually returned response set:

1. Collect the versions of the DataItem on all selected responding replicas;
2. Select the Mutation with the largest timestamp;
3. If the winning Mutation is a Put, place it in the result;
4. If the winning Mutation is a Delete or there are no versions, the DataItem does not appear in the logical result.

A successful read result must equal the complete LWW resolution result of the actual response set for that read, not any subset of it. This prevents the model from circumventing the property by always returning an empty result.

### 7.5 Modeling Implications of ONE, QUORUM, ALL

`ONE`：

- Only one current replica response is required;
- It may read an older version from a lagging replica;
- It does not guarantee reading the most recently successfully acknowledged write, unless the write/read replica intersection and version conditions are otherwise satisfied.

`QUORUM`：

- A majority response from the current replica set is required;
- When the write and read target the same replica set, and the write acknowledgment count `W` and read response count `R` satisfy `W + R > N`, the write quorum and read quorum have at least one replica in common;
- Provided no higher timestamp overwrites that logical item, this intersection provides the basis for a visibility guarantee of the successfully written version.

`ALL`：

- All replica responses from the current replica set are required;
- If any current replica cannot respond, the read cannot succeed;
- After success, the result is based on LWW resolution across all current replicas.

### 7.6 Read Failure

If the principal has SELECT permission, but the collected read responses are insufficient to satisfy the selected consistency level, the read enters a failure or timeout state:

- It must not fabricate a successful result;
- It must not incorrectly mark partial responses as satisfying QUORUM or ALL;
- Diagnostic partial response state may be retained, but `lastRead.succeeded = FALSE`;
- It is not required to return business data when a read fails.

### 7.7 Boundary of Read Repair

When replica responses of different versions occur during a read, Cassandra can trigger read repair to promote replica convergence. The first version of the model can model read repair as a separate subsequent synchronization action, and does not require `CompleteRead` to atomically modify lagging replicas.

Read correctness only requires:

- A successful read returns the result resolved by LWW over the set of replicas that actually responded;
- Subsequent repair does not create unaccepted mutations;
- Repair does not change already recorded historical read results.

---

## 8. Unified Abstraction of Data Range Migration

### 8.1 Unified Migration Object

Cassandra's bootstrap, decommission, remove, move, replace, rebuild, and repair may all involve transferring token range data between nodes. The first version abstracts them uniformly as:

- Replica configuration for a `TokenRange` migrates from the old epoch to the new epoch;
- The source replica set is `sourceReplicas`;
- The target replica set is `targetReplicas`;
- Data propagates from the source side to the target side through streaming, repair, or other legitimate synchronization methods;
- After the switch, the new `activeEpoch` determines the routing replica set for subsequent reads and writes to this range.

This abstraction does not assume that a range has only one "owner". In Cassandra, a TokenRange has multiple replicas at the same time, and replicas can independently receive mutations. Therefore, the model must use an "active replica set" rather than a single owner variable.

### 8.2 Migration States

The migration state of each TokenRange is fixed as:

- `Stable`: there is no range migration in progress, and the replica set of the current activeEpoch serves requests;
- `Streaming`: the old replica configuration is still the active routing configuration, and the target replica configuration is receiving historical data and catch-up data;
- `Activated`: the new replica configuration has become the active routing configuration, but redundant data in the old replicas may not yet have been cleaned up;
- `CleanupEligible`: the new configuration has become stable, and data no longer needed on the old nodes can be cleaned up by operations.

The first version may use `CleanupEligible` as a logical marker after `Activated`, or reset the state to `Stable` after migration completes, but it must preserve the semantics that "old data is not automatically deleted by the activation action".

### 8.3 StartMigrate

The preconditions of `StartMigrate(operator, range, targetEpoch)` include at least:

1. `CanOperateTopology(operator)` is true;
2. range is currently in `Stable`;
3. `targetEpoch` defines the replica set for this range;
4. Target replica set differs from current replica set, or migration type is explicitly rebuild/repair;
5. All nodes in the target replica set are valid Node.

Effect:

1. `migrateState(range) := Streaming`；
2. Record `sourceEpoch(range)` and `targetEpoch(range)`;
3. Freeze the source replica set and the target replica set;
4. Record the logical boundary of successful writes at the start of migration;
5. The old activeEpoch continues to handle normal reads and writes in this phase;
6. Target nodes may begin receiving range data from source replicas or other valid replicas.

Unauthorized or invalid StartMigrate must not change routing epoch, active replica set, migration state, or replica data.

### 8.4 StreamRangeData

`StreamRangeData(range, source, target)` represents one data propagation during streaming.

Preconditions:

1. range is in `Streaming`;
2. source belongs to the source replica set, retained replica set, or another holder legitimately determined by repair;
3. target belongs to the target replica set;
4. source already owns an accepted version that can be propagated.

Effect:

1. target receives the winning version of the DataItem already owned by source or its missing mutation;
2. The result on target obeys LWW;
3. Transmission must not create data beyond WriteFrontier;
4. Transmission may be repeated, out of order, or completed in multiple steps;
5. Transmission does not automatically change activeEpoch.

The first version does not distinguish partition-based transmission from whole-SSTable zero-copy transmission; both are considered legitimate propagation of logical versions from source to target.

### 8.5 CatchUpMigrate

During the Streaming phase, the old routing configuration may still accept new writes. Therefore, migration cannot merely copy the static snapshot at startup.

`CatchUpMigrate(range)` represents target replicas continuing to catch up with updates on the source side or existing replicas. It must at least cover:

- logical versions successfully confirmed before migration start;
- Logical versions that have been successfully acknowledged before activation during the Streaming phase;
- The current logical winning version after being overwritten by a newer version due to LWW.

For each DataItem, the migration target must store a version consistent with the migration safety boundary, or store a valid version with a higher timestamp. If the higher version is Delete, the tombstone must also be correctly propagated and must not erroneously resurrect the old value.

### 8.6 ActivateMigrate: Ownership/Route Switching Conditions

`ActivateMigrate(range)` indicates that the active routing switches from the old replica configuration to the new replica configuration. It is not a single-primary owner switch, but a switch of `activeEpoch(range)`.

Preconditions must include:

1. `migrateState(range) = Streaming`；
2. For each logical DataItem currently successfully acknowledged and belonging to the range, its migration-safe winning version is covered by the new replica set;
3. For each target replica, the target replica owns a safe version of the DataItem, or owns a valid LWW winning version with a higher timestamp;
4. The new replica set satisfies the replication configuration constraints of the Keyspace;
5. At the discrete atomic boundary of the switching action, there does not exist a mutation that has not yet been included in the migration safety determination but has already been successfully acknowledged and is still routed according to the old epoch.

Effects:

1. `activeEpoch(range) := targetEpoch(range)`；
2. `migrateState(range) := Activated`；
3. Subsequent reads and writes for the range use the new replica set;
4. Data on the old replicas is not deleted;
5. Successfully acknowledged data remains readable from the corresponding replicas and can continue to be replicated under the new routing configuration.

This condition corresponds to Cassandra’s safety goal of requiring new nodes to stream data from existing replicas during range movement and, when necessary, repair to recover missed writes. The model adopts a stronger safety precondition than “switching is allowed once streaming has started” to avoid losing acknowledged data in the new replica configuration after switching.

### 8.7 FinishMigrate and Cleanup

`FinishMigrate(range)` is executed after Activated:

1. Marks the new routing configuration as stable;
2. Allows range data on old replicas that is no longer needed to enter `CleanupEligible`;
3. Must not delete data within the migration safety boundary in the new replica configuration;
4. Must not cause activeEpoch to regress;
5. Must not change the historical results of successful writes.

In the model, `CleanupOldRangeData` is an optional action. It may only delete data replicas that no longer belong to the current replica configuration and have already satisfied the migration safety condition. This action must not delete all logical replicas, nor must it break the replication count required under the current activeEpoch.

### 8.8 Correspondence with Specific Operational Scenarios

Bootstrap：

- The new node obtains a token;
- The new node becomes part of a new replica set for some TokenRanges;
- Stream data from existing replicas;
- Activate the new configuration after catch-up completes.

Decommission：

- A live node exits;
- The data of the ranges it is responsible for or participates in as a replica flows to other nodes;
- After the new replica set is activated, the old node no longer bears the active replica responsibility for the corresponding ranges.

Remove dead node：

- A failed node cannot serve as a streaming source;
- The remaining replicas become the data source;
- It must be guaranteed that the remaining replicas can satisfy the migration safety conditions.

Move：

- In a single-token scenario, a node changes position on the ring;
- It can be viewed as a combined migration from an old token range replica configuration to a new token range replica configuration.

Replace：

- A new node replaces a failed node;
- The new node bootstraps data from other nodes;
- The official documentation states that writes in progress may be missed during replacement, and repair must be run under specific conditions;
- In the model, the ActivateMigrate precondition must be reached through CatchUpMigrate/Repair, and 'node startup' must not be directly regarded as a safe switch.

---

## 9. Frontier Layered Definition

### 9.1 WriteFrontier

`WriteFrontier` is the set of Mutations that have been legally accepted by the coordinator node.

Conditions for a Mutation to enter WriteFrontier:

1. The request principal has MODIFY permission;
2. The coordinator node has determined the current token range of the Partition;
3. The coordinator node has fixed the writeEpoch and writeReplicas of the mutation;
4. The mutation has entered the pending dispatch process.

WriteFrontier does not mean the client has received a successful acknowledgment, nor does it mean all replicas have applied it.

Formally:

- `WriteFrontier = { m : ReceiveWrite of m has succeeded }`

Core relationships:

- Mutations in the local commit logs of all replicas must belong to WriteFrontier;
- The mutations already applied by all replicas must belong to WriteFrontier;
- repair, hint replay, and streaming must not introduce mutations outside WriteFrontier.

### 9.2 LocalPersistenceFrontier

`LocalPersistenceFrontier(node)` denotes the set of Mutations that a node has already written to its local commit log abstraction.

Formally:

- `LocalPersistenceFrontier(node) = commitLogged[node]`

Core relationships:

- `LocalPersistenceFrontier(node) ⊆ WriteFrontier`

This Frontier only denotes local logical append history, not that physical fsync has completed.

### 9.3 ReplicaFrontier

`ReplicaFrontier(node, range)` denotes the set of Mutations for which the node has completed memtable application for the TokenRange and can participate in reads or continue synchronization.

Formally:

- `ReplicaFrontier(node, range) = { m ∈ memtableApplied[node] : RangeOf(m) = range }`

Core relationships:

- `ReplicaFrontier(node, range) ⊆ LocalPersistenceFrontier(node)`
- `ReplicaFrontier(node, range) ⊆ WriteFrontier`

The local readable logical state of each replica is derived from the LWW winners of mutations in its ReplicaFrontier.

### 9.4 CommitFrontier

`CommitFrontier` denotes the set of Mutations that the coordinator node has successfully acknowledged to the client.

A Mutation is in CommitFrontier if and only if:

1. The mutation has entered WriteFrontier;
2. The size of its ackSet reaches the threshold required by the requested write consistency level;
3. Each acknowledged node in ackSet belongs to the writeReplicas fixed for that mutation;
4. Each acknowledged node has applied the mutation to ReplicaFrontier.

Formally:

- `CommitFrontier = { m ∈ WriteFrontier : ClientSucceeded(m) }`

CommitFrontier is the boundary of successful client writes, not the sole source of all readable data.

Special provision: do not require `QueryFrontier ⊆ CommitFrontier`. In Cassandra's asynchronous replica system, a mutation that has already been applied locally by a replica, but for which the coordinator node has not yet returned success or final failure, may have been observed by some reads. Requiring queries to observe only CommitFrontier would incorrectly strengthen Cassandra semantics.

### 9.5 QueryFrontier

`QueryFrontier(readRequest)` denotes the result boundary that a read can safely resolve under its actual responding replica set.

Its composition conditions are:

1. The read request has obtained SELECT authorization at execution time;
2. The responding node belongs to the readReplicas for the request's current routing epoch;
3. The number of responding nodes satisfies the selected read consistency level;
4. The mutation in each response belongs to the ReplicaFrontier of that replica;
5. The return value is the complete result of these actual responses resolved according to the LWW rules.

Therefore, QueryFrontier is request-dependent, rather than a set statically determined only by `ONE`, `QUORUM`, `ALL`.

For a particular read `q`:

- `QueryFrontier(q) = ResolveLWW(ReplicaResponses(q))`

where `ReplicaResponses(q)` contains only the actual responses that satisfy the legal replica conditions for that read request.

### 9.6 MigrateFrontier

`MigrateFrontier(range)` denotes the successfully acknowledged logical state boundary that the target replica configuration must cover before the routing configuration of the TokenRange switches.

It is defined by the winning version of each DataItem, rather than simply storing all historical Mutations:

1. Take the mutations in the CommitFrontier that belong to this range;
2. For each DataItem, determine the currently successfully acknowledged winning version according to LWW;
3. If the target already has a legal WriteFrontier version with a higher timestamp, it may be regarded as covering that lower version;
4. Delete/tombstone must also be retained as a logical winning version.

Before the migration switch, the following must be satisfied:

- For each DataItem in MigrateFrontier, every node in the new replica set that is required to retain a replica for that range already has a safe winning version, or has a higher legal version.

### 9.7 FinalQueryFrontier

`FinalQueryFrontier(readRequest)` denotes the result boundary that a successful read is ultimately allowed to return:

- `FinalQueryFrontier(q)`
  = authorization boundary
  ∩ QueryFrontier(q)
  ∩ current routing safety boundary
  ∩ LWW resolution boundary

where:

- The authorization boundary requires that SELECT permission is held when the read request occurs;
- QueryFrontier requires satisfying the actual read replica responses and the read consistency level;
- The current routing safety boundary requires that the responding replicas belong to the legal replica set under activeEpoch, or, during the Streaming phase, belong to the old routing replica set that is still valid;
- The LWW resolution boundary requires that each returned logical value is the Put with the maximum timestamp among the actual response versions and is not overwritten by a Delete with a higher timestamp.

The result of a successful read must equal FinalQueryFrontier, rather than any subset thereof.

### 9.8 Frontier Relationship Overview

The core dependencies are as follows:

- `LocalPersistenceFrontier(node) ⊆ WriteFrontier`
- `ReplicaFrontier(node, range) ⊆ LocalPersistenceFrontier(node)`
- `CommitFrontier ⊆ WriteFrontier`
- `ackSet(m) ⊆ { n : m ∈ ReplicaFrontier(n, RangeOf(m)) }`
- `QueryFrontier(q)` is derived only from the ReplicaFrontier of legitimate responding replicas
- `MigrateFrontier(range)` is derived from the LWW winning state of CommitFrontier
Before `ActivateMigrate(range)`, the target replica must cover MigrateFrontier
- `FinalQueryFrontier(q) ⊆ QueryFrontier(q)`

Note: There is no unconditional set inclusion relationship between CommitFrontier and QueryFrontier. CommitFrontier describes writes that have received successful acknowledgment to clients; QueryFrontier describes versions visible in actual read responses. The two establish conditional visibility guarantees through `W + R > N`, replica set intersection, LWW, and migration safety conditions.

---

## 10. Safety Properties to Be Verified

### 10.1 TypeOK and Mapping Consistency

Always verify:

1. All variables belong to the declared finite sets, function spaces, or state enumerations;
2. DataItem, Partition, Table, and Keyspace mappings remain consistent;
3. Each Partition maps to a unique TokenRange;
4. The replica set of each active TokenRange is non-empty;
5. Nodes in ReplicaSet are distinct;
6. The writeReplicas of a write record are consistent with the writeEpoch at write acceptance;
7. The readReplicas of a read record are consistent with the activeEpoch at read acceptance;
8. The relationships among migration source, target epoch, and TokenRange remain type-correct.

### 10.2 AuthSafety

Verify:

1. On a successful write, the initiating Principal has MODIFY permission at the time the write occurs;
2. On a successful read, the initiating Principal has SELECT permission at the time the read occurs;
3. On a successful Grant/Revoke, the executor has AUTHORIZE permission or SUPERUSER status at the time of execution;
4. On a successful migration initiation, the executor has the model-defined `CanOperateTopology`;
5. Unauthorized writes, reads, and migrations do not modify protected data or topology state;
6. Subsequent permission revocation does not change `authorized = TRUE` in historical successful operation records.

### 10.3 WritePathSafety

Verify:

1. `MemtableApplied(node, m)` implies `CommitLogged(node, m)`;
2. `CommitLogged(node, m)` implies `m ∈ WriteFrontier`;
3. `MemtableApplied(node, m)` implies `m ∈ WriteFrontier`;
4. Any replica acknowledgment can only occur after that replica has locally applied the mutation;
5. `ackSet(m) ⊆ writeReplicas(m)`；
6. `m ∈ CommitFrontier` implies the acknowledgment count reaches the threshold of the write consistency level requested for that mutation;
7. Failed or timed-out writes must not be incorrectly marked as CommitFrontier;
8. A successfully acknowledged write does not require all replicas to have applied it, unless the write level is ALL.

### 10.4 ReplicaSafety

Verification:

1. The ReplicaFrontier of any replica does not exceed WriteFrontier;
2. Late synchronization, hint replay, repair, and streaming can only propagate accepted mutations;
3. A replica's local LWW winning version can only come from mutations that the replica has actually applied;
4. A delete mutation must not be incorrectly overwritten by an older Put mutation;
5. The local result for the same DataItem is always equal to the LWW winning result of locally applied mutations.

### 10.5 ReadSafety

Verification:

1. The number of responses for a successful read reaches the selected read consistency level;
2. Each read response node belongs to the readReplicas of that read record;
3. Each read response version comes from that node's ReplicaFrontier;
4. A successful read result is exactly equal to the LWW resolution result of the actual response set;
5. A successful read must not return a DataItem whose tombstone wins;
6. Unauthorized reads must not produce successful results;
7. A read with insufficient responses must not masquerade as a successful read;
8. A successful read result belongs to FinalQueryFrontier.

### 10.6 Conditional quorum visibility

When the following conditions hold simultaneously, verify the conditional visibility of successfully written data to subsequent reads:

1. The write and read operations target the same logical replica configuration, or migration has safely brought the logical winning version of that write into the new configuration;
2. The number of write acknowledgments is `W`, and the number of read responses is `R`;
3. `W + R > N`；
4. The read occurs after the write succeeds;
5. There is no mutation with a higher timestamp that legally overwrites the DataItem;
6. The read succeeds and the response set satisfies its read consistency level.

Then the LWW result of the read must contain the logical effect of that successful write.

This property applies, for example, to the typical case of RF=3 with QUORUM writes and QUORUM reads. It should not incorrectly claim that ONE reads necessarily see the most recent successful write, or that all Cassandra read/write combinations provide linearizability.

### 10.7 MigrateSafety

Verification:

1. During the Streaming phase, the old activeEpoch continues to handle request routing, unless the model explicitly defines another legal transition policy;
2. Before the Active routing switch, the target replica configuration already covers MigrateFrontier;
3. After ActivateMigrate, the current routing replica set comes from targetEpoch;
4. Migration activation must not delete old replica data;
5. Cleanup must not delete safe versions required by the current active replica configuration;
6. For each successfully acknowledged logical DataItem, the LWW winning version before and after migration is not lost due to routing switches;
7. During migration, old replicas and new replicas are allowed to hold data simultaneously; this is not an illegal “dual owner” state in Cassandra;
8. A single Node owner invariant must not be imposed on Cassandra’s multi-replica architecture;
9. Scenarios such as replacement and remove must not be incorrectly considered safely activated by the model before catch-up/repair is complete.

### 10.8 FrontierSafety

Unified verification:

1. `LocalPersistenceFrontier(node) ⊆ WriteFrontier`；
2. `ReplicaFrontier(node, range) ⊆ WriteFrontier`；
3. `CommitFrontier ⊆ WriteFrontier`；
4. The acknowledgment nodes of each successful write have all advanced past the corresponding ReplicaFrontier;
5. QueryFrontier depends only on the ReplicaFrontier of actual legal read responses;
6. MigrateFrontier depends only on the LWW logical state of successfully acknowledged writes;
7. Before ActivateMigrate, the target replicas cover MigrateFrontier;
8. The most recent successful read result equals its FinalQueryFrontier;
9. Any data returned by a successful read has passed authorization, write acceptance, replica visibility, read consistency, LWW, and routing migration safety checks.

---

## 11. Liveness properties requiring fairness or environment assumptions

The following are not pure safety invariants and must be expressed in the TLA+ specification together with weak fairness, strong fairness, or environment assumptions.

### 11.1 Delayed replicas eventually catch up

When the following premises are satisfied:

- the mutation has entered WriteFrontier;
- the target replica is reachable over the long term;
- subsequent synchronization actions continue to be allowed;
- no infinite number of new mutations perpetually preempt synchronization;

then `SyncLateReplica`, hint replay, or repair will eventually cause the target replica to incorporate the mutation or a higher LWW winning version into ReplicaFrontier.

Fairness must be imposed on synchronization actions, or “eventual network delivery” must be treated as an environmental assumption.

### 11.2 Eventual consistency

After writes to a certain DataItem stop, if all replicas within the configuration eventually become reachable and repair is fairly scheduled, then all replicas eventually converge to the same LWW winning version.

This property requires:

- fairness for repair/sync actions;
- an environmental assumption about network reachability;
- assumptions about the total order of timestamps and the consistency of the LWW rule.

### 11.3 Eventual dissemination of successful writes

If a successful write has not yet reached all target replicas, and the target replicas are eventually reachable, then, provided that the synchronization mechanism continues to execute, the mutation or a higher legitimate overriding version of it eventually reaches all currently legitimate replicas.

This property should not be expressed as “the original mutation always exists on all replicas”, because it may be legitimately overwritten by a Put or Delete with a higher timestamp.

### 11.4 Eventual completion of migration

If migration has entered Streaming, source/target nodes remain reachable, streaming and catch-up actions are fairly scheduled, and no writes indefinitely prevent the formation of a stable boundary, then migration eventually reaches activation conditions and finally enters Activated/Stable.

If new writes persist, the model may require each concrete write to eventually be included in some catch-up, without requiring the entire migration to necessarily terminate under an infinite write load.

### 11.5 Limitations on eventual request success

It must not be unconditionally verified that “every read/write request eventually succeeds”. In Cassandra, when replicas are unreachable, a network partition occurs, or the selected consistency level is too high, legitimate requests may fail or time out.

If eventual request success needs to be verified, environmental premises must be explicitly added, for example:

- a sufficient number of target replicas remain continuously responsive;
- the coordinator node remains continuously operational;
- request messages and response messages are eventually delivered;
- The corresponding actions satisfy fairness.

---

## 12. Official Documentation Basis and Scenario Correspondence

### 12.1 Partitions, token ring, vnode, and replica sets

Official basis:

- Apache Cassandra Documentation, “Dynamo”
- Link: https://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html

Corresponding modeling semantics:

1. Cassandra uses consistent hashing to map partition keys to the token ring;
2. token range maps to the same physical node replica set;
3. Physical nodes can have multiple tokens, i.e., vnodes;
4. Replicas must be different physical nodes;
5. Each Keyspace has a replication strategy and replication factor;
6. Cassandra is multi-master replication and should not be modeled as a single leader or single owner database.

### 12.2 LWW, mutation timestamp, and replica convergence

Official basis:

- Apache Cassandra Documentation, “Dynamo”
- Link: https://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html

Corresponding modeling semantics:

1. Each mutation carries a timestamp;
2. Cassandra uses last-write-wins for the same data;
3. Delete also carries a timestamp;
4. Different replicas can temporarily have different versions;
5. read repair, hinted handoff, and anti-entropy repair are used to promote replica convergence;
6. Merkle tree repair is one of the mechanisms that guarantee eventual synchronization.

### 12.3 Write path, commit log, memtable, and SSTable

Official basis:

- Apache Cassandra Documentation, “Storage Engine”
- Link: https://cassandra.apache.org/doc/latest/cassandra/architecture/storage-engine.html

Corresponding modeling semantics:

1. The write path sequentially includes commit log, memtable, flush, and SSTable;
2. When Cassandra accepts a write request, it writes data to CommitLog and memtable;
3. CommitLog is used for recovery after abnormal shutdown;
4. memtable can serve reads;
5. After flush, data is written to immutable SSTable;
6. periodic and batch commit log synchronization modes have different fsync acknowledgment semantics;
7. The first version model preserves logical append and application order, and does not model physical fsync and crash recovery.

### 12.4 Write Consistency, Read Consistency, and Quorum Intersection

Official basis:

- Apache Cassandra Documentation, “Dynamo”
- link: https://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html

Corresponding modeling semantics:

1. Write requests are sent to all replicas;
2. The write consistency level determines how many replica responses the coordinator node waits for;
3. Reads usually issue requests to a sufficient number of replicas to satisfy the read consistency level;
4. ONE, QUORUM, and ALL correspond to 1, majority, and all replica responses, respectively;
5. When `W + R > RF`, there is a replica intersection between the read and write quorums;
6. QUORUM writes and QUORUM reads can guarantee the visibility of acknowledged writes in typical configurations such as RF=3, provided that no higher version overwrites and routing migration remains safe;
7. ANY is used only for writes and may be satisfied by hints, so the first version base model does not include ANY.

### 12.5 Cassandra Consistency and LWT Boundaries

Official basis:

- Apache Cassandra Documentation, “Guarantees”
- link: https://cassandra.apache.org/doc/latest/cassandra/architecture/guarantees.html

Corresponding modeling semantics:

1. Cassandra is an eventually consistent storage system;
2. Single-table writes eventually propagate to all replicas;
3. LWT uses Paxos and provides linear consistency;
4. Ordinary read/write paths should not be incorrectly modeled as general linearly consistent transactions;
5. This specification's first version does not model LWT/Paxos.

### 12.6 Roles, Permissions, Permission Inheritance, and Authorization Modification

Official basis:

- Apache Cassandra Documentation, “Security”
- link：https://cassandra.apache.org/doc/latest/cassandra/managing/operating/security.html
- Apache Cassandra Documentation, “Database Roles”
- link：https://cassandra.apache.org/doc/latest/cassandra/developing/cql/security.html

Corresponding modeling semantics:

1. Cassandra uses database roles to represent users or user groups;
2. Permissions can be granted to a role;
3. A role can be granted to other roles, and permissions can be inherited;
4. Role grant relationships form a directed acyclic graph;
5. Data resources form a hierarchy by ALL KEYSPACES, KEYSPACE, and TABLE;
6. SELECT corresponds to read permissions;
7. MODIFY corresponds to INSERT, UPDATE, DELETE, and TRUNCATE;
8. AUTHORIZE corresponds to GRANT and REVOKE;
9. Permission modifications are visible to existing sessions;
10. After authorization is enabled, requests not explicitly granted are denied by default.

### 12.7 Bootstrap, decommission, move, replace, and cleanup

Official basis:

- Apache Cassandra Documentation, “Adding, replacing, moving and removing nodes”
- link：https://cassandra.apache.org/doc/latest/cassandra/managing/operating/topo_changes.html

Corresponding modeling semantics:

1. bootstrap assigns tokens to new nodes and makes them responsible for the corresponding ranges;
2. New nodes stream data from current replicas;
3. Under the default consistent range movement, unavailable replicas cause consistent bootstrap to fail;
4. decommission streams data from live nodes to other nodes;
5. removenode reconstructs data of failed nodes from remaining replicas;
6. move can be regarded as a range position change;
7. replace nodes may still require repair after bootstrap to catch up on missed in-progress writes;
8. Cassandra does not automatically delete data on old nodes after range movement; cleanup is explicitly performed by operations;
9. Therefore, model activation and cleanup must be separated.

### 12.8 Streaming and repair

Official basis:

- Apache Cassandra Documentation, “Improved Streaming”
- Link: https://cassandra.apache.org/doc/latest/cassandra/architecture/streaming.html
- Apache Cassandra Documentation, “Dynamo”
- Link: https://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html

Corresponding modeling semantics:

1. streaming is used for repair, host replacement, range movement, bootstrap, rebuild, and cluster expansion;
2. The physical unit of streaming can be an SSTable, but the model abstracts it as logical data version propagation;
3. repair is used to identify and synchronize inconsistencies among replicas;
4. decommission is protected when the replica count is below the configured RF, unless a forced option is used;
5. The model validates data coverage and safe switching, but does not validate throughput, rate limiting, Netty, Zero Copy, or SSTable component transmission.

---

## 13. Suggested module partition for the subsequent TLA+ model

The subsequent generated model is recommended to adopt the following module order. This order indicates dependency relationships, not runtime action order.

### 13.1 CCore

Responsibilities:

- Declare Principals, Nodes, Keyspaces, Tables, Partitions, DataItems, Mutations, Tokens, TokenRanges, Epochs;
- Define static mappings for Table, Partition, TokenRange, Keyspace, and Mutation;
- Define timestamp ordering, Mutation Put/Delete types, and LWW basic operators;
- Define `ReplicaSet(epoch, keyspace, range)`;
- Define core type constraints and static configuration assumptions.

### 13.2 CAuth

Responsibilities:

- Define roles, permissions, resource hierarchy, and optional role inheritance;
- Define valid permission determination for SELECT, MODIFY, AUTHORIZE;
- Define GrantPermission, RevokePermission;
- Define the restricted control-plane authorization check CanOperateTopology;
- Define authorization operation records and denied operation records;
- Define local properties of AuthSafety.

### 13.3 CWrite

Responsibilities:

- Define write requests, coordinator nodes, write consistency levels;
- Define WriteFrontier;
- Define `writeEpoch`, `writeReplicas`, pending-send state, ackSet, write-success state;
- Define ReceiveWrite, RejectWrite, ReplicaReceiveAndApply, ReplicaAck, CompleteWrite, WriteTimeout;
- Define CommitFrontier;
- Define write-path safety properties.

### 13.4 CReplica

Responsibilities:

- Define CommitLogged, MemtableApplied, and local LWW state for each replica;
- Define LocalPersistenceFrontier and ReplicaFrontier;
- Define PendingDelivery, Hint, or abstract synchronization state;
- Define SyncLateReplica, RepairOrSync;
- Define the property that replicas do not advance beyond WriteFrontier;
- Do not redeclare write acknowledgment states already defined by CWrite.

### 13.5 CRead

Responsibilities:

- Define read consistency levels ONE, QUORUM, ALL;
- Define read requests, read routing epoch, readReplicas, read-response sets, and read results;
- Define ReadRequest, RejectRead, ReplicaReadResponse, CompleteRead, ReadTimeout;
- Define the operation that performs LWW resolution on actual responses;
- Define specific read eligibility and result sets;
- Do not reference undefined final Frontier interface names.

### 13.6 CMigrate

Responsibilities:

- Define migration states Stable, Streaming, Activated, CleanupEligible;
- Define sourceEpoch, targetEpoch, sourceReplicas, targetReplicas;
- Define StartMigrate, RejectMigrate, StreamRangeData, CatchUpMigrate, ActivateMigrate, FinishMigrate, CleanupOldRangeData;
- Define underlying migration safety data required by MigrateFrontier;
- Define conditions under which target coverage has successfully acknowledged logical versions before migration activation;
- Do not use a single owner variable to replace Cassandra's multi-replica set.

### 13.7 CFrontierInterface

Responsibilities:

- Do not declare new state variables;
- Do not define actions that change state;
- Define uniformly based on preceding modules:
  - WriteFrontier；
  - LocalPersistenceFrontier；
  - ReplicaFrontier；
  - CommitFrontier；
  - QueryFrontier；
  - MigrateFrontier；
  - FinalQueryFrontier；
- Define FrontierSafety uniformly;
- Define conditional visibility properties under quorum intersections.

### 13.8 CIntegrated

Responsibilities:

- Combine all preceding modules;
- Define the global state variable set;
- Define Init;
- Define Next as the disjunction of all legal actions;
- Define global type invariants;
- Define composite properties such as AuthSafety, WritePathSafety, ReplicaSafety, ReadSafety, MigrateSafety, FrontierSafety;
- Provide action wrappers and checkable properties required for TLC finite instances.

---

## 14. Subsequent Model Generation Constraints

The following constraints must be observed when generating subsequent TLA+ models:

1. Cassandra must not be modeled as a single leader, single primary, or a system with a unique owner for each range;
2. token range, ReplicaSet, and activeEpoch must be used to represent routing and replica configuration;
3. writes must record the coordinator node, historical write epoch, historical write replica set, and write consistency level;
4. write requests must be logically sent to all target replicas; the write consistency level only controls the number of acknowledgments the coordinator waits for;
5. the commit log abstraction must precede memtable/applied state;
6. all replica applied data must come from WriteFrontier;
7. CommitFrontier may only contain mutations that reach the acknowledgment threshold of the write consistency level;
8. it must not be incorrectly required that all QueryFrontier data belongs to CommitFrontier;
9. successful read results must equal the complete LWW resolution result of the actual read response set;
10. successful read results must not be fixed to the empty set;
11. unauthorized read/write/migration must not modify protected state;
12. permission revocation must not retroactively negate historical successful operations;
13. migration must be represented by replica set and routing epoch switching;
14. before ActivateMigrate, it must be verified that the target replicas cover MigrateFrontier;
15. ActivateMigrate must not automatically delete old replica data;
16. Cleanup must be separated from migration activation;
17. ANY hint acknowledgments must not be mixed into the replica acknowledgment semantics of ONE, QUORUM, and ALL;
18. Raft, consensus leader, cross-partition transactions, or vector retrieval semantics not defined in this document must not be introduced;
19. each action must fully specify its modified variables and unmodified variables;
20. each safety property must be traceable to this specification, the Frontier method, or the listed Apache Cassandra official documentation basis.

---

## 15. Core Correctness Goals

Any logical DataItem returned by a successful read must satisfy:

1. the reading principal must have SELECT permission for the corresponding Table at the time the read is executed;
2. the returned version must come from actual responses in the current legal replica set for the read;
3. the version must have been written to the responding replica's local commit log abstraction;
4. The version has been applied to the memtable/local readable state by the responding replica;
5. The version belongs to WriteFrontier;
6. The number of read responses satisfies the requirements of ONE, QUORUM, or ALL;
7. The returned value is the winning Put resolved from the actual response versions according to Cassandra LWW rules;
8. If some higher timestamp Delete wins in the response set, then the data item must not be returned;
9. The replicas used for the read belong to a valid replica configuration under the current activeEpoch, or belong to an old routing configuration that remains valid during migration;
10. If migration has already been activated, then the logical winning version of successfully confirmed data has been covered by the new replica configuration;
11. The result equals the FinalQueryFrontier of the read, rather than any arbitrarily reduced subset.

Any successful write must satisfy:

1. The write principal has MODIFY permission at the time of write execution;
2. The coordinator node has fixed the target replica set according to the token range and the current routing epoch;
3. The mutation has entered WriteFrontier;
4. Each confirmed replica has completed local commit log abstraction and memtable application;
5. The number of confirmations satisfies the consistency level selected by the write request;
6. The mutation therefore enters CommitFrontier;
7. Subsequent replica synchronization and migration may only propagate the mutation or a valid overriding version with a higher timestamp, and must not fabricate data out of nothing.

Through the above boundaries, what the model verifies is not Cassandra's performance, query optimization, or underlying file implementation, but the key safety relationships among authorization, write, replica, read, and migration when Cassandra has tunable consistency, multi-replica asynchronous propagation, LWW version resolution, and range migration coexisting.
