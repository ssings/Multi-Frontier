# Cassandra Frontier-based Formal Modeling Specification

## 1. Modeling Objectives

This document defines the Frontier-based natural-language formal modeling specification for Apache Cassandra, intended for the subsequent automatic generation of Cassandra TLA+ models and TLC configurations.

The objective of the model is to verify the safety boundaries of Cassandra when partitioning, replication, tunable consistency, access control, and topology migration coexist. The model does not reproduce Cassandra source code, network protocols, or storage file implementations. Instead, it abstracts the following facts:

1. Data is hashed to a token ring according to partition keys, and token ranges determine replica sets.
2. Any node can act as a coordinator to receive client read and write requests.
3. The coordinator sends writes to all replicas in the current replica set of the partition but may report success to the client after receiving enough responses to satisfy the write consistency level.
4. Each replica independently records mutations, writes to the commit log, applies mutations to the memtable, and may subsequently converge with other replicas through hints, read repair, or anti-entropy repair.
5. A successful read must satisfy the number of responses required by the selected read consistency level. The coordinator reconciles the versions returned by participating replicas according to the Last-Write-Wins rule.
6. Bootstrap, decommission, move, replace, and streaming of token ranges can be uniformly represented as protected migration from an old replica configuration to a new replica configuration.
7. Successful operations must pass the corresponding authorization checks in Cassandra's role and permission model. Rejected operations must not modify protected data or topology state.
8. Data returned by any successful read must originate from locally applied versions held by actual serving replicas and must simultaneously satisfy read consistency and migration safety constraints.

In this document, "commit" only refers to the client write completion condition in the model, meaning that the coordinator has received sufficient acknowledgments to satisfy the write consistency level. It does not imply that Cassandra has a global atomic commit protocol across replicas. Except for lightweight transactions, ordinary Cassandra writes do not involve distributed transaction commits.

## 2. Abstraction Scope

### 2.1 Semantics Included in the Model

The model must include the following Cassandra semantics:

- A hierarchical abstraction of Keyspace, Table, Partition, and Row/Column mutations.
- The mapping from partition keys to tokens and from tokens to token ranges.
- Token range replica sets determined by Keyspace replication strategies.
- An abstraction of physical nodes, virtual nodes (vnodes), and multiple tokens belonging to the same node.
- Client principals, Cassandra roles, authenticated session identities, and authorization decisions.
- Coordinators receiving read and write requests.
- Commit log recording, memtable application, and replica acknowledgments for writes.
- Write consistency levels ONE, QUORUM, and ALL, with optional support for ANY, TWO, and THREE.
- Read consistency levels ONE, QUORUM, and ALL, with optional support for TWO, THREE, LOCAL_ONE, LOCAL_QUORUM, and EACH_QUORUM.
- Versioned mutations and Last-Write-Wins conflict resolution.
- A unified eventual synchronization abstraction for delayed propagation, hint replay, read repair, and anti-entropy repair among replicas.
- A unified migration abstraction for bootstrap, decommission, move, replace, streaming, and cleanup.
- Frontier relationships among writes, acknowledged writes, replica visibility, reads, migration, and final query results.
- Safety properties and liveness properties that can be verified under fairness assumptions.

### 2.2 Explicitly Excluded Content

The first version of the model does not include the following:

1. CQL syntax, query optimization, driver retry protocols, or native protocol details.
2. Gossip messages, the Phi Accrual Failure Detector algorithm, seed node discovery, or network handshakes between nodes.
3. Different local judgments of node UP/DOWN states. The model may use an abstract "set of responsive nodes" to represent their impact on read and write availability.
4. Commit log segments, fsync scheduling, disk file formats, SSTable file components, Bloom filters, compression, compaction, or cache implementations.
5. Internal steps for flushing memtables to SSTables. Flush may be represented as an optional persistence action that does not change logical data versions.
6. Cross-partition transactions, distributed joins, foreign keys, or referential integrity.
7. The Paxos protocol of lightweight transactions (LWT) and linearizable CAS semantics.
8. Logged batches, batchlog, counters, materialized views, secondary indexes, SAI, user-defined functions, or aggregations.
9. Specialized behavior of transient replication.
10. TLS, password hashing, authentication handshakes, JMX permissions, or audit log implementations.
11. File chunking in actual streaming, the Netty threading model, zero-copy transfers, or bandwidth throttling.
12. Complete command semantics of operational tools. For example, `nodetool` commands are represented only through abstract topology management actions.
13. The complete timing behavior of node crashes, process restarts, and commit log replay. The first version may exclude node crashes from the state space. If crashes are subsequently included, synchronized and unsynchronized commit log states must be distinguished. In particular, `commitlog_sync=periodic` must not be incorrectly abstracted as every acknowledgment having already been fsynced.

## 3. Core Entities and Static Mappings

### 3.1 Principal, Role, and Session

`Principal` represents the logical entity initiating a request. It corresponds to an authenticated Cassandra role, user, or service identity.

The model must include at least:

- `Principals`: The set of principals.
- `Roles`: The set of Cassandra database roles.
- `principalRole`: A mapping from principals to authenticated roles.
- `loginEnabled`: Whether a role has LOGIN capability.
- `superuser`: Whether a role has SUPERUSER status.
- `roleMembership`: The role-grant relationship used to represent role inheritance. This relationship must be acyclic.
- `effectivePermissions`: The effective permissions obtained by a role through direct grants, inherited roles, and propagation through the resource hierarchy.

The first version may directly equate a Principal with an authenticated role, but it must preserve the semantics that permissions belong to roles rather than to physical nodes.

### 3.2 Keyspace, Table, and Resource Hierarchy

`Keyspace` is the scope of replication strategies and an important boundary in the permission hierarchy. A `Table` belongs to a Keyspace.

At least the following must be defined:

- `Keyspaces`
- `Tables`
- `tableKeyspace : Table -> Keyspace`

Permission resources may be abstracted at the following levels:

- All Keyspaces;
- A specific Keyspace;
- A specific Table.

For the data read and write scenarios in this model:

- `SELECT` represents permission to read Table data;
- `MODIFY` represents permission to modify Table data through INSERT, UPDATE, DELETE, TRUNCATE, and other operations;
- `AUTHORIZE` represents permission to grant or revoke permissions on a resource;
- `SUPERUSER` may bypass ordinary permission checks in the model.

