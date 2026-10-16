# Cassandra Frontier-based Formal Modeling Specification

## 1. Specification Objectives

This document defines a Frontier-based formal modeling specification for Apache Cassandra, used to drive LLMs to generate TLA+ models that can be checked by a model checker based on the general Frontier method and existing reference instances.

This specification is not an implementation specification of Cassandra source code, but a formal model that preserves the following key semantics in an abstract manner:
- Role-based authorization
- Write path (CommitLog, Memtable, replica acknowledgment)
- Multi-replica write consistency levels
- Multi-replica read consistency levels and eventual consistency
- Dynamic Token Range migration (bootstrap, decommission, move/replace)
- Read/write and migration safety boundaries of multi-layer Frontiers

The model excludes low-level implementation details unrelated to the research objectives.

Modeling adopts the following mandatory module order:
```
CCore
CAuth
CWrite
CReplica
CMigrate
CQuery
CFrontierInterface
CIntegrated
```
This order represents static dependencies, not the execution order of actions. CFrontierInterface must be second-to-last, and CIntegrated must be last.

## 2. Modeling Scope

The model includes:
- Principal (role/Role)
- Keyspace
- Table
- DataItem (basic data unit written/read, abstracted as a row or a mutation identifier)
- Token (hash value), Token Range
- Node/Endpoint
- Replica
- Coordinator (coordinator node)
- WriteState、WriteAck
- Replica data set
- Read consistency level、Write consistency level
- Token Range migration state and ownership
- WriteFrontier、ReplicaFrontier、QueryFrontier、MigrateFrontier、FinalQueryFrontier
- Safety properties

The model does not include:
- Complete CQL syntax and query compilation
- Column-level concrete type system
- Table physical columns and schema change details
- SSTable file format, Compaction, Bloom Filter, underlying index implementation
- Gossip protocol, Failure Detector precise state propagation
- CommitLog disk write details, memtable memory allocation
- Specific algorithms of Hinted Handoff and Read Repair, Anti-entropy Repair
- Multi-datacenter replication topology (abstracted only as the set of nodes where replicas reside)
- Lightweight Transactions（Paxos）
- Batch writes (batchlog) and materialized views
- Correctness of range queries and Secondary Index
- Technical details such as compression, encryption, and ZeroCopy for streaming transfer

## 3. Basic Objects and Fixed Constants

### 3.1 Principal

According to the Role definition in the document, Principal represents a database role (a loginable user or group). The model only cares whether Principal has the permission for the corresponding operation. All operation subjects belong to the set `Principals`.

### 3.2 Keyspace and Table

- Keyspace: logical data container, defines replication strategy (such as SimpleStrategy or NetworkTopologyStrategy) and replication factor (RF). Each Keyspace contains several Tables.
- Table: structured container of data, composed of one or more columns, partitioned by the partition key (Partition Key).

The model treats Keyspace as the context unit for permission and replication, and uses Table to distinguish data items.

### 3.3 DataItem

DataItem represents a single data record targeted by one write operation in the database (which can be mapped to a row in CQL, or an identifier of one mutation). The model does not care about its column values and content; it only cares whether the DataItem is:
- Has been written and recorded in CommitLog/Memtable;
- Has received enough replica confirmations to satisfy the write consistency level;
- Is held by a specific replica;
- Can be used to satisfy the read consistency level;
- Is in a safe state during migration;
- Can be returned by a query.

Each DataItem belongs to a Table and is mapped to a Token Range through the Token of its Partition Key:
```
dataItemTable        : DataItem -> Table
tableKeyspace        : Table -> Keyspace
dataItemToken        : DataItem -> Token
tokenRangeForToken   : Token -> TokenRange  (determined by the ring structure and sorted tokens)
```

### 3.4 Token, Token Range, and Partition

- Token: a 64-bit integer or similar hash value, which is a position on the Consistent Hashing ring.
- Token Range: a continuous interval on the ring (left-open, right-closed); all DataItems whose Token falls in this interval belong to this Token Range. A Token Range is the unit of data partitioning and replica allocation.

