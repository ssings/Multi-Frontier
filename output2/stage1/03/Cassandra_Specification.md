Cassandra Specification.md

## 1. Specification Goals

This file defines a Frontier‑based formal modeling specification for Apache Cassandra.  
The goal is not to reproduce Cassandra's complete implementation, but to extract the key semantic boundaries of writes, replicas, consistency reads, data range migration, and permission checks, and to unify them into safety conditions using the Frontier method. The generated TLA+ model will be used to verify whether these safety conditions hold invariantly under any execution sequence.

The specification follows the general Frontier‑based modeling method and uses the following Cassandra official documentation as the authoritative semantic source:

- Architecture Overview
- Dynamo and Tunable Consistency
- Storage Engine and Write Path
- Guarantees and Eventual Consistency
- Authentication and Authorization
- Roles and Permissions
- Topology Changes (Adding, replacing, moving and removing nodes)
- Streaming

The final model must correspond to the entities, action semantics, Frontier layering, and safety properties specified in this specification, and must not introduce mechanisms beyond the above documentation.

## 2. Modeling Scope

The model includes:

- Node, Token Range / Shard, Partition, Coordinator Node
- Keyspace-based permission management (Principal, Role, permissions)
- Write path: commit log (WAL) write, memtable absorption, replica distribution, replica confirmation, write consistency level and commit condition
- Replica asynchronous catch-up and eventual synchronization abstraction (without detailing hinted handoff, read repair, or Merkle tree repair)
- Read consistency levels: ONE, QUORUM, ALL
- Unified abstraction of data range migration (Token Range movement): bootstrap, decommission, move/replace, including migration phases and ownership switching
- WriteFrontier, CommitFrontier, ReplicaFrontier, QueryFrontier, MigrateFrontier, FinalQueryFrontier, and their constraints

The model **does not include**:

- Gossip protocol details, concrete computation of Phi failure detection
- Hinted handoff hint storage and replay
- Concrete algorithms for Read repair and anti‑entropy repair (Merkle tree)
- SSTable internal structure, Compaction, Bloom filter, tombstones, TTL
- Counters, lightweight transactions (LWT), batch log
- Multi-datacenter special policies (only retaining the abstract RF configuration of the single-datacenter NetworkTopologyStrategy)
- Concrete processes for network partition and node crash recovery
- Performance, latency, throughput

## 3. Basic Objects and Constants

The basic sets and mappings in the model are as follows:

**Principal** – The acting subject. It can correspond to roles (Role) and users in Cassandra. The model only checks the operation permissions of a Principal on a Keyspace.

**Node** – A physical node, identified by Host ID. Each Node may have multiple Tokens (virtual nodes), but the model abstracts it as the set of Token Ranges for which the Node is responsible.

**Keyspace** – A namespace, the basic granularity of permission management. Each data row belongs to a Keyspace.

**Partition** – A basic data item (one row or multiple columns identified by the partition key + clustering key in CQL). The model does not care about the specific content of columns; it only cares about the state of the Partition during write, replication, read, and migration processes.

**Shard** – A data partitioning unit, corresponding to a Token Range. The data of a Keyspace is hash-distributed across multiple Shards according to the partition key.  
Mapping relationships:

- partitionKeyspace : Partition → Keyspace
- partitionShard    : Partition → Shard
- shardKeyspace     : Shard → Keyspace

Constraint: ∀ pt ∈ Partition : partitionKeyspace[pt] = shardKeyspace[partitionShard[pt]].

**Replica** – A replica of a Shard. The model does not explicitly materialize Replica; instead, it directly uses the association between nodes and Shards: the replicas variable denotes the current set of replica nodes for each Shard.

**Configuration constants** (fixed but parameterizable):

- Nodes, Principals, Keyspaces, Shards, Partitions
- initialReplicas : Shard → SUBSET Node (initial replica set, satisfying RF)
- replicationFactor : Keyspace → Nat
- writeConsistencyFactor : Keyspace → Nat（1 ≤ wcf ≤ RF）
- partitionShard, partitionKeyspace, shardKeyspace mappings

Consistency level set `ReadConsistencyLevels ≜ {"One", "Quorum", "All"}`.

## 4. Permission model

### 4.1 Operation types

Operations ≜ {"Read", "Write", "Manage", "Migrate"}

- "Read": allows reading data (corresponds to SELECT)
- "Write": allows writing or modifying data (corresponds to INSERT/UPDATE/DELETE)
- "Migrate": allows performing data range migration (such as bootstrap operations)
- "Manage": allows granting/revoking permissions, and implicitly includes Read, Write, and Migrate permissions