The first version does not need to fully implement all CQL permissions, such as CREATE, ALTER, DROP, DESCRIBE, EXECUTE, UNMASK, and SELECT_MASKED, but these permissions must not be incorrectly interpreted as SELECT or MODIFY.

### 3.3 Partition, Token, and Token Range

`Partition` represents a data partition located by a partition key. All ordinary reads and writes modeled are restricted to a single Partition.

At least the following must be defined:

- `Partitions`
- `partitionTable : Partition -> Table`
- `partitionKey`: An abstract identifier of the partition key.
- `partitionToken : Partition -> Token`
- `TokenRanges`
- `rangeOfToken : Token -> TokenRange`
- `partitionRange : Partition -> TokenRange`

The following must be maintained:

- A Partition belongs to exactly one Table;
- A Partition's token maps to exactly one TokenRange;
- Partitions within the same TokenRange share the same replica configuration.

The model does not need to implement the actual Murmur3 hash algorithm. `partitionToken` may be a finite mapping provided by configuration constants, but it must express that Partition routing is determined by token ranges.

### 3.4 Node, Token, and vnode

`Node` represents a physical node or endpoint in a Cassandra cluster.

At least the following must be defined:

- `Nodes`
- `Tokens`
- `tokenNode : Token -> Node`
- `nodeTokens : Node -> SUBSET Token`
- `nodeAvailable : Node -> BOOLEAN`, or an equivalent responsive state.
- `nodeDatacenter : Node -> Datacenter`
- `nodeRack : Node -> Rack`, if the model needs to check multi-datacenter or rack-aware replica selection.

Multiple Tokens may map to the same Node to abstract Cassandra vnodes. The model must not assume that "one node owns only one token."

### 3.5 Replica Set and Replication Strategy

For each Keyspace and TokenRange, the replication strategy determines a set of replica nodes:

\- `replicaSet : Keyspace -> TokenRange -> SUBSET Node`

Alternatively, an equivalent mapping with topology epochs may be used:

\- `activeReplicaSet : TopologyEpoch -> Keyspace -> TokenRange -> SUBSET Node`

The model must satisfy the following:

1. Replica sets are nonempty.
2. Replicas of the same TokenRange are distinct physical nodes.
3. The number of replicas is constrained by the replication factor of the corresponding Keyspace.
4. Reads and writes target the replica set corresponding to the Keyspace of the Table to which the Partition belongs.
5. The same node may participate in the replica sets of multiple TokenRanges because of vnodes.

The first version does not need to fully compute the node-selection algorithms of `SimpleStrategy` or `NetworkTopologyStrategy`. Replica sets may be provided by configuration, but they must satisfy the replica-set semantics described above. If multi-datacenter consistency levels are modeled, a mapping from replica nodes to datacenters must also be provided.

### 3.6 Data Item, Mutation, and LWW Version

`DataItem` represents the smallest logical data unit in the model. It is recommended to abstract it as the current value of a logical cell or row-column position within a Partition of a Table.

At least the following must be defined:

- `Items`
- `itemPartition : Item -> Partition`
- `itemTable : Item -> Table`
- `itemRange : Item -> TokenRange`
- `Mutations`
- `mutationItem : Mutation -> Item`
- `mutationVersion : Mutation -> Version`
- `mutationKind : Mutation -> {Value, Tombstone}`

Here, `Version` must have a total order or a deterministic ordering that can identify a winner. Ordinary Cassandra mutations use timestamps and resolve conflicts according to the Last-Write-Wins rule. Deletions also have timestamps. Therefore:

1. For the same Item, a mutation with a higher version overrides one with a lower version.
2. Tombstone is also a mutation and must participate in version comparisons.
3. The model must not treat deletion simply as "stateless removal"; otherwise, it cannot express the LWW relationship between deletions and old writes.
4. If a finite TLA+ model needs to resolve identical timestamps, it may introduce a stable auxiliary ordering key to establish a deterministic total order. This auxiliary ordering is used only to resolve ambiguity in the model and must not be described as additional business semantics of Cassandra's official timestamp rules.

Define:

- `Winner(S)`: The LWW-winning mutation for the same Item in set `S`.
- `VisibleValue(S, item)`: The value when `Winner(S)` is `Value`; if the winner is Tombstone, the Item appears deleted when read.

## 4. Authorization, Permission Changes, and Rejected Operations

### 4.1 Authorization Decisions

Define the abstract predicates:

- `CanSelect(principal, table, coordinator)`
- `CanModify(principal, table, coordinator)`
- `CanAuthorize(principal, resource, coordinator)`
- `CanManageTopology(principal)`

Where:

1. `CanSelect` is based on the effective `SELECT` permission of the role.
2. `CanModify` is based on the effective `MODIFY` permission of the role.
3. `CanAuthorize` is based on the effective `AUTHORIZE` permission of the role or SUPERUSER status.
4. `CanManageTopology` is an abstraction of authorization for operational control-plane actions such as bootstrap, decommission, move, and replace. It must not be incorrectly described as an ordinary Table permission named `MIGRATE` in Cassandra CQL.
5. SUPERUSER may be abstracted as possessing all necessary permissions on the corresponding resources.

Cassandra authorization data may be cached. To represent this faithfully, it is recommended to distinguish:

- `permissionStore`: The authoritative permission state.
- `authView[node]`: The permission view currently used by a coordinator for authorization decisions.
- `RefreshAuthCache(node)`: An action that causes a node's permission view to converge toward the authoritative state.

Authorization safety for successful operations must be evaluated according to the authorization view actually used by the coordinator when the operation was executed. Permission states that may have changed afterward must not be used to retroactively invalidate historical operations.

### 4.2 Grant and Revoke

The model should include:

- `GrantPermission(admin, targetRole, resource, permission)`
- `RevokePermission(admin, targetRole, resource, permission)`

Preconditions:

- `admin` has `AUTHORIZE` permission on the target resource or an appropriate parent resource, or is a SUPERUSER;
- The permission being granted is applicable to the resource type;
- The role inheritance relationship remains acyclic.

Permission changes affect subsequent authorization checks. Historical read, write, or migration actions that have already completed successfully must retain the authorization results from their execution time. A subsequent Revoke must not cause such historical records to become "unauthorized successful operations" in safety properties.

### 4.3 Unauthorized and Non-Executable Operations