In the model, a Token Range is equivalent to a Shard in Qdrant and serves as the basic unit for replication and migration. A set `TokenRanges` and its related mappings can be defined.

### 3.5 Node and Endpoint

- Node: a physical or virtual node in the cluster, identified by a unique Host ID. A node owns several Token values (vnodes), but the model can view each node as responsible for a set of contiguous Token Ranges.
- Endpoint: a network address (IP + port); the model can ignore the concrete address and use Node directly to represent replica locations.

### 3.6 Replica and Replica Set

For each Token Range, the replication policy determines an ordered list of replica nodes, called a Replica Set, whose size is the Replication Factor (RF). This list provides read and write services during normal service. The model represents it as `replicaSet : TokenRange -> Tuple of Node` (order does not matter and it can be simplified to a set). A replica on each node for a specific TokenRange is called a Replica instance and can be modeled as `replicas : TokenRange -> SUBSET Replica`, with `replicaNode : Replica -> Node` defined.

### 3.7 Coordinator

A Coordinator is not a persistent role but a node temporarily responsible for request coordination. Write, read, and migration actions in the model implicitly choose a coordinator, but we need not explicitly model coordinator state and can express it only through action parameters. We only need to ensure that data is correctly routed to the target replica.

### 3.8 Configuration Constants and model values

The model will use constant assignments supported by TLC; all instance objects are provided through configuration or helper functions, without hard-coding concrete names. For example:
- Collection constants such as `Principals`, `Nodes`, `TokenRanges`, `Keyspaces`, `Tables`, `DataItems`, and `Replicas`
- `replicationFactor : Keyspace -> Nat` or `Keyspace -> replicationFactor`
- `writeConsistencyLevel` and `readConsistencyLevel` as possible operation parameters
- `replicaSet : TokenRange -> SUBSET Node` or the `replicas` mapping
- Function constants such as `dataItemToken`, `dataItemTable`, and `tableKeyspace`

## 4. Authorization Model

### 4.1 Operation

Based on the permission list in the documentation, we abstract the operation types relevant to modeling:
```
Operations == {"Read", "Write", "Manage", "Migrate"}
```
- "Read": corresponds to SELECT permission and allows reading data.
- "Write": corresponds to MODIFY permission and allows insert/update/delete.
- "Migrate": corresponds to executing topology change operations (bootstrap, decommission, etc.), assuming the corresponding permission is required.
- "Manage": corresponds to AUTHORIZE/CREATE/ALTER/DROP permissions, implicitly includes Read, Write, and Migrate, and allows Grant/Revoke.

### 4.2 Permission State

```
permission : Principal -> Keyspace -> SUBSET Operations
```

Permission determination:
```
CanAccess(principal, keyspace, op) ==
    op \in permission[principal][keyspace]
    \/ "Manage" \in permission[principal][keyspace]
```

### 4.3 Grant / Revoke

The actions `GrantPermission` and `RevokePermission` must be included, and modifications are allowed only when the initiating Principal has "Manage" permission on the target Keyspace. In addition, Cassandra's Superuser role can implicitly have all permissions; in the model, the Superuser role can be preset to have "Manage" permission on all Keyspaces.

### 4.4 Unauthorized Actions

Denial actions corresponding to write, read, and migration:
- `RejectWrite`
- `RejectQuery`
- `RejectMigrate`
These actions only record failure and authorization status, and must not modify write status, replica data, migration status, or permissions.

### 4.5 Historical authorization records

The model must preserve the authorization result at the time of the most recent successful operation execution:
```
lastWrite.authorized
lastQuery.authorized
lastMigrate.authorized
```
Subsequent permission changes (Revoke) should not affect recorded historical successful operations.

## 5. Write model

### 5.1 Write path abstraction

According to the official documentation, the write process is:
1. The Coordinator receives the write request and sends the mutation to all target replicas (based on the replication strategy).
2. Each replica writes the mutation to the local CommitLog and Memtable, and replies to the coordinator with an ack.
3. The Coordinator waits until the number of acks satisfying the specified write consistency level is reached, then returns success to the client.