### 4.2 Permission state

```
permission : Principal → Keyspace → SUBSET Operations
```

Permission determination:

```
CanAccess(principal, keyspace, op) ≜
    op ∈ permission[principal][keyspace]
    ∨ "Manage" ∈ permission[principal][keyspace]
```

### 4.3 Authorization operations

- `GrantPermission(admin, target, keyspace, op)`
  Precondition: `admin ∈ Principals`, `target ∈ Principals`, `keyspace ∈ Keyspaces`, `op ∈ Operations`, and `CanAccess(admin, keyspace, "Manage")`.
  Effect: add `op` to `permission[target][keyspace]`.

- `RevokePermission(admin, target, keyspace, op)`
  Precondition same as Grant, effect: remove `op` from `permission[target][keyspace]`.

### 4.4 Rejection and History Records

To verify permission security, the execution result (success or rejection) of each write, query, and migration attempt and the authorization status at that time must be recorded.  
Variables:

- lastWrite : Records the most recent write attempt (including the authorized field)
- lastQuery : Records the most recent query attempt (including the authorized field)
- lastMigrate : Records the most recent migration attempt (including the authorized field)

The corresponding unauthorized actions (RejectWrite, RejectQuery, RejectMigrate) only update these records and **must not** modify the wal, applied, replicaHas, migrate state, or data distribution.

Any permission change (Revoke) occurring **after** the execution of a successful operation must not cause historical successful operations to be retroactively judged illegal.

## 5. Write Model

### 5.1 Write State

Enumeration of write states for a single Partition:

WriteStates ≜ {"None", "WalLogged", "Applied"}

- "None": has not yet been accepted by any write operation
- "WalLogged": the write has been accepted by the coordinator node and recorded in the commit log (WAL), but the consistency condition has not yet been satisfied
- "Applied": the write has reached the write consistency level and entered the commit state

### 5.2 Core Write Variables

- writeState : Partition → WriteStates
- wal : SUBSET Partition (the set of Partitions that have entered the WAL)
- applied : SUBSET Partition (the set of Partitions that have reached the commit condition)
- replicaHas : Node → SUBSET Partition (the Partitions owned locally by a node, including its memtable and data already flushed to SSTable)

### 5.3 Write Consistency Commit Condition

For Partition pt, let ks = partitionKeyspace[pt] and sh = partitionShard[pt]; the condition for pt to reach "Applied" is:

In replicaHas, the number of replica nodes that own pt is ≥ writeConsistencyFactor[ks].

### 5.4 Write Action

1. **ReceiveWrite(principal, pt)**
   - Precondition:
     - principal ∈ Principals
     - pt ∈ Partitions
     - CanAccess(principal, partitionKeyspace[pt], "Write")
     - writeState[pt] = "None"
   - Effects:
     - writeState[pt] := "WalLogged"
     - wal := wal ∪ {pt}
     - The coordinator node (the node executing this action) adds pt to its own replicaHas (indicating that it has been recorded in the local commit log and memtable)
     - Record lastWrite as success (authorized = TRUE)

2. **RejectWrite(principal, pt)**
   - Executed when permission is insufficient; only records lastWrite as failure and does not modify any write, replica, or migration state.

3. **ReplicateToNode(pt, node)**
   - Simulates asynchronous propagation among replicas: allows any node (typically a node in the replica set) to obtain Partition from WAL or other nodes and add it to local replicaHas.
   - Preconditions:
     - pt ∈ wal
     - node ∈ initialReplicas[partitionShard[pt]] (or the currently valid replica set)
     - pt ∉ replicaHas[node]
   - Effects:
     - replicaHas[node] := replicaHas[node] ∪ {pt}

   This action abstracts the eventual transfer of data among replicas, without distinguishing the specific mechanisms of hinted handoff, streaming, or read repair.

4. **CommitIfReady(pt)**
   - Checks whether the number of replica nodes currently owning pt is ≥ writeConsistencyFactor; if satisfied and writeState[pt] = "WalLogged", then:
     - writeState[pt] := "Applied"
     - applied := applied ∪ {pt}

   This action can be executed after each ReplicateToNode; the model must ensure that once the condition is satisfied, it can commit immediately.

### 5.5 Safety Properties (Local)

- **WalBeforeApply**：applied ⊆ wal
- All principals of successful writes must have Write or Manage permission when operating.