The model must explicitly include the following rejection branches:

- `RejectWrite`
- `RejectRead`
- `RejectGrantOrRevoke`
- `RejectTopologyChange`
- Optional `RejectUnavailableWrite`
- Optional `RejectUnavailableRead`

Unauthorized writes must not modify:

- Request acceptance state;
- Commit log;
- Memtable or replica-applied state;
- Replica acknowledgment set;
- Hints;
- Migration state;
- Current token range replica configuration.

Unauthorized reads must return an empty result or an explicit rejection result. They must not generate fabricated data or advance replica, repair, or migration states.

Unauthorized migration must not modify:

- The current replica set of the token range;
- Migration sources, targets, or phases;
- Streamed data;
- Serving route configuration.

Each type of most-recent-operation record must store at least:

- Operation type;
- Principal;
- Target Table or TokenRange;
- Coordinator or execution node;
- Authorization check result;
- Whether the operation executed successfully;
- The consistency level for read and write operations;
- The returned result for read operations;
- The migration phase for topology operations.

## 5. Write Path Specification

### 5.1 Write Requests and Coordinators

Any available Node can act as the coordinator for a write to a Partition. The coordinator does not need to be a replica of that Partition.

A write request must contain at least:

- `principal`
- `coordinator`
- `item`
- `mutation`
- `writeConsistencyLevel`

Before a write begins, the following conditions must be satisfied:

1. `principal` has satisfied the authentication prerequisites in the model.
2. `CanModify(principal, itemTable[item], coordinator)` is true.
3. `coordinator` is available to receive client requests.
4. The Item, Table, Partition, and TokenRange mappings of the mutation are consistent.
5. The mutation version belongs to the Version domain defined by the model.

The coordinator determines the target replica set according to `itemRange` and the current `activeReplicaSet`. Ordinary writes must be modeled as "sending to all replicas in the current replica set," rather than sending only to the minimum number of replicas needed to satisfy the write consistency threshold.

### 5.2 Replica-Local Write State

Each replica node must maintain at least the following abstract states for each mutation:

- `commitLog[node]`: The set of mutations recorded by the node.
- `memtable[node]`: The logical mutations applied by the node or the current version of an Item.
- `replicaApplied[node]`: The set of mutations that the node has completed applying locally.
- `replicaAcked[mutation]`: The set of replica nodes that have sent successful responses to the coordinator.
- `hintStore[node]`: The set of hints stored by the coordinator or a proxy node that have not yet been replayed.

When a local replica receives a mutation, it must follow this logical order:

1. The mutation enters the node's commit log.
2. The mutation is subsequently applied to the memtable.
3. The memtable retains the LWW winner for the same Item.
4. The replica may acknowledge the coordinator only after satisfying the local write conditions specified by the model.

The model may separate "commit log recording" and "memtable application" into two actions or advance them simultaneously in one atomic action, but it must preserve the safety relationship that commit log recording precedes or occurs simultaneously with memtable application.

### 5.3 Commit Log Synchronization Modes

Cassandra's `commitlog_sync=batch` and `commitlog_sync=periodic` have different persistence boundaries at acknowledgment time.

The model should support the following parameterized descriptions:

- `Batch` mode: Before a replica acknowledges, the relevant commit log has been synchronized to the persistence boundary.
- `Periodic` mode: A replica may acknowledge before the commit log is periodically synchronized. If the crash model is subsequently extended, such acknowledgments must not be assumed to survive sudden failures.

If the first version does not model crash recovery, the commit log may be abstracted as a local ordered record, checking only that "recording precedes application." However, this must not be used to infer the unmodeled property that "all client-successful writes have already been fsynced."

### 5.4 Write Consistency Levels and Client Success Conditions

For a write, let:

- `N` be the size of the current replica set of the Partition;
- `A` be the set of distinct actual replica nodes that have acknowledged the mutation;
- `W(level, N)` be the minimum number of actual replica acknowledgments required by the write consistency level.

At least the following must be supported:

| Write Consistency Level | Success Condition                                              |
| ----------------------- | -------------------------------------------------------------- |
| ONE                     | `Cardinality(A) >= 1`                                          |
| QUORUM                  | `Cardinality(A) >= floor(N / 2) + 1`                           |
| ALL                     | `A` covers the current replica set, i.e., `Cardinality(A) = N` |

Optional support:

| Write Consistency Level | Success Condition                                                                |
| ----------------------- | -------------------------------------------------------------------------------- |
| TWO                     | At least two distinct replicas acknowledge                                       |
| THREE                   | At least three distinct replicas acknowledge                                     |
| LOCAL_ONE               | At least one replica in the local datacenter acknowledges                        |
| LOCAL_QUORUM            | A majority of replicas in the local datacenter acknowledge                       |
| EACH_QUORUM             | Each datacenter independently reaches a local replica majority                   |
| ANY                     | At least one actual replica acknowledges, or a hint has been successfully stored |

For ONE, QUORUM, ALL, TWO, THREE, LOCAL_ONE, LOCAL_QUORUM, and EACH_QUORUM, acknowledgments must come from actual target replicas.

For ANY:

1. ANY is permitted only for writes and not for reads.
2. If no actual replica can acknowledge, the coordinator may satisfy ANY by successfully storing a hint.
3. A write that satisfies ANY only through a hint must not be treated as having already been applied by any actual data replica.
4. The hint must subsequently be delivered to the target replica through a replay action or explicitly included within the scope of protection in migration safety conditions.

### 5.5 Write Completion State

It is recommended to distinguish the following sets rather than using a single "committed" set:

- `WriteFrontier`: Mutations that have passed authorization, been accepted by the coordinator, and entered the write propagation path.
- `ReplicaFrontier(node)`: Mutations that the node has recorded and applied to its local logical state.
- `AckFrontier(level)`: Mutations that have satisfied the corresponding write consistency level and for which success has been returned to the client.
- `HintFrontier`: Mutations stored as hints but not yet applied by actual replicas.

After an ordinary write succeeds, the mutation must enter the corresponding `AckFrontier(level)`. This indicates that the client has received a successful response at that consistency level, not that all replicas already possess the mutation.

The following must be maintained:

1. A mutation applied by a replica must already have entered `WriteFrontier`.
2. Replica acknowledgments must correspond to mutations applied by those replicas.
3. Successful writes must satisfy the acknowledgment thresholds of their consistency levels.
4. Successful acknowledgments for non-ANY writes must come from actual replicas.
5. If an ANY write succeeds through a hint, the hint must be explicitly recorded as the basis for success instead of fabricating replica acknowledgments.
6. All acknowledging replica nodes must belong to the target replica set of the write at its topology epoch.

## 6. Replica Propagation, Lagging Replicas, and Eventual Synchronization

### 6.1 Replica Divergence

Because each replica can independently receive mutations, some replicas may temporarily lag behind or hold older versions of the same Item. The model must permit the following states:

- A write has satisfied ONE or QUORUM, but not all replicas have applied it;
- Different replicas hold different versions of the same Item;
- A replica is currently unavailable and cannot immediately receive a mutation;
- The coordinator has reported success to the client, but some replicas remain behind.

These states are consistent with Cassandra's tunable consistency and eventual consistency semantics and must not be incorrectly prohibited by invariants.

### 6.2 Synchronization Actions

The model must include at least one unified delayed-synchronization action:

\- `SyncReplica(mutation, targetReplica)`

Its preconditions must include at least:

1. The mutation has entered `WriteFrontier`.
2. `targetReplica` is a replica of the TokenRange to which the Item belongs under the relevant topology epoch, or a legitimate target replica during migration.
3. `targetReplica` does not currently hold the mutation, or its current version of the corresponding Item is lower than that of the mutation.
4. The mutation originates from a legitimate replica, hint, or repair source.

Its effects are:

1. The commit log and memtable of `targetReplica` receive the mutation.
2. The LWW state of `targetReplica` advances to the winner between the mutation and the existing version.
3. The `ReplicaFrontier` of `targetReplica` includes the mutation.
4. If synchronization originates from a hint, the corresponding hint may be removed after successful replay.

### 6.3 Abstraction of Hinted Handoff, Read Repair, and Repair

The model does not need to reproduce the internal protocols of these three mechanisms separately, but it must preserve their different roles:

- `HintReplay`: Delivers a stored hint to the replica that was originally supposed to receive the write.
- `ReadRepair`: When a read detects inconsistent replica versions, propagates the reconciled newer version to lagging replicas.
- `AntiEntropyRepair`: Replicas synchronize inconsistent data after comparing summaries of data ranges. The model may abstract Merkle tree comparison as "detecting differences and selecting missing mutations for synchronization."

All three mechanisms can advance replica convergence but must not be modeled as synchronous prerequisites for successful reads or writes unless the corresponding operation's consistency level requires otherwise.

### 6.4 Replica Version Correctness

For every replica node and Item:

1. The replica's current version must originate from a mutation applied by that replica.
2. A replica must not produce mutations that have not entered `WriteFrontier`.
3. Replica synchronization can only increase the set of visible mutations or replace an older mutation with a higher LWW version.
4. The logical value of the replica's state must equal the LWW winner of its set of applied mutations for that Item.
5. Older versions may be overridden by higher versions. Therefore, "every replica always retains all historical versions" is not a model requirement.

## 7. Consistent Read Specification

### 7.1 Read Coordination

Any available Node can act as a read coordinator. A read request must contain at least:

- `principal`
- `coordinator`
- `partition` or the Partition to which the Item belongs
- `readConsistencyLevel`
- An optional set of target Items to query

Before reading, the following check must pass:

\- `CanSelect(principal, table, coordinator)`

The coordinator selects a sufficient number of replicas from the current `activeReplicaSet` to receive read requests. The model may allow the coordinator to send redundant reads, such as by abstracting speculative retries, but only replicas that actually respond successfully can count toward the read success condition.

### 7.2 Read Consistency Levels

Let:

- `N` be the size of the current serving replica set;
- `R` be the set of distinct replicas returning valid read responses for the request;
- `RequiredRead(level, N)` be the minimum number of responses required for the read.

At least the following must be supported:

| Read Consistency Level | Success Condition                          |
| ---------------------- | ------------------------------------------ |
| ONE                    | `Cardinality(R) >= 1`                      |
| QUORUM                 | `Cardinality(R) >= floor(N / 2) + 1`       |
| ALL                    | `R` covers the current serving replica set |

Optional support may be provided for TWO, THREE, LOCAL_ONE, LOCAL_QUORUM, and EACH_QUORUM. ANY must not appear in the set of read consistency levels.

If there are insufficient responsive replicas, the read must take an unavailable or failure branch and must not fabricate a successful result without satisfying the consistency level.

### 7.3 Read Results and LWW Reconciliation

For each Item being read, the version returned by a successful read must be the LWW winner over the states of the replicas participating in the read response.

Define:

- `ReadResponders(req)`: The set of replicas that actually participate in and successfully respond to the read.
- `ReadReplicaState(req, item)`: The set of mutations returned by these replicas for the Item.
- `ReadWinner(req, item)`: The LWW winner of that set.

Successful read results must satisfy:

1. Results originate only from the applied state of at least one replica in `ReadResponders(req)`.
2. Results must equal `ReadWinner(req, item)` rather than arbitrarily selecting an older response.
3. If `ReadWinner(req, item)` is a Tombstone, the Item appears deleted or nonexistent in the result.
4. Read results must not contain mutations that are not held by any responding replica.
5. Read results must not automatically exclude a mutation merely because the write has not reached the client success threshold. In Cassandra, a mutation that has been applied by a replica but has not satisfied the client success condition of a particular write request may still be observed by subsequent reads.

### 7.4 Conditional Guarantees of Write-Read Quorum Intersection

For the same topology epoch, the same TokenRange, and in the absence of interfering concurrent mutations with higher versions:

- If a non-ANY write has received acknowledgments from `W` distinct actual replicas;
- A subsequent successful read receives responses from `R` distinct replicas;
- And `W + R > N`;

Then the read replica set and the write acknowledgment replica set must intersect. The coordinator performs LWW reconciliation of response versions during the read, so the read result should observe that write version or a subsequent mutation with a higher version.

This property applies to combinations with intersecting replica sets, such as QUORUM/QUORUM. ONE/ONE does not provide this guarantee. The model must not incorrectly abstract Cassandra's eventual consistency as "any successful read always sees the most recent successful write."

## 8. Data Range Migration Specification

### 8.1 Unified Migration Object