The model abstracts the data lifecycle on a replica as:
- State `None`: the replica has not yet received the DataItem.
- State `Received`: the replica has received and persisted it (CommitLog+Memtable), but the write has not yet been considered committed by the coordinator.
- State `Committed`: the given write consistency level has been reached, the system considers the DataItem committed, and it can participate in subsequent read decisions.

But to reduce state explosion, we can abstract the satisfaction of the write consistency level as a global condition: when the number of replicas that have acknowledged a DataItem reaches `writeConsistencyNumber` (computed from the configured write level and RF), that DataItem enters the global `committed` set. The replica-local state only records `replicaHas[replica]` (whether the replica already has the data), and elements in `replicaHas` are necessarily mutations already sent by the Coordinator.

Thus, define the following variables:
- `writeRequested : SUBSET DataItem`: DataItems accepted by the coordinator and sent to all target replicas.
- `ackCount : DataItem -> Nat`: the number of replicas for which an ack has been received.
- `committed : SUBSET DataItem`: DataItems satisfying write consistency.
- `replicaHas : Replica -> SUBSET DataItem`: the set of data already received by each replica.
- `lastWrite`: records the subject, keyspace, dataItem, authorized, etc. of the most recent write attempt.

### 5.2 Write Consistency Level

The model supports the following representative write consistency levels (taken from the documentation):
- `ONE`: at least one replica acknowledges.
- `QUORUM`: a majority of replicas (RF/2 + 1) acknowledge.
- `ALL`: all replicas acknowledge.
- `ANY`: may only write a hint; this model ignores `ANY` because hints are not modeled.

For a given Keyspace's RF and write level, the required number of acknowledgments `requiredWrites` can be computed. The model can obtain it via the function `WriteThreshold(keyspace, level)`.

### 5.3 Write Action

- `ReceiveWrite(principal, dataItem)`
  Precondition: the principal has Write or Manage permission for the keyspace to which dataItem belongs, and dataItem has not yet been requested.
  Effect: add dataItem to `writeRequested`, send to all replicas in `replicaSet[dataItem's TokenRange]` (i.e., they can add the item to `replicaHas`), and record `lastWrite`.

- `RejectWrite(principal, dataItem)`
  When permissions are insufficient, record the rejection and do not change any data state.

- `ReplicaAck(replica, dataItem)`
  Precondition: dataItem is already in `writeRequested`, and replica belongs to the replicaSet of its token range, and replica does not yet have the data.
  Effect: add dataItem to `replicaHas[replica]`, and increment `ackCount[dataItem]` by one. If `ackCount` reaches `WriteThreshold`, add dataItem to `committed`.

Note: the model does not separately model the coordinator send action; it marks dataItem as requested directly through `ReceiveWrite` and allows any relevant replica to perform `ReplicaAck`. This is equivalent to the coordinator having already sent write requests to all replicas, but details such as network latency are omitted.

## 6. Replica and Read Consistency Model

### 6.1 Replica Visibility

- `replicaHas[replica]` represents the data currently held by that replica that has been written (but may not have been committed).
- Define the operator `ReplicaContains(dataItem)`: returns the set of replicas containing that dataItem.

### 6.2 Read Consistency Level

Supports three representative levels (taken from the documentation):
- `ONE`: at least one replica has dataItem.
- `QUORUM`: a majority of replicas have dataItem.
- `ALL`: all replicas have dataItem.

For reads, define the visibility condition:
```
Visible(dataItem, level) ==
    Cardinality({r \in replicaSet[tokenRange] : dataItem \in replicaHas[r]}) >= RequiredReads(level, RF)
```
where `RequiredReads` is computed according to the level and RF.

### 6.3 Read Eligibility

The necessary condition for a dataItem to be successfully read is:
- dataItem has already been committed (i.e., it has reached the write consistency level and entered the committed set).
- `Visible(dataItem, level)` is satisfied.

This ensures that reads only return data that has been acknowledged and is visible to replicas, conforming to the strong consistency intersection semantics when `W + R > RF`.

