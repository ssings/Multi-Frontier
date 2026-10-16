# Cassandra Specification

## 1. Specification Objective

This document defines a Frontier‑based formal modeling specification for Apache Cassandra, used to constrain LLMs to generate TLA+ models checkable by SANY and TLC based on the general Frontier method, the Qdrant reference instance (for formal reference only), and fixed module interfaces.

The specification is not Cassandra source code implementation or product manual, but an abstract model oriented to the security boundary of distributed databases. The model preserves key semantics such as permission, write commit log (commit log), replica acknowledgment and application, read consistency, Token range migration, and multi-layer Frontier, and excludes storage engine internal details and network protocol implementation.

The specification follows the general Frontier method, requiring the generated model to use fixed module order and variable set, ensuring core safety properties that are checkable and verifiable.

## 2. Modeling Scope

The model includes:

- Principal (role/user)
- Keyspace (namespace)
- Record (data row)
- TokenRange / Partition (data partitioning unit)
- Replica (replica)
- Node (cluster node)
- Coordinator (coordinator node abstraction)
- Permission (permission)
- Commit Log (WAL) write state
- Replica acknowledgment (ack)
- Replica holding state
- Read consistency level
- Write consistency factor (replication factor and consistency threshold)
- Token range migration (unified abstraction of bootstrap / decommission / replace)
- Read operation result
- WriteFrontier、CommitFrontier、ReplicaFrontier、QueryFrontier、MigrateFrontier、ReadFrontier
- Safety invariant

The model does not include:

- Memtable and SSTable internal formats
- compression, Bloom Filter, index structures
- specific data models of partition keys and clustering keys
- concrete process of anti-entropy repair (only abstracted as eventual synchronization)
- hinted handoff mechanism
- lightweight transactions (LWT)
- batch logs (batchlog)
- network protocol and gossip protocol specifics
- hardware failures, timeout retries, timeout handling

Consensus protocols such as Raft / Paxos are not modeled. Cluster topology is treated as a static set, and membership changes are explicitly triggered by migration actions.

## 3. Basic Objects and Constants

### 3.1 Principal

Operation subject, corresponding to Role in Cassandra. The model only checks whether Principal has the corresponding operation permission.

Set: Principals (fixed finite set)

### 3.2 Keyspace

Logical container for data, similar to Namespace. Each Record belongs to a Keyspace, and permissions apply at the Keyspace level.

Set: Keyspaces (fixed finite set)

Mapping:
```
recordKeyspace : Record -> Keyspace
```

### 3.3 Record

Basic data unit in the database, abstractly corresponding to a row in a CQL table or a row in a partition. The model does not care about column contents; it only cares whether the record has been written, committed, visible to replicas, satisfies read consistency, is migration-safe, and can be returned by read operations.

Set: Records (fixed finite set)

Each Record belongs to a definite TokenRange / Partition.

### 3.4 TokenRange / Partition

Cassandra uses consistent hashing to partition data into different token ranges, and each token range corresponds to a Partition. Partition is the basic unit for data replication, routing, and migration. Each Record belongs to one Partition.

Mapping:
```
recordPartition : Record -> Partition
partitionKeyspace : Partition -> Keyspace
```
Constraint:
```
∀ r ∈ Records : recordKeyspace[r] = partitionKeyspace[recordPartition[r]]
```

Set: Partitions (fixed finite set)

### 3.5 Replica

Each Partition has a set of replicas (Replica), and each Replica is located on a Node.

Mapping:
```
replicas : Partition -> SUBSET Replica
replicaNode : Replica -> Node
```

Require the replica set of each Partition to be non-empty.

### 3.6 Node

Cluster physical nodes, used to specify replica locations, Token range owners, migration sources and targets, etc.

Set: Nodes (fixed finite set)

There is another abstract concept: Coordinator, which can be any node. The model does not separately track the coordinator, but instead uses action parameters to represent the node initiating the operation.

### 3.7 Configuration constants and TLC model values

The following constants are assigned via helper in fixed cfg files, and model code must not directly hard-code specific names or values:

- Principals
- Keyspaces
- Partitions
- Records
- Replicas
- Nodes
- replicaNode
- replicas
- recordPartition
- recordKeyspace
- partitionKeyspace
- replicationFactor : Keyspace -> Nat (number of replicas for each Keyspace)
- writeConsistencyFactor : Keyspace -> Nat (minimum number of acknowledgments required by write consistency, satisfying writeConsistencyFactor[ks] ≤ replicationFactor[ks])

## 4. Permission model

### 4.1 Operation

The core operations of the Cassandra permission model are abstracted as:

```
Operations == {"Read", "Write", "Manage", "Migrate"}
```

- "Read" : Allows reading data.
- "Write" : Allows writing or modifying data.
- "Migrate" : Allows performing Token range migration operations.
- "Manage" : Includes Read, Write, and Migrate, and allows granting/revoking permissions.

### 4.2 Permission state

Permissions act at the Keyspace level and are not subdivided down to Table:

```
permission : Principal -> Keyspace -> SUBSET Operations
```

Permission check:

```
CanAccess(p, ks, op) ==
    op ∈ permission[p][ks]
    ∨ "Manage" ∈ permission[p][ks]
```

### 4.3 Permission management actions

Must include:

- GrantPermission(actor, target, ks, op) : Requires actor to have "Manage" permission on ks.
- RevokePermission(actor, target, ks, op) : Same as above.

These actions modify permission state.

### 4.4 Unauthorized actions

Denial actions corresponding to write, read, and migration:

- RejectWrite(principal, record)
- RejectRead(principal, keyspace)
- RejectMigrate(principal, partition)

Unauthorized actions may only update the most recent operation record (recording authorized = FALSE), and must not modify commit log, replica state, Token range owners, or migration state.

### 4.5 Historical authorization records

The model must record the following information about the most recent successful/rejected operation:

- lastWrite.authorized
- lastRead.authorized
- lastMigrate.authorized

Subsequent permission revocation must not retroactively affect historically successful operations.

## 5. Write Model

### 5.1 Write State

Abstract two key states:

- "None": No write request has been received yet.
- "CommitLogged": The record has been written to the commit log (similar to WAL), but the write consistency condition has not yet been reached.
- "Applied": The write consistency condition has been reached, the record is considered committed, and it has been applied to the shardData of the current owner.

State variables:

```
writeState : Record -> {"None", "CommitLogged", "Applied"}
wal         : SUBSET Record    // Equivalent to the basis of WriteFrontier
applied     : SUBSET Record    // Set of committed records
```

Initial state: all Record are "None", and wal and applied are empty.

### 5.2 Replica Acknowledgment and Replica Holding State

Variables:

```
ackSet    : Record -> SUBSET Replica   // Set of replicas that have acknowledged writing this record
replicaHas : Replica -> SUBSET Record  // Set of records currently held by each replica
shardData  : Partition -> SUBSET Record // Committed data on the current owner node
lastWrite  : Records the most recent write attempt (including the authorized flag and record)
```

Initial state: all ackSet are empty, replicaHas is an empty set for each Replica, and shardData is an empty set for each Partition.

### 5.3 Write Consistency Condition

For a record r, its write consistency factor is determined by the Keyspace to which it belongs:

```
wFactor(ks) == writeConsistencyFactor[ks]
```

Commit condition:

```
Cardinality(ackSet[r]) ≥ wFactor(recordKeyspace[r])
```

### 5.4 Write Action

#### ReceiveWrite(p, r)

Precondition:

- p ∈ Principals
- r ∈ Records
- CanAccess(p, recordKeyspace[r], "Write")
- writeState[r] = "None"

Effect:

- writeState[r] := "CommitLogged"
- wal := wal ∪ {r}
- lastWrite recorded successfully, authorized = TRUE

#### RejectWrite(p, r)

Precondition: missing write permission. Effect: only records lastWrite as authorized = FALSE, other states unchanged.

#### ReplicaAck(r, replica)

Precondition:

- r ∈ wal
- writeState[r] = "CommitLogged"
- replica ∈ replicas[recordPartition[r]]

Effect:

- ackSet[r] := ackSet[r] ∪ {replica}
- replicaHas[replica] := replicaHas[replica] ∪ {r}

#### CommitWrite(r)

Precondition: Cardinality(ackSet[r]) ≥ wFactor(recordKeyspace[r]) and writeState[r] = "CommitLogged".

Effect:

- writeState[r] := "Applied"
- applied := applied ∪ {r}
- shardData[recordPartition[r]] := shardData[recordPartition[r]] ∪ {r}

#### SyncReplica(r, replica)

Used for final synchronization of records that have been committed but have not yet reached a replica.

Precondition:

- r ∈ applied
- replica ∈ replicas[recordPartition[r]]
- r ∉ replicaHas[replica]

Effect:

- replicaHas[replica] := replicaHas[replica] ∪ {r}
- Does not change the write state and commit set.

## 6. Replica and Read Consistency Model

### 6.1 Replica Containment Set

```
ReplicaContains(r) ==
    {rep ∈ replicas[recordPartition[r]] : r ∈ replicaHas[rep]}
```

### 6.2 Read Consistency Levels

Supports representative levels:

```
ReadConsistencyLevels == {"One", "Quorum", "All"}
```

Other levels can be extended later.

### 6.3 Visibility Determination

```
Visible(r, "One") ==
    Cardinality(ReplicaContains(r)) ≥ 1

Visible(r, "Quorum") ==
    2 * Cardinality(ReplicaContains(r)) > Cardinality(replicas[recordPartition[r]])

Visible(r, "All") ==
    ReplicaContains(r) = replicas[recordPartition[r]]
```

Visible only concerns the number of replicas held by replicas as required by consistency, and does not concern whether it has been committed. Final read eligibility must also check r ∈ applied and migration safety.

## 7. Token Range Migration Model

### 7.1 Migration Abstraction

Corresponds to Cassandra operations such as bootstrap, decommission, move, replace. Unified as the process of a Token range (Partition) migrating from the current owner node to a target node. The current owner of each Partition is recorded in `shardOwner`, and its data is in `shardData[partition]`.

### 7.2 Migration State

```
MigrateStates == {"Stable", "Migratering", "Activated"}
```

### 7.3 Migration Variables

```
shardOwner    : Partition -> Node               // current owner node
shardLocation : Partition -> SUBSET Node         // set of nodes currently holding this partition's data (includes at least the owner)
migrateState : Partition -> MigrateStates
migrateSrc   : Partition -> Node
migrateDst   : Partition -> Node
copiedData    : Partition -> SUBSET Record       // data already copied to the target node during migration
lastMigrate  : migration attempt record
```

Initial state: for each partition, shardOwner is some preset node, shardLocation contains all replica nodes, migrateState = "Stable", copiedData is empty.

### 7.4 Migration actions

#### StartMigrate(p, partition, src, dst)

Precondition:

- p ∈ Principals
- CanAccess(p, partitionKeyspace[partition], "Migrate")
- migrateState[partition] = "Stable"
- src = shardOwner[partition]
- dst ∈ Nodes, dst ≠ src

Effect:

- migrateState[partition] := "Migratering"
- migrateSrc[partition] := src
- migrateDst[partition] := dst
- shardLocation[partition] := shardLocation[partition] ∪ {dst}
- copiedData[partition] := {}
- lastMigrate records Start and authorized = TRUE

#### RejectMigrate

When unauthorized, only record rejection, do not change owner, location, copied data, and migration state.

#### AdvanceMigrate(partition)

Copy all committed data on the source owner to the target at once. Fixedly use one-shot copy, do not model progressive catch-up.

Precondition: migrateState[partition] = "Migratering"

Effect:

- copiedData[partition] := shardData[partition]

#### ActivateMigrate(partition)

Precondition:

- migrateState[partition] = "Migratering"
- applied ∩ {r ∈ Records : recordPartition[r] = partition} ⊆ copiedData[partition]