The migration unit is `TokenRange`, not an individual Item. Migration of a TokenRange affects the replica configurations of all Partitions and Items within that range.

Define:

- `activeReplicaSet[range]`: The replica set currently serving clients.
- `plannedReplicaSet[range]`: The replica set expected to become effective after migration completes.
- `migrateState[range]`
- `migrateSources[range]`
- `migrateTargets[range]`
- `streamedMutations[range][target]`
- `migrateEpoch[range]`
- `topologyEpoch`

`activeReplicaSet` represents the replica set that should be used for current routing. It must not be incorrectly modeled as a single "Shard Owner," because a Cassandra TokenRange is typically stored and served jointly by multiple replicas.

If it is necessary to represent the primary node on the ring, `primaryReplica[range]` may be additionally defined, but this variable must not weaken the semantics that "all replicas can independently accept mutations for the key."

### 8.2 Migration States

The first version uses the following phases:

- `Stable`: No migration is in progress, and the current replica set serves normally.
- `Streaming`: Source replicas or other legitimate replicas are transferring TokenRange data to target nodes. The old serving configuration remains valid for clients.
- `ReadyToActivate`: The target replicas have reached the data coverage boundary required for the switch.
- `Activated`: The new replica configuration has become the current serving configuration.
- `CleanupPending`: An optional phase in which old nodes may still retain redundant data pending explicit cleanup.
- `Stable`: The system returns to a stable state after cleanup completes or when cleanup is unnecessary.

To control the state space, `ReadyToActivate` and `Activated` may be combined, but if they are combined, the activation action must atomically check the target coverage conditions and update the serving replica configuration.

### 8.3 Unified Migration Sources

The following Cassandra scenarios are all represented in the model as changes to the replica configuration of a TokenRange:

| Cassandra Scenario | Unified Abstraction                                                                                                                    |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| Bootstrap          | A new node acquires tokens and streams the data of the ranges it will become responsible for from current replicas                     |
| Decommission       | Ranges belonging to a departing node are taken over by other nodes, with data transferred from the departing node or existing replicas |
| Remove dead node   | Remaining replicas copy data to the new replica configuration                                                                          |
| Move               | The token position of a node changes, triggering redistribution of old and new ranges                                                  |
| Replace            | A new node replaces a failed node and bootstraps data from other replicas                                                              |
| Rebuild            | Streaming synchronization that reacquires replica data                                                                                 |
| Repair streaming   | Synchronization of inconsistent data within a replica's range                                                                          |

The model must preserve the source constraints of different scenarios:

- Bootstrap streams data by default from current primary replicas or legitimate current replicas;
- Decommission may stream data from the node being decommissioned;
- Dead node removal/replacement must rely on other remaining available replicas;
- Writes during the replacement window may be missed, so subsequent repair or catch-up must be abstracted as potentially necessary synchronization steps;
- According to the official documentation, move applies when `num_tokens: 1`. The first version does not need to verify this operational prerequisite, but it must not describe move as fully equivalent to official behavior under arbitrary vnode configurations.

### 8.4 Starting Migration

The preconditions of `StartMigrate(principal, range, plannedSet)` must include at least:

1. `CanManageTopology(principal)` is true.
2. `migrateState[range] = Stable`.
3. `plannedSet` is nonempty and satisfies the replica count and physical node distinctness constraints of the replication strategy.
4. The difference between `plannedSet` and the current `activeReplicaSet[range]` corresponds to bootstrap, decommission, move, replace, or equivalent redistribution.
5. The source set consists of current replicas, legitimate remaining replicas, or nodes proven to hold data for the range.
6. Multiple conflicting migrations must not simultaneously change the serving configuration of the same TokenRange.

Effects:

- `migrateState[range] := Streaming`;
- Fix the `migrateEpoch` for this migration;
- Record the current serving replica set as the migration source semantics;
- Set `plannedReplicaSet[range]`;
- Initialize the receiving state of target nodes;
- The old `activeReplicaSet[range]` continues to serve as the read and write configuration before activation.

### 8.5 Streaming and Catch-Up

`AdvanceMigrate(range, source, target)` copies legitimate mutations already held by the source to the target.

The model may use an all-at-once copying abstraction or advance one mutation at a time, but it must satisfy:

1. The target may obtain only mutations that have entered `WriteFrontier`.
2. After receiving data, the target merges its logical state according to the LWW rule.
3. Old replicas may continue processing writes during streaming.
4. If new mutations occur during migration, the model must allow the target to catch up through subsequent catch-up, hint replay, repair, or additional streaming actions.
5. The model must not unconditionally activate the new configuration after merely copying a static snapshot taken at migration initiation. Gaps caused by new writes during migration must be handled before activation.

### 8.6 MigrateFrontier and Activation Conditions

Define `MigrateFrontier(range)` as the data boundary that must be safely covered by the new serving configuration at the current migration switch point. It includes at least:

1. LWW-winning versions within the TokenRange that may be read from the current serving replicas at activation time;
2. Necessary versions corresponding to writes that have satisfied client success conditions;
3. Versions already applied by replicas that may be observed by reads even though a particular write request did not receive client success;
4. Mutations corresponding to hints that have not yet been replayed but previously succeeded at ANY, unless those mutations have been explicitly excluded from the switchover scope. The recommended approach is to require that target replicas actually receive them before activation or that they remain protected as replayable state.

The preconditions of `ActivateMigrate(range)` must include:

1. `migrateState[range] = Streaming` or `ReadyToActivate`;
2. For every necessary target node that will become a new serving replica, its received and applied data covers `MigrateFrontier(range)`;
3. There are no unprotected write gaps between the current serving replica configuration and the planned new configuration;
4. The new configuration satisfies the basic constraints of the replication strategy;
5. Activation and serving route updates occur atomically in the model, or an explicit epoch mechanism ensures that reads and writes do not use inconsistent mixed configurations.

Activation effects:

- `activeReplicaSet[range] := plannedReplicaSet[range]`;
- Advance `topologyEpoch` or the epoch of the range;
- `migrateState[range] := Activated`;
- Subsequent new reads and writes are routed according to the new serving replica configuration.

### 8.7 Cleanup

The official documentation states that after range movement such as bootstrap, move, or replace, nodes that lose responsibility for some ranges do not automatically delete the old data. Operators may execute `nodetool cleanup` after confirming that the new nodes are functioning properly.