## 7. Token Range Migration Model

### 7.1 Migration Abstraction

According to the official documentation, topology changes (bootstrap, decommission, move, replace) are essentially changes in the ownership of a Token Range (i.e., the set of responsible replicas), accompanied by streaming of data from the old replica set to the new replica set. The model abstracts this uniformly as a migration process for a Token Range, including three phases:

```
Stable, Migratering, Activated
```

- Stable: no migration, the token range is served by the current `ownerReplicas` set.
- Migratering: the target node(s) (one or more) are synchronizing data from source nodes.
- Activated: the target nodes already have all committed data, the ownership switch is complete, and the source nodes may clear old data for which they are no longer responsible (but the model does not model cleanup, and only ensures that data is visible at the new owner).

### 7.2 Migration Variables

- `currentReplicas : TokenRange -> SUBSET Node` (i.e., the replica set currently providing service, consistent with RF)
- `migrateState : TokenRange -> {"Stable", "Migratering", "Activated"}`
- `migrateSrc : TokenRange -> SUBSET Node` (source node set, usually equal to the currentReplicas before migration)
- `migrateDst : TokenRange -> SUBSET Node` (target node set, becomes the new currentReplicas after migration completes)
- `copiedData : TokenRange -> SUBSET DataItem` (data copied to the target nodes during migration)
- `lastMigrate`: records the most recent migration attempt

### 7.3 Migration Actions

- `StartMigrate(principal, tokenRange, srcSet, dstSet)`
  Precondition: the principal has Migrate or Manage permission on the keyspace to which tokenRange belongs; migrateState is Stable; srcSet equals currentReplicas; dstSet differs from srcSet.
  Effect: migrateState := "Migratering"; migrateSrc := srcSet; migrateDst := dstSet; copiedData := {}; record lastMigrate.

- `RejectMigrate`: only records when permission is insufficient.

- `AdvanceMigrate(tokenRange)`
  Precondition: migrateState = "Migratering".
  Effect: copy all currently committed data belonging to this tokenRange into copiedData in one step: `copiedData[tokenRange] := {d \in committed : tokenRangeOf(d) = tokenRange}`. This is equivalent to streaming completion.

- `ActivateMigrate(tokenRange)`
  Precondition: migrateState = "Migratering"; all currently committed data for this tokenRange are in copiedData (i.e., `committed \cap tokenRangeData \subseteq copiedData`).
  Effect: currentReplicas := migrateDst; migrateState := "Activated".

- `FinishMigrate(tokenRange)`
  Precondition: migrateState = "Activated".
  Effect: migrateState := "Stable"; copiedData := {}; also ensure that the replicaHas set on the new currentReplicas contains all committed data (which can be ensured by AdvanceMigrate having already copied it, or by additional synchronization actions).

### 7.4 Migration Safety Condition

Define a migration safety predicate for a DataItem:
```
MigrationSafe(dataItem) ==
    dataItem \in replicaHas of some scheme that at least includes the current owner?
```
Since after migration activation, the owner has changed to migrateDst, the data must have at least one replica available on the new currentReplicas. The model may define: a dataItem is migration-safe if and only if it is held by at least one replica belonging to `currentReplicas`. More precisely, in the Stable state it naturally satisfies this; during migration, reads and writes are still served by the original currentReplicas until activation. Therefore, on read, it is sufficient that the dataItem is held by a valid replica when queried. The model will consider migration safety through `QueryFrontier`.

## 8. Query Model (CQuery)

### 8.1 Query Eligibility Set

In the model, read operations are abstracted as querying all DataItems in a specific Keyspace or Table that satisfy a certain read consistency level. But for simplification, the query scope can be defined as the entire Keyspace, returning only eligible data.

Define `SearchEligibleSet(principal, keyspace, readLevel)` as:
```
{d \in DataItems :
    dataItemTable[d] belongs to keyspace,
    CanAccess(principal, keyspace, "Read"),
    d \in committed,
    Visible(d, readLevel),
    MigrationSafe(d)}
```

### 8.2 Query Action