## 6. Replica and Read Consistency Model

### 6.1 Replica Visibility

Define the replica containment function:

ReplicaContains(pt) ≜ { node ∈ Nodes : pt ∈ replicaHas[node] }

### 6.2 Consistency Level Semantics

For Partition pt:

- Visible(pt, "One") ≜ |ReplicaContains(pt)| ≥ 1
- Visible(pt, "Quorum") ≜ 2 * |ReplicaContains(pt)| > |replicasOfShard(partitionShard[pt])|
- Visible(pt, "All") ≜ ReplicaContains(pt) = replicasOfShard(partitionShard[pt])

where replicasOfShard(sh) is the currently valid set of replica nodes (initially equal to initialReplicas[sh], and may change during migration).

### 6.3 Query Eligibility

A query can only return Partitions that satisfy all of the following conditions:

1. The data belongs to the queried Keyspace
2. It is already in the applied set (committed)
3. It satisfies the Visible condition under the read consistency level level

No additional migration safety condition is required, because during migration the old replicas still serve within the replica set, and after switching the target replicas already contain all committed data, so query results always fall within the safety boundary.

## 7. Data Range Migration Model

### 7.1 Migration Abstraction

Cassandra operations such as bootstrap, decommission, replace, and move essentially all involve changes in Token Range ownership. The model uniformly abstracts them as a replica set change of a Shard: replacing the source node with the target node (keeping RF unchanged), and ensuring that committed data is not lost during the replacement.

### 7.2 Migration State Variables

- replicas : Shard → SUBSET Node (dynamic replica set, modified after migration completes)
- migrateState : Shard → {"Stable", "Migratering", "Activated"}
- migrateSrc, migrateDst : Shard → Node (source and target nodes involved in migration)
- copiedData : Shard → SUBSET Partition (data already held by the target node during migration)

### 7.3 Migration Actions

1. **StartMigrate(principal, sh, src, dst)**
   - Precondition:
     - CanAccess(principal, shardKeyspace[sh], "Migrate")
     - migrateState[sh] = "Stable"
     - src ∈ replicas[sh]，dst ∉ replicas[sh]
   - Effect:
     - migrateState[sh] := "Migratering"
     - migrateSrc[sh] := src, migrateDst[sh] := dst
     - copiedData[sh] := {pt ∈ replicaHas[dst] : partitionShard[pt] = sh} (initially may be empty)
     - Record lastMigrate as successful (authorized = TRUE)

2. **RejectMigrate**: When permission is insufficient, only record failure and do not modify any state.

3. **AdvanceMigrate(sh)**
   - Copy all Partitions on the source node that are already applied and belong to this Shard to copiedData[sh] at once:
     copiedData[sh] := applied ∩ {pt : partitionShard[pt] = sh}
   - This abstraction ignores the incremental nature of actual streaming transfer, requiring only that the target node can eventually obtain the complete committed data.

4. **ActivateMigrate(sh)**
   - Precondition:
     - migrateState[sh] = "Migratering"
     - (applied ∩ {pt : partitionShard[pt] = sh}) ⊆ copiedData[sh]
   - Effect:
     - replicas[sh] := (replicas[sh] \ {migrateSrc[sh]}) ∪ {migrateDst[sh]}
     - Optional: update the target node's replicaHas to include all Partitions in copiedData[sh] (if not already included)
     - migrateState[sh] := "Activated"

5. **FinishMigrate(sh)**
   - Precondition: migrateState[sh] = "Activated"
   - Effect:
     - migrateState[sh] := "Stable"
     - copiedData[sh] := {}
     - Clear the temporary fields migrateSrc[sh], migrateDst[sh] or set them to default values

### 7.4 Migration Safety Properties

- **NoCommittedDataLoss**: After migration completes, all Partitions that were originally in applied and belong to this Shard must still appear in the replicaHas of some node in replicas.
- **NoUnsafeActivation**: ActivateMigrate can be executed only when the target node already has all committed data of this Shard.
- **NoDoubleOwner**: For the same Shard in Stable state, the size of replicas equals RF, and the source node must be removed upon activation; the same Partition will not have two mutually conflicting "primary" copies (the model does not simulate multi-primary write conflicts, and only guarantees that the replica set is valid).

## 8. Query Model

### 8.1 Query Actions

`Query(principal, keyspace, level)` is executed by any coordinator node, querying the set of Partitions in a specific Keyspace that meet the conditions.

Preconditions for successful execution:
- principal has "Read" or "Manage" permission for this Keyspace