Therefore, `CleanupMigrate(range)` in the model must satisfy:

1. It executes only after the new replica configuration has been activated.
2. It must not delete data still needed for serving from replicas required by the current `activeReplicaSet[range]`.
3. Cleaning redundant replica data from old nodes must not delete the only remaining copy of any data belonging to `MigrateFrontier(range)`.
4. Cleanup may be delayed or never executed. Retention of old data is not a safety error.

## 9. Layered Frontier Definitions

### 9.1 WriteFrontier

`WriteFrontier` represents the set of mutations that have passed authorization, been accepted by the write path, and can be relied upon by replica propagation or migration synchronization.

Only after a mutation enters `WriteFrontier` may it:

- Be recorded in a replica's commit log;
- Be applied to a memtable;
- Be recorded as a replica acknowledgment;
- Be stored as a hint;
- Be copied through streaming or repair;
- Be read, provided it has actually been applied by a responding replica.

`WriteFrontier` is not equal to the set of client-successful writes. It may contain mutations that subsequently fail to reach the selected write consistency level, because some replicas may already have applied those mutations.

### 9.2 AckFrontier

`AckFrontier(level)` represents the set of mutations for which the coordinator has reported success to the client according to a particular write consistency level.

For non-ANY writes:

\- The mutation must be acknowledged by no fewer than `W(level, N)` distinct actual replicas.

For ANY:

\- The mutation may satisfy the condition through one actual replica acknowledgment or successful storage of a hint.

`AckFrontier` is the "client completion boundary," not the boundary indicating that all replicas already hold the data.

### 9.3 ReplicaFrontier

`ReplicaFrontier(node)` represents the set of mutations that a node has accepted and applied through its local commit log and memtable path.

The following must be maintained:

- `ReplicaFrontier(node)` is a subset of `WriteFrontier`;
- Any replica acknowledgment may correspond only to a mutation in `ReplicaFrontier(node)`;
- The logical readable state of a node for an Item is determined by the LWW winner of the corresponding mutations within its `ReplicaFrontier(node)`.

### 9.4 QueryFrontier

`QueryFrontier(request)` is a request-dependent boundary rather than a globally fixed set independent of read requests.

For a successful read request, it is determined by:

1. The current serving replica set;
2. The set of replicas that actually respond;
3. The selected read consistency level;
4. The mutations applied by each responding replica;
5. The LWW reconciliation result for each Item.

Therefore:

- Every returned mutation in `QueryFrontier(request)` must originate from the `ReplicaFrontier` of at least one replica in `ReadResponders(request)`;
- It does not require the same mutation to exist on all responding replicas;
- It does not require a mutation to belong to a client-successful write;
- It must not exceed the version boundaries actually held by responding replicas.

### 9.5 MigrateFrontier

`MigrateFrontier(range)` represents the data boundary that must be covered by the new configuration before switching the serving replica configuration of a TokenRange.

It constrains:

- Data that streaming targets may obtain;
- Catch-up completion conditions;
- Activation conditions for the new replica configuration;
- Retention requirements for old replicas before cleanup.

During migration, the old `activeReplicaSet` continues serving. After activation, the new `activeReplicaSet` must cover this boundary.

### 9.6 FinalQueryFrontier

`FinalQueryFrontier(request)` represents the boundary of data that a successful read is ultimately permitted to return. It simultaneously satisfies:

1. The requesting principal has SELECT permission in the coordinator's current authorization view;
2. The number of read responses reaches the request's consistency level;
3. The data originates from the `ReplicaFrontier` of actual responding replicas;
4. The returned value is the LWW winner of the responding replicas' states;
5. The replicas used for reading belong to the current serving replica configuration;
6. If the TokenRange is undergoing migration or has just completed migration, the serving replica configuration satisfies the corresponding `MigrateFrontier`;
7. The returned value has not been superseded by a higher-version Tombstone or Value within the response set.

The result of a successful read must equal the projection of its `FinalQueryFrontier(request)` onto the requested Item set, rather than an arbitrary subset. This "complete set of eligible return values" requirement prevents the model from evading verification by always returning an empty result.

### 9.7 Frontier Relationships

The following core relationships must be verified:

1. `ReplicaFrontier(node) ⊆ WriteFrontier`
2. `AckFrontier(level) ⊆ WriteFrontier`
3. Replica acknowledgments correspond only to mutations in `ReplicaFrontier`.
4. Every element of `QueryFrontier(request)` originates from a `ReplicaFrontier` of a replica in `ReadResponders(request)`.
5. `MigrateFrontier(range) ⊆ WriteFrontier`
6. The new serving replica configuration after activation covers `MigrateFrontier(range)`.
7. `FinalQueryFrontier(request)` is simultaneously constrained by authorization, read consistency, replica state, LWW reconciliation, and migration safety.
8. Successful read results equal the request projection of `FinalQueryFrontier(request)`.

## 10. Safety Properties to Be Verified

### 10.1 Type and Mapping Safety

The model must always maintain:

- Type correctness of Item, Partition, Table, Token, TokenRange, Node, Role, Mutation, and version mappings.
- Each Item belongs to exactly one Partition, Table, and TokenRange.
- Each current replica node belongs to the current replica set of the corresponding TokenRange.
- Replica sets are nonempty and contain distinct nodes.
- Token and vnode mappings allow multiple tokens to correspond to the same Node.
- Planned replica sets during migration satisfy the abstract constraints of the replication strategy.

### 10.2 Authorization Safety

1. Successful writes must pass the MODIFY check at execution time.
2. Successful reads must pass the SELECT check at execution time.
3. Successful permission changes must pass the AUTHORIZE or SUPERUSER check.
4. Successful topology migrations must pass the operational management authorization check.
5. Unauthorized actions must not modify protected data, acknowledgments, hints, or topology state.
6. Historical successful operations must record the authorization decision at execution time. Subsequent permission revocations must not retroactively turn them into violations.
7. If the permission cache abstraction is enabled, safety properties must be based on the `authView[coordinator]` actually used for authorization checks, rather than assuming that global permissions take effect immediately without refreshing.

### 10.3 Write Path Safety