- `Query(principal, keyspace, readLevel)`
  Precondition: permission check.
  Effect: set `queryResult` to `SearchEligibleSet(...)`. Record `lastQuery`.

- `RejectQuery`: return an empty set when permissions are insufficient, and record the rejection.

## 9. Frontier Interface

The CFrontierInterface module is responsible for defining all Frontiers.

### 9.1 WriteFrontier

```
WriteFrontier == writeRequested
```
Represents the set of DataItems that have been accepted by the system write path and distributed to replicas.

### 9.2 CommitFrontier

```
CommitFrontier == committed
```
Represents the set of DataItems that have satisfied the write consistency level and cannot be revoked.

### 9.3 ReplicaFrontier

```
ReplicaFrontier(r) == replicaHas[r]
```
Represents the data set currently held by a specific replica.

### 9.4 QueryFrontier

```
QueryFrontier(level) ==
    {d \in CommitFrontier : Visible(d, level)}
```
Represents the set of DataItems that are committed and visible to a sufficient number of replicas under a given read consistency level.

### 9.5 MigrateFrontier

```
MigrateFrontier ==
    {d \in CommitFrontier : MigrationSafe(d)}
```
Represents the data set that is committed and safe for migration.

### 9.6 FinalQueryFrontier

```
FinalQueryFrontier(principal, keyspace, level) ==
    {d \in QueryFrontier(level) :
        d belongs to keyspace
        /\ CanAccess(principal, keyspace, "Read")
        /\ d \in MigrateFrontier}
```
Equivalent to the query eligibility set. This Frontier ensures that returned results are authorized, committed, replica-visible, and migration-safe.

### 9.7 SearchFrontier

```
SearchFrontier(principal, keyspace, level) ==
    FinalQueryFrontier(principal, keyspace, level)
```

### 9.8 Frontier Relationships

```
CommitFrontier \subseteq WriteFrontier
\A r \in Replicas : ReplicaFrontier(r) \subseteq WriteFrontier
\A level : QueryFrontier(level) \subseteq CommitFrontier
MigrateFrontier \subseteq CommitFrontier
FinalQueryFrontier \subseteq QueryFrontier \cap MigrateFrontier
```

## 10. Safety Properties

### 10.1 TypeOK

All variables always remain within their type constraints.

### 10.2 AuthSafety

Any successful write, query, or migration must have the required permissions at the time it occurs. Unauthorized actions can only enter the Reject branch and cannot modify data or migration state. Revoke does not affect the recorded authorization history.

### 10.3 WriteSafety

- `committed \subseteq writeRequested`
- If a dataItem is successfully written, it must first be writeRequested and eventually reach committed.

### 10.4 ReplicaSafety

- `replicaHas[r] \subseteq writeRequested` (replicas cannot hold unrequested data)
- For a dataItem belonging to tokenRange, only replicas in the corresponding replicaSet can hold it.

### 10.5 QuerySafety

- The result of any successful query must equal `SearchEligibleSet`. That is, `result = FinalQueryFrontier(...)`. This ensures that queries do not exceed the query scope and do not omit data that should be returned.

### 10.6 MigrateSafety

- At any time, for each tokenRange, the set of nodes in `currentReplicas` is consistent with RF.
- Before migration activation, all committed data must already exist in the target replica set (`copiedData` contains all committed data belonging to that range).
- After migration activation, `currentReplicas` switches, and all committed data has at least one replica in the new currentReplicas (installed via copiedData).
- Multiple active owners must not occur during migration.
- After migration completes and cleanup occurs, old data on removed nodes does not cause read anomalies (the model may optionally ignore cleanup).

### 10.7 FrontierSafety

All inclusion relationships among Frontiers must hold, as described in 9.8.

## 11. Official Documentation Basis for Major Scenarios