Definition of the returned result set:

```
SearchEligibleSet(principal, keyspace, level) ≜
  { pt ∈ Partitions :
      partitionKeyspace[pt] = keyspace
      ∧ CanAccess(principal, keyspace, "Read")
      ∧ pt ∈ applied
      ∧ Visible(pt, level) }
```

The result of a successful query **must be exactly equal to** SearchEligibleSet, and must not return only a subset of it (otherwise the model may degenerate).

When a query is rejected, the result set is set to empty, and lastQuery records authorized = FALSE.

### 8.2 Interaction with migration

The dynamism of replicas during queries is already reflected in the Visible condition. During migration, when migrateState = "Migratering", the source node is still in replicas, and queries can normally read the source node or other replicas; after the transfer is complete, the target node is already in replicas and has the full committed data, so queries remain safe. Therefore, there is no need to additionally add a MigrationSafe condition to query eligibility.

## 9. Frontier hierarchical definition

According to the Frontier‑based method, the model uniformly defines the following Frontiers in the final stage (CFrontierInterface module), all of which are Partition sets.

1. **WriteFrontier ≜ wal**
   The set of Partitions that have entered the commit log (WAL). All subsequent write, replication, or commit operations can only be based on data within this boundary.

2. **CommitFrontier ≜ applied**
   The set of Partitions that have satisfied the write consistency condition. Only Partitions that have entered this boundary can be returned by queries at any consistency level.

3. **ReplicaFrontier(node) ≜ replicaHas[node]**
   The set of Partitions already owned locally by a node, representing the read boundary that this node can serve.

4. **QueryFrontier(level) ≜ { pt ∈ CommitFrontier : Visible(pt, level) }**
   The Partition boundary that is committed and visible to replicas under a given read consistency level.

5. **MigrateFrontier ≜ CommitFrontier** (no separate filter condition added)
   The boundary for migration safety: all Partitions in CommitFrontier must be protectable by the migration process. Since the migration target must catch up with CommitFrontier, CommitFrontier is used directly here. More precisely, the migration condition may require the target to replicate the full subset of Shards corresponding to CommitFrontier.

6. **FinalQueryFrontier(principal, keyspace, level) ≜**
   { pt ∈ Partitions :
       CanAccess(principal, keyspace, "Read")
       ∧ pt ∈ QueryFrontier(level)
       ∧ partitionKeyspace[pt] = keyspace }

   That is, the maximum set that queries can ultimately safely return.

**Frontier chain relationships (global invariant):**

- CommitFrontier ⊆ WriteFrontier
- ∀ node : ReplicaFrontier(node) ⊆ WriteFrontier
- ∀ level : QueryFrontier(level) ⊆ CommitFrontier
- The result set result returned by a successful query satisfies:
  result ⊆ FinalQueryFrontier(principal, keyspace, level)
  and result = SearchEligibleSet(principal, keyspace, level) (that is, it returns exactly all servable data, with no leakage and no omission).

## 10. Security properties

The model must verify the following global security invariants (Integrated module composition).

1. **TypeOK** – All variables are always within their declared type ranges.

2. **AuthSafety**
   - Any successful Write (lastWrite.authorized = TRUE) ⇒ the executing principal had Write or Manage permission at that time
   - Any successful Query (lastQuery.authorized = TRUE) ⇒ the executing principal had Read or Manage permission at that time
   - Any successful Migrate (lastMigrate.authorized = TRUE) ⇒ the executing principal had Migrate or Manage permission at the time
   - Permission changes do not affect the legality of historical successful records

3. **WalBeforeApply** – applied ⊆ wal

4. **ReplicaNotAheadOfWAL** – ∀ node : replicaHas[node] ⊆ wal

5. **QuerySafety**
   - Query result ⊆ FinalQueryFrontier(principal, keyspace, level)
   - Query result = SearchEligibleSet (i.e., no matching data is omitted)

6. **MigrateSafety**
   - After migration completes, ∀ pt ∈ applied : if pt belongs to a Shard whose migration has completed, then pt exists in replicaHas of some node in the new replicas (data is not lost)
   - ActivateMigrate can be executed only after the target node has replicated all Partitions in applied that belong to the Shard

7. **FrontierSafety** – All Frontier containment relations above always hold.

## 11. Liveness Properties and Fairness

The model may additionally define the following liveness properties, and weak fairness (WF) must be enabled during verification:

- **PartitionToAllReplicas**: For any pt ∈ applied, provided there is no persistent state corruption and migration blocking, eventually every current replica node (in replicas) will have the Partition (pt ∈ replicaHas[node]).  
  The ReplicateToNode action must be allowed to eventually occur when its precondition is satisfied (WF on ReplicateToNode).

- **MigrateProgress**: Once migration starts (migrateState = "Migratering"), if AdvanceMigrate and ActivateMigrate are continuously permitted, then migration will eventually complete (reach "Stable").  
  Weak fairness is required for executable migration steps.

The main model specification Spec can be defined as Init ∧ □[Next]_vars ∧ WF_... to support these liveness checks, but safety property verification does not require fairness conditions.

## 12. Main Scenarios and Official Documentation Basis

| Scenario | Model Abstraction | Official Documentation Basis |
|------|----------|--------------|
| Write path: coordination, commit log, memtable, replica sending | ReceiveWrite → wal & replicaHas; ReplicateToNode propagation; CommitIfReady commits based on the number of replica acknowledgments | Storage Engine – commit log, memtable; Dynamo – “Write operations are always sent to all replicas” |
| Write consistency level | writeConsistencyFactor compared with the number of replicas | Tunable Consistency – ONE, QUORUM, ALL; Dynamo chapter |
| Read consistency level | Visible condition based on the number of replicas that contain it; Query returns SearchEligibleSet | Tunable Consistency – Read consistency levels; read path |
| Asynchronous replica catch-up | ReplicateToNode allows replicas to learn data from wal | Guarantees – eventual consistency; Replica synchronization (hinted handoff, repair) |
| Token range migration (bootstrap / decommission) | Migrate three phases (Stable, Migratering, Activated) replicate applied data and then switch the replicas set | Topology Changes – Bootstrap, Decommission, Replace; Streaming – data streaming between nodes |
| Permission management | Keyspace-based Operations permissions, Grant/Revoke | Security – Authorization; Roles and Permissions – GRANT/REVOKE |

## 13. Recommended Module Partitioning

Following the Frontier method and the Cassanadra specification, it is recommended that the LLM generate the following 8 TLA+ modules in a fixed order:

1. **CCore.tla**  
   Define basic constants (Nodes, Principals, Keyspaces, Shards, Partitions, replication factors, etc.) and the TypeOK condition, as well as mapping relations.

2. **CAuth.tla**  
   Permission state `permission`, `CanAccess`, `GrantPermission`, `RevokePermission`, `lastWrite` / `lastQuery` / `lastMigrate` permission records, `Reject*` actions.

3. **CWrite.tla**  
   Write state variables `writeState`, `wal`, `applied`, `replicaHas`; define `ReceiveWrite`, `ReplicateToNode`, `CommitIfReady`, write-side `lastWrite` records; local safety property `WalBeforeApply`.

4. **CReplica.tla**  
   Replica visibility definitions `ReplicaContains` and `Visible`; `ReadConsistencyLevels` constant.

5. **CQuery.tla**  
   Query results `searchResult`, `lastQuery`; define `SearchEligibleSet`, `Query` and `RejectQuery` actions.

6. **CMigrate.tla**  
   Migration variables `replicas`, `migrateState`, `migrateSrc`, `migrateDst`, `copiedData`; define `StartMigrate`, `AdvanceMigrate`, `ActivateMigrate`, `FinishMigrate` and reject versions; migration safety property.

7. **CFrontierInterface.tla**  
   **No new variables are declared, and no actions are defined**, only define all Frontiers (WriteFrontier, CommitFrontier, ReplicaFrontier, QueryFrontier, FinalQueryFrontier) and FrontierSafety based on preceding modules. Must ensure the equivalence `SearchFrontier(…) = SearchEligibleSet(…)`.

8. **CIntegrated.tla**  
   Combine all variables, define Init, Next (disjunction of all actions), Spec (including optional fairness constraints), global invariant TypeInvariant and conjunction of safety properties.

Inter-module dependency order is strictly CCore → CAuth → CWrite → CReplica → CQuery → CMigrate → CFrontierInterface → CIntegrated. Circular references are not allowed, especially CQuery must not reference operators in FrontierInterface.

Model configuration (TLC cfg) must fixedly specify SPECIFICATION Spec, and check at least TypeInvariant, AuthSafety, WalBeforeApply, ReplicaNotAheadOfWAL, QuerySafety, MigrateSafety, FrontierSafety. Function constants (such as partitionShard, replicas initial values) are injected through pre-provided helper constant mappings.