1. `MemtableAfterCommitLog`: Any mutation applied by a replica must have been recorded in that replica's commit log beforehand or simultaneously.
2. `ReplicaNotAheadOfWrite`: Any mutation applied by a replica belongs to `WriteFrontier`.
3. `AckAfterApply`: Replica acknowledgments correspond only to mutations applied by the acknowledging replicas.
4. `WriteLevelSatisfied`: For every successful non-ANY write, the number of actual replica acknowledgments reaches the requested write consistency level.
5. `AnyHintDistinguished`: When ANY succeeds through a hint, actual replica acknowledgments must not be fabricated.
6. `LWWLocalState`: The current value of each Item on a replica equals the LWW winner of its locally applied mutations.

### 10.4 Read Safety

1. `ReadAuthorizationSafety`: A successful read was authorized at execution time.
2. `ReadResponseThreshold`: The number of responding replicas for a successful read reaches the selected read consistency level.
3. `ReadFromCurrentReplicas`: Responding replicas belong to the current serving replica set at the time of the request.
4. `ReadNoFabrication`: Every version in the read result is actually held by at least one responding replica.
5. `ReadLWWReconciliation`: The read result equals the LWW reconciliation result of the responding replicas' versions.
6. `ReadNoUnauthorizedLeak`: Unauthorized reads cannot return data.
7. `ReadFrontierSafety`: Successful read results equal the request projection of `FinalQueryFrontier(request)`.

### 10.5 Quorum Intersection Safety

Check the conditional property under the following prerequisites:

- The same TokenRange;
- The same topology epoch;
- A non-ANY write;
- No concurrent mutations with higher versions;
- The number of successful write acknowledgments is `W`;
- The number of successful read responses is `R`;
- `W + R > N`.

Then the response set of a successful read must intersect with the acknowledged write set, and the read result must contain that write or a higher LWW version.

This property must explicitly be stated as conditional. The model must not incorrectly claim that ONE/ONE, ANY/ONE, or arbitrary read/write combinations across different replica configuration epochs provide strong read-your-writes guarantees.

### 10.6 Migration Safety

1. `NoUnsafeActivation`: The new target replica configuration must not be activated before it covers `MigrateFrontier`.
2. `OldConfigServesBeforeActivation`: During migration streaming, the old serving replica configuration remains available for serving requests.
3. `NewConfigCoversAfterActivation`: After activation, the new serving replica configuration covers the migration safety boundary.
4. `NoCommittedDataLoss`: Necessary LWW winners belonging to the migration range that have satisfied client success conditions must not be lost because of replica configuration switching.
5. `NoReadableDataLoss`: Data that was readable from serving replicas before migration and remains a logical winner at the switchover boundary must not disappear after switching because the target has not caught up.
6. `NoUnauthorizedTopologyChange`: Unauthorized migration must not modify the current replica configuration.
7. `CleanupPreservesActiveData`: Cleanup must not delete data still needed by the current serving replica configuration.
8. `NoConflictingMigrate`: At most one migration changing the serving configuration of the same TokenRange may be in progress simultaneously.

## 11. Liveness Properties Requiring Fairness Assumptions

The following properties are not purely safety invariants. They must depend on appropriate weak or strong fairness assumptions and explicit environmental prerequisites in the TLA+ specification.

### 11.1 Eventual Replica Convergence

Under the following conditions:

- The network eventually becomes reachable;
- Replicas do not fail permanently;
- There is no infinite stream of subsequent new-version writes that prevents an Item from ever stabilizing;
- Hint replay, read repair, or anti-entropy repair is scheduled continuously;

Then replicas of the same TokenRange eventually converge to the same LWW winner for each stable Item.

Fairness must be imposed on actions such as `SyncReplica`, `HintReplay`, and `AntiEntropyRepair`, or represented through equivalent eventual-delivery assumptions.

### 11.2 Eventual Hint Replay

If an ANY write succeeds solely because of a hint, and the target replica eventually becomes reachable and remains available, the hint should eventually be replayed to an appropriate replica.

This property must assume that the hint is not deliberately cleared, the target replica is reachable, and the replay action is not starved indefinitely.

### 11.3 Eventual Migration Completion

Under the following conditions:

- Migration target nodes are available;
- The source or other legitimate replicas can provide the required data;
- Streaming and catch-up actions are continuously scheduled;
- There are no infinitely rapid new writes preventing the target from ever reaching the switchover boundary;
- The migration is not actively canceled by operational actions;

Then a TokenRange in `Streaming` eventually enters `Activated` or a subsequent `Stable` state.

### 11.4 Eventual Request Response

If a request is authorized, sufficient replicas remain responsive, and the corresponding coordination actions are fairly scheduled, the read or write request eventually succeeds or terminates with an explicit unavailable result instead of remaining permanently in an intermediate state.

This property must not be required to hold without assumptions about network availability, node availability, and scheduling fairness.

## 12. Official Documentation References