| Scenario | File / Section |
|------|------------|
| Consistent hashing, Token Ring, Token Range, replica determination | Architecture Overview / Dynamo: Consistent Hashing |
| Multi-master replication, write path, replica ack | Dynamo: Multi-master Replication, Tunable Consistency |
| Writing to CommitLog and Memtable | Storage Engine: Logging writes to commit logs, Memtables |
| Write consistency levels ONE/QUORUM/ALL | Dynamo: Tunable Consistency |
| Read consistency levels ONE/QUORUM/ALL and read-write intersection | Dynamo: Tunable Consistency |
| Eventual consistency, read repair, Hinted Handoff | Dynamo: Replica Synchronization; Guarantees |
| Role-based authentication and authorization | Security: Roles, Authentication, Authorization |
| Permission model GRANT/REVOKE | Security: Permissions |
| Bootstrap、Decommission、Move、Replace、Streaming | Topology Changes; Improved Streaming |
| SSTable streaming and data migration | Improved Streaming |

## 12. Mandatory Module Structure and Dependencies

The following 8 modules are generated by the LLM strictly in order, with no additions, removals, or circular dependencies:

1. **CCore.tla**  
   Constant definitions, basic sets (Principals, Nodes, TokenRanges, Keyspaces, Tables, DataItems, Replicas), mappings (tokenRangeOf, replicaSet, dataItemTable, etc.), CoreAssumption, CoreTypeOK.

2. **CAuth.tla**  
   Permission state `permission`, `CanAccess`, Grant/Revoke actions, authorization flags in `lastWrite`/`lastQuery`/`lastMigrate` records.

3. **CWrite.tla**  
   Write state: `writeRequested`, `ackCount`, `committed`, `replicaHas`, `WriteThreshold` derived operations;  
   `ReceiveWrite`, `RejectWrite`, `ReplicaAck` actions;  
   Record `lastWrite`.

4. **CReplica.tla**  
   Defines operators such as `Visible`, `ReplicaContains`; does not declare new state variables, but may reference variables from the write module.

5. **CMigrate.tla**  
   Migration state: `currentReplicas`, `migrateState`, `migrateSrc`, `migrateDst`, `copiedData`;  
   Actions `StartMigrate`, `RejectMigrate`, `AdvanceMigrate`, `ActivateMigrate`, `FinishMigrate`;  
   Record `lastMigrate`; define `MigrationSafe`.

6. **CQuery.tla**  
   `Query`, `RejectQuery` actions; define `SearchEligibleSet`; record `lastQuery`; do not reference any Frontier operator.

7. **CFrontierInterface.tla**  
   Based on the states and operators of preceding modules, define all Frontiers: `WriteFrontier`, `CommitFrontier`, `ReplicaFrontier`, `QueryFrontier`, `MigrateFrontier`, `FinalQueryFrontier`;  
   Define `FrontierSafety` as the conjunction of the inclusion relations. Do not declare variables; do not define actions.

8. **CIntegrated.tla**  
   Combine all modules, declare global variable `Vars`; define `Init` as the conjunction of the initial states of each module; `Next` as the disjunction of all actions; `Spec`; global `TypeOK` and `IntegratedSafety` (includes all safety properties).

Prohibit any reverse dependencies, especially prohibit CQuery from referencing Frontier operators.  

The generation of all modules must satisfy:
- Each action fully specifies the next-state.
- Unmodified variables must be explicitly `UNCHANGED`.
- Invariants must not be defined as `TRUE`.
- Next must not be defined as `FALSE`.
- Query results must not always return the empty set.
- Do not delete or weaken the safety properties required by the specification.
- All behaviors must be traceable to this specification or the general Frontier method.

## 13. Core Correctness Goals

In the Casandra model established by this specification, any DataItem returned by a successful query must satisfy:
1. Belongs to the queried Keyspace;
2. The querying principal has Read or Manage permissions at execution time;
3. Has been accepted by the system write path (entered writeRequested);
4. Has satisfied the write consistency level (entered committed);
5. Satisfies the current read consistency level (replica visibility);
6. Remains safe after Token Range migration (`MigrationSafe`);
7. Therefore belongs to `SearchEligibleSet`, i.e., `FinalQueryFrontier`.

The model ensures through the Frontier interface that “read results do not exceed boundaries, migration does not lose committed data, and permissions are always checked”.