Effect:

- shardOwner[partition] := migrateDst[partition]
- shardData[partition] := copiedData[partition]  (install as the target node's current data)
- migrateState[partition] := "Activated"

Note: at this point, the source node's shardLocation has not been cleaned up; the subsequent FinishMigrate cleans it up.

#### FinishMigrate(partition)

Precondition: migrateState[partition] = "Activated"

Effect:

- shardLocation[partition] := {shardOwner[partition]}
- migrateState[partition] := "Stable"
- copiedData[partition] := {}

Clear temporary copied data, but shardData[partition] already contains the migrated data.

### 7.5 Migration safety determination

```
MigrationSafe(r) ==
    r ∈ shardData[recordPartition[r]]
```

Even if a partition is being migrated, the source owner continues serving before activation; query eligibility must check whether r is in the owner's shardData.

## 8. Read (query) model

### 8.1 Module positioning

The CRead module is located after CMigrate and before CFrontierInterface. It must not reference any Frontier operator, but uses underlying state to define concrete read eligibility sets.

### 8.2 Read eligibility set

```
ReadEligibleSet(p, ks, level) ==
    {r ∈ Records :
        ∧ recordKeyspace[r] = ks
        ∧ CanAccess(p, ks, "Read")
        ∧ r ∈ applied
        ∧ Visible(r, level)
        ∧ MigrationSafe(r)}
```

This set is equivalent to all records that can ultimately be safely read out.

### 8.3 Read actions

#### Read(p, ks, level)

The model does not care which columns are returned, only the set of records returned. A successful Read returns the complete ReadEligibleSet:

```
readResult' = ReadEligibleSet(p, ks, level)
```

The use of uncertain selection (such as returning only a subset) is not allowed; otherwise the model could forever return an empty set.

#### RejectRead(p, ks, level)

Without read permission:

- readResult' = {}
- lastRead.authorized = FALSE

Permissions and write, copy, and migration states must not be modified.

### 8.4 Most Recent Read Record

lastRead must contain at least:

- kind
- principal
- keyspace
- level
- result
- authorized
- executed

## 9. Frontier Interface

### 9.1 Module Responsibilities

All Frontier operators are uniformly defined in the penultimate module CFrontierInterface. This module EXTENDS CRead, declares no new variables, defines no actions, constructs Frontiers solely based on variables and derived operators defined in preceding modules, and uniformly declares FrontierSafety.

### 9.2 WriteFrontier

```
WriteFrontier == wal
```

Represents the set of records written to the commit log.

### 9.3 CommitFrontier

```
CommitFrontier == applied
```

Represents the set of records that satisfy write consistency conditions and have completed the commit.

### 9.4 ReplicaFrontier

```
ReplicaFrontier(rep) == replicaHas[rep]
```

### 9.5 QueryFrontier

```
QueryFrontier(level) ==
    {r ∈ CommitFrontier : Visible(r, level)}
```

### 9.6 MigrateFrontier

```
MigrateFrontier ==
    {r ∈ CommitFrontier : MigrationSafe(r)}
```

### 9.7 ReadFrontier

```
ReadFrontier(p, ks, level) == ReadEligibleSet(p, ks, level)
```

This definition elevates the concrete read eligibility set to the final readable boundary in the Frontier‑based method.

### 9.8 Frontier Relations

In CFrontierInterface, declare the following global properties:

- CommitFrontier ⊆ WriteFrontier
- ∀ replica : ReplicaFrontier(replica) ⊆ WriteFrontier
- ∀ level : QueryFrontier(level) ⊆ CommitFrontier
- MigrateFrontier ⊆ CommitFrontier
- ReadFrontier(p, ks, level) is equivalent to ReadEligibleSet

## 10. Safety Properties

### 10.1 AuthSafety

Any successful write, read, or migration operation has authorized = TRUE during execution; unauthorized actions can only enter the Reject branch; permission revocation does not affect historical successful operation records.

### 10.2 WalBeforeCommit

applied ⊆ wal

### 10.3 ReplicaNotAheadOfWAL

∀ replica ∈ Replicas : replicaHas[replica] ⊆ wal

### 10.4 MigrateSafety

Includes at least:

- shardOwner[partition] is always in shardLocation[partition];
- The migration source is the current owner, and the target is different from the source;
- Before activation, the target has copied all currently committed data;
- Records in applied are not lost after owner switch;
- After Finish clears copiedData, committed data remains in shardData.

### 10.5 FrontierSafety

Uniformly defined by CFrontierInterface, combining the above sub-properties and the following core requirements:

- QueryFrontier ⊆ CommitFrontier
- MigrateFrontier ⊆ CommitFrontier
- ReadFrontier(p, ks, level) must be exactly returned in any successful read operation:
  lastRead.result = ReadFrontier(lastRead.principal, lastRead.keyspace, lastRead.level)

## 11. Mandatory TLA+ Module Structure

Must generate exactly the following 8 modules, in a fixed order:

1. CCore.tla — constants, sets, mappings, CoreAssumption, TypeOK
2. CAuth.tla — permissions, CanAccess, Grant/Revoke, permission records
3. CWrite.tla — wal, applied, ack, replicaHas, shardData, write and synchronization actions
4. CReplica.tla — replica-derived operators such as ReplicaContains, Visible (do not declare write state variables)
5. CMigrate.tla — shardOwner, shardLocation, migration state, migration actions
6. CRead.tla — readResult, lastRead, ReadEligibleSet, Read/RejectRead (do not reference Frontier)
7. CFrontierInterface.tla — define all Frontiers and FrontierSafety (do not declare variables, do not define actions)
8. CIntegrated.tla — define Init, Next, Spec, GlobalVars, and the conjunction of all invariants

Dependency chain:

- CAuth EXTENDS CCore
- CWrite EXTENDS CAuth
- CReplica EXTENDS CWrite
- CMigrate EXTENDS CReplica
- CRead EXTENDS CMigrate
- CFrontierInterface EXTENDS CRead
- CIntegrated EXTENDS CFrontierInterface, CCfgHelpers

Circular dependencies are prohibited, especially CRead EXTENDS CFrontierInterface or CFrontierInterface reverse-depending on CIntegrated.

## 12. Official Documentation Basis Explanation

The following lists the Cassandra official documentation sources corresponding to each major modeling point:

- **write path** (commit log, write consistency, replica acknowledgment): from the commit log and write path descriptions in “Storage Engine”; from the “Dynamo” description that write operations are always sent to all replicas, and the consistency level controls the number of replicas whose responses are awaited.
- **replicas and eventual consistency**: from the description of eventual consistency in “Guarantees”; from the description of “Replica Synchronization” in “Dynamo”.
- **read consistency levels**: from “Tunable Consistency” and “Picking Consistency Levels” in “Dynamo”.
- **Token range migration (bootstrap / decommission / replace)**: from the “Topology Changes” and “Streaming” documents, describing token allocation, range streaming, ownership switching, and so on.
- **permission model**: from the “Authentication and Authorization” as well as the “Database Roles” and “Permissions” sections in the “Security” document, specifying roles, operation permissions, management permissions, and so on.
- **data model**: from the keyspace, table, partition, and row definitions in “Architecture Overview”.

All modeling semantics are based on the above documents, and no mechanisms not described in the documents are introduced.

## 13. Core Correctness Goals

Any Record returned by a successful read operation must satisfy the following:

1. belongs to the requested Keyspace;
2. the requesting principal has "Read" or "Manage" permission at execution time;
3. has been recorded in the commit log (wal);
4. The write consistency condition has been reached (applied);
5. The selected read consistency level is satisfied;
6. Located in the shardData of the current owner node;
7. Not lost during Token range migration;
8. Belongs to ReadEligibleSet, and therefore also belongs to ReadFrontier.

This specification defines concrete states and behaviors through preceding modules, abstracts Frontier uniformly via CFrontierInterface, and composes the system via CIntegrated, thereby realizing Cassandra's instantiation of the general Frontier‑based method.