| Modeling Scenario                                                             | Official Reference                                               | Corresponding Specification Semantics                                                                                                                                                                |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Partitioning, token ring, vnode, physical nodes, and replica sets             | Apache Cassandra, “Dynamo and Tunable Consistency”               | Cassandra uses consistent hashing; TokenRanges map to replica nodes; a physical node may own multiple tokens; replicas are distinct physical nodes.                                                  |
| Multi-master replicas, coordinators, and ordinary writes sent to all replicas | “Dynamo and Tunable Consistency”                                 | The coordinator determines the token range according to the partition key and replicates mutations to replicas of the data; the write consistency level controls how many responses must be awaited. |
| LWW versions and deletion timestamps                                          | “Dynamo and Tunable Consistency”                                 | Mutations carry timestamps; updates, including deletions, are resolved according to Last-Write-Wins; versions of individual CQL rows/columns can be handled independently.                           |
| ONE, QUORUM, ALL, ANY, and `W + R > RF`                                       | “Dynamo and Tunable Consistency”                                 | Read and write consistency levels, quorum thresholds, ANY being permitted only for writes, and conditional visibility based on write-read quorum intersection.                                       |
| Commit log, memtable, SSTable, and write ordering                             | Apache Cassandra, “Storage Engine”                               | Writes are recorded in the commit log before being written to the memtable; the commit log is used for recovery; memtables can be flushed to SSTables.                                               |
| Batch and periodic commit log synchronization                                 | “Storage Engine”                                                 | Batch mode acknowledges after commit log fsync; periodic mode may acknowledge before subsequent periodic synchronization.                                                                            |
| Replica divergence, hints, read repair, and anti-entropy repair               | “Dynamo and Tunable Consistency”                                 | Replicas may be temporarily inconsistent; hinted handoff and read repair are best-effort mechanisms; repair is used to drive eventual consistency.                                                   |
| Eventual consistency, LWT, and batches outside the ordinary model             | Apache Cassandra, “Guarantees and Eventual Consistency”          | Cassandra is an eventually consistent system; LWT uses Paxos and provides linearizable consistency; these are excluded from the first version.                                                       |
| Role, LOGIN, SUPERUSER, and role inheritance                                  | Apache Cassandra, “Database Roles”                               | Roles represent users or groups; roles may be granted to other roles; permissions and SUPERUSER status can be inherited, while LOGIN cannot.                                                         |
| SELECT, MODIFY, AUTHORIZE, and resource hierarchy                             | “Database Roles”                                                 | Permissions may apply to resource levels such as all keyspaces, a keyspace, or a table; SELECT is used for queries, MODIFY for write modifications, and AUTHORIZE for permission management.         |
| Default-deny authorization, permission caching, and existing sessions         | Apache Cassandra, “Security”                                     | When CassandraAuthorizer is enabled, permissions follow a whitelist model; permission data may be cached, and cached views may remain outdated until refreshed.                                      |
| Bootstrap, decommission, move, and replace                                    | Apache Cassandra, “Adding, replacing, moving and removing nodes” | New nodes bootstrap and stream range data; decommission migrates data away; replace bootstraps from other nodes; move triggers range redistribution.                                                 |
| Streaming purposes and range migration                                        | Apache Cassandra, “Improved Streaming”                           | Streaming is used for repair, host replacement, range movement, bootstrap, rebuild, and cluster expansion.                                                                                           |
| Cleanup does not automatically remove old range data                          | “Adding, replacing, moving and removing nodes”                   | After range movement, old nodes do not automatically delete data they no longer need; cleanup must be performed after confirmation.                                                                  |

Official documentation links:

- https\://cassandra.apache.org/doc/latest/cassandra/architecture/overview\.html
- https\://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html
- https\://cassandra.apache.org/doc/latest/cassandra/architecture/storage-engine.html
- https\://cassandra.apache.org/doc/latest/cassandra/architecture/guarantees.html
- https\://cassandra.apache.org/doc/latest/cassandra/managing/operating/security.html
- https\://cassandra.apache.org/doc/latest/cassandra/developing/cql/security.html
- https\://cassandra.apache.org/doc/latest/cassandra/managing/operating/topo_changes.html
- https\://cassandra.apache.org/doc/latest/cassandra/architecture/streaming.html

## 13. Recommended Module Organization for the Subsequent TLA+ Model

The subsequent generated model is recommended to use the following module order. This order represents dependencies, not the execution order of runtime actions.

### 13.1 CassandraCore

Responsibilities:

- Define Principals, Roles, Nodes, Datacenters, Keyspaces, Tables, Partitions, Tokens, TokenRanges, Items, Mutations, and Versions.
- Define static mappings: Table to Keyspace, Partition to TokenRange, Item to Partition, and Token to Node.
- Define basic type constraints for replica sets, replication factors, and topology epochs.
- Define LWW winners and Tombstone semantics.
- Define the basic representations of current serving replica sets and planned replica sets.

### 13.2 CassandraAuth

Responsibilities:

- Define permission stores, role inheritance, SUPERUSER, and authorization cache views.
- Define authorization predicates for SELECT, MODIFY, AUTHORIZE, and topology management.
- Define Grant, Revoke, permission cache refresh, and rejection operation records.
- Define authorization history records and AuthSafety.

### 13.3 CassandraWrite

Responsibilities:

- Define write request states, coordinators, target replicas, commit logs, memtables, replica acknowledgments, and hints.
- Define ReceiveWrite, ReplicaLogAndApply, ReplicaAck, StoreHint, CompleteWrite, and RejectWrite.
- Define write consistency levels and their success thresholds.
- Define the underlying states required by WriteFrontier and AckFrontier, without uniformly naming all Frontiers in this module.

### 13.4 CassandraReplication

Responsibilities:

- Define derived relationships for replica-applied states.
- Define SyncReplica, HintReplay, ReadRepair, and AntiEntropyRepair.
- Define replica version convergence and LWW local-state constraints.
- Define the underlying states required by `ReplicaFrontier(node)`.

### 13.5 CassandraMigrate

Responsibilities:

- Define TokenRange migration phases, migration sources, migration targets, planned replica sets, streamed data states, and topology epochs.
- Define StartMigrate, AdvanceMigrate, CatchUpMigrate, ActivateMigrate, CleanupMigrate, and RejectTopologyChange.
- Define the unified migration parameterization for bootstrap, decommission, move, and replace.
- Define the underlying `MigrateFrontier` data basis required by migration coverage conditions.

### 13.6 CassandraRead

Responsibilities:

- Define read requests, read coordinators, responding replica sets, read consistency levels, read results, and most-recent-read records.
- Define ReadEligible, ExecuteRead, RejectRead, and UnavailableRead.
- Define read response thresholds, collection of responding replica states, and LWW reconciliation.
- This module must not depend backward on the subsequent Frontier Interface module.
- Successful reads must return the complete set of currently eligible results for the request, rather than an arbitrary subset.

### 13.7 CassandraFrontierInterface

Responsibilities:

- Declare no new state variables.
- Define no new state actions.
- Uniformly define the following based on states already defined in preceding modules:
  - `WriteFrontier`
  - `AckFrontier`
  - `ReplicaFrontier`
  - `QueryFrontier`
  - `MigrateFrontier`
  - `FinalQueryFrontier`
- Uniformly define safety relationships among Frontiers.
- Define FrontierSafety, ReadFrontierSafety, and MigrateFrontierSafety.

### 13.8 CassandraIntegrated

Responsibilities:

- Integrate all state variables.
- Define the initial state.
- Define the global `Next` as the disjunction of actions from all modules.
- Define global type invariants.
- Combine AuthSafety, WriteSafety, ReplicaSafety, ReadSafety, QuorumIntersectionSafety, MigrateSafety, and FrontierSafety.
- Configure appropriate fairness assumptions for actions requiring liveness verification.
- Preceding modules must not depend backward on this integrated module.