# A General Frontier-Based Formal Modeling Method for Distributed Databases

## 1. Method Objective

This document defines a Frontier-based formal modeling method for distributed databases.

The objective of the method is not to reproduce the source-code implementation of a particular database. Instead, it abstracts the safety boundaries among write, replication, query, consistency, authorization, and data-migration processes in distributed databases, and uses a formal model to verify that these boundaries are always preserved.

In this method, a Frontier represents the safety boundary that the system has reached for a particular class of operation. Subsequent operations may depend only on data that has crossed the corresponding Frontier; they must not read, synchronize, migrate, or return data beyond that boundary.

------

## 2. Scope of Applicability

This method applies to distributed databases or distributed storage systems with the following characteristics:

```text
1. Data is divided into multiple partitions or shards;
2. Data may have multiple replicas;
3. Visibility delays may exist between writes and reads;
4. Queries may require different consistency levels;
5. Data may be migrated between nodes;
6. The system provides access control or authorization checks;
7. The goal is to verify safety properties rather than performance properties.
```

The method does not focus on:

```text
1. Internal implementation of query algorithms;
2. Correctness of index structures;
3. Correctness of ranking or similarity computation;
4. Low-level optimizations such as storage pages, caching, and compression;
5. Network protocol details;
6. Full implementation details of real-world failure recovery procedures.
```

------

## 3. General System Objects

A Frontier-based model is recommended to use the following general objects.

### 3.1 Principal

A `Principal` represents an entity that performs an operation.

In a real system, it may correspond to:

```text
user
service account
access token
client identity
API caller
```

The model only considers whether a `Principal` has permission to perform a given type of operation.

------

### 3.2 Namespace

A `Namespace` represents a logical data container.

In a real system, it may correspond to:

```text
table
collection
namespace
database
index space
tenant space
```

Permissions are typically applied at the `Namespace` level.

------

### 3.3 Record

A `Record` represents a basic data item in the database.

The model does not consider the internal contents of a `Record`; it only considers whether the record:

```text
has been written;
has been received by replicas;
has satisfied the commit condition;
has satisfied query-consistency requirements;
remains safe during migration;
can be returned by a query.
```

------

### 3.4 Partition

A `Partition` represents a data-partitioning unit in the system.

In a real system, it may correspond to:

```text
partition
shard
data range
replica group
routing unit
migration unit
```

`Partition` is the central object that connects writes, replication, query routing, and data migration.

------

### 3.5 Replica

A `Replica` represents a replica of a particular `Partition`.

The model may use `Replica` to express whether:

```text
a replica has received a write;
a replica has applied a write;
a replica can serve queries;
a replica participates in migration or recovery.
```

------

### 3.6 Server

A `Server` represents a node in the cluster.

A `Server` may act as:

```text
the node hosting a replica;
a query-serving node;
a write-forwarding node;
a migration source node;
a migration target node.
```

------

### 3.7 Operation

An `Operation` represents an operation type.

General operations include:

```text
Read
Write
Manage
Migrate
```

A specific system may extend the set of operation types, but it should preserve the modeling semantics that every successful operation must be authorized.

------

## 4. General Module Structure

A Frontier-based formal model is recommended to be divided into the following modules.

```text
Core module:
    Defines the basic sets Principal, Namespace, Record, Partition, Replica, Server,
    together with mappings from Record to Namespace and from Record to Partition.

Authorization module:
    Defines authorization state, authorization checks, permission grants,
    permission revocations, and authorization safety properties.

Write module:
    Defines write state, write actions, and WriteFrontier.

Replication module:
    Defines replica acknowledgements, replica application, replica synchronization state,
    and ReplicaFrontier.

Query module:
    Defines consistency levels, query visibility, QueryFrontier,
    and query safety properties.

Migration module:
    Defines data-migration state, migration source, migration target,
    migration progress, and MigrationFrontier.

Frontier Interface module:
    Provides unified definitions of the Frontier types and declares ordering
    or containment relationships among them.

Integrated module:
    Composes all submodules and defines Init, Next, Spec,
    and global safety properties.
```

This layered structure is part of the method. Different database instances may replace the semantics of variables and actions, but should preserve this module organization as far as possible.

------

## 5. Basic Definition of a Frontier

A `Frontier` is an abstract safety boundary.

Depending on the system, a Frontier may be represented as:

```text
1. A numeric boundary:
   for example, a version number, timestamp, log position, or sequence number.

2. A set-valued boundary:
   for example, the set of data items that have been written,
   replicated, or made visible.

3. A predicate-based boundary:
   for example, whether a data item satisfies authorization, commit,
   visibility, and migration-safety conditions.
```

The same method allows different databases to choose different Frontier representations.

------

## 6. Core Frontier Types

### 6.1 WriteFrontier

`WriteFrontier` represents the boundary of data already accepted by the write path.

It answers the following question:

```text
Which data items have already been accepted by the system's write path?
```

`WriteFrontier` may be instantiated as:

```text
write version
log position
write sequence number
set of written data
pre-commit persistence boundary
```

General safety requirement:

```text
No replica, query, or migration operation may depend on data
that has not yet entered WriteFrontier.
```

Typical safety property:

```text
ReplicaFrontier <= WriteFrontier
```

or, in set form:

```text
ReplicaFrontier ⊆ WriteFrontier
```

------

### 6.2 ReplicaFrontier

`ReplicaFrontier` represents the boundary to which a replica or serving node has caught up.

It answers the following question:

```text
Up to which write boundary can a given replica or node safely serve at present?
```

`ReplicaFrontier` may be instantiated as:

```text
replica synchronization version
set applied by a replica
set acknowledged by a replica
node-local readable boundary
```

General safety requirement:

```text
ReplicaFrontier must not advance beyond WriteFrontier.
```

Typical safety property:

```text
∀ server, partition :
    ReplicaFrontier(server, partition) <= WriteFrontier(partition)
```

Set form:

```text
ReplicaVisible(server, partition) ⊆ WriteAccepted(partition)
```

------

### 6.3 QueryFrontier

`QueryFrontier` represents the boundary that a query may observe under a particular consistency policy.

It answers the following question:

```text
What data may a query safely observe at most?
```

`QueryFrontier` is usually determined by the following factors:

```text
1. Whether a write has reached a queryable state;
2. Whether the replica has caught up sufficiently;
3. The consistency level selected by the query;
4. Whether the serving node has sufficiently recent local state.
```

General safety requirement:

```text
A query must not advance beyond QueryFrontier.
```

Typical safety property:

```text
QueryFrontier <= ReplicaFrontier
```

or, in set form:

```text
QueryFrontier(level) ⊆ ReplicaFrontier
```

------

### 6.4 MigrationFrontier

`MigrationFrontier` represents the safety boundary that must be satisfied for data migration, redistribution, or routing switchover.

It answers the following question:

```text
Has the target node or target location reached a state at which service can be switched safely?
```

`MigrationFrontier` constrains:

```text
migration start;
migration progress;
target catch-up;
service switchover;
release of the old location.
```

General safety requirement:

```text
Before migration completes, the target side must reach MigrationFrontier.
```

Typical safety property:

```text
MigrationFrontier(partition) <= WriteFrontier(partition)
TargetFrontier(partition) >= MigrationFrontier(partition)
```

Set form:

```text
CommittedData(partition) ⊆ TargetCopiedData(partition)
```

------

### 6.5 FinalQueryFrontier

`FinalQueryFrontier` represents the final boundary of data that may be returned by a query.

It combines the following constraints:

```text
authorization boundary;
write boundary;
replica boundary;
query-consistency boundary;
migration-safety boundary.
```

It can be abstracted as:

```text
FinalQueryFrontier(principal, level)
    = AuthorizedBoundary(principal)
      ∩ QueryFrontier(level)
      ∩ MigrationSafeBoundary
```

If the model uses numeric Frontiers, version comparisons may be used.

If the model uses set-valued Frontiers, set intersection may be used.

Core safety property:

```text
QueryResult ⊆ FinalQueryFrontier(principal, level)
```

------

## 7. General Frontier Chains

The basic chain is:

```text
WriteFrontier
    ↓
ReplicaFrontier
    ↓
QueryFrontier
    ↓
FinalQueryFrontier
    ↓
QueryResult
```

The migration-safety chain is:

```text
WriteFrontier
    ↓
MigrationFrontier
    ↓
TargetFrontier
```

`FinalQueryFrontier` must be constrained by both `QueryFrontier` and `MigrationFrontier`:

```text
QueryFrontier
        ↓
FinalQueryFrontier

MigrationFrontier
        ↓
FinalQueryFrontier
```

Therefore, data returned by a successful query must simultaneously be:

```text
authorized;
written;
synchronized or acknowledged by replicas;
consistent with the current consistency level;
in a migration-safe state.
```

------

## 8. Authorization Modeling Method

The authorization module constrains whether a `Principal` may perform an `Operation`.

General authorization state:

```text
permission : Principal -> Namespace -> SUBSET Operation
```

General authorization predicate:

```text
CanAccess(principal, namespace, operation)
```

Administrative permission may be modeled as a higher-level permission:

```text
CanAccess(p, ns, op) ==
    op ∈ permission[p][ns]
    \/ Manage ∈ permission[p][ns]
```

Authorization safety property:

```text
If an operation succeeds, the executing principal must have the corresponding permission.
```

It is recommended to record the most recent successful operations:

```text
lastWrite
lastQuery
lastMigration
```

and then verify:

```text
LastWriteAuthorized
LastQueryAuthorized
LastMigrationAuthorized
```

------

## 9. Write Modeling Method

The write module is responsible for advancing `WriteFrontier`.

A typical write process is:

```text
ReceiveWrite
    ↓
AdvanceWriteFrontier
    ↓
CommitOrApply
```

Meaning:

```text
ReceiveWrite:
    The system accepts a write request and checks write permission.

AdvanceWriteFrontier:
    The write enters the boundary on which subsequent modules may depend.

CommitOrApply:
    The write reaches a state in which it may be considered by query-consistency logic.
```

General safety property:

```text
Committed or applied data must first enter WriteFrontier.
```

Numeric form:

```text
CommittedVersion(partition) <= WriteFrontier(partition)
```

Set form:

```text
CommittedSet ⊆ WriteFrontier
```

------

## 10. Replica / Synchronization Modeling Method

The replica module is responsible for advancing `ReplicaFrontier`.

A typical synchronization process is:

```text
StartSync
    ↓
AdvanceReplicaFrontier
    ↓
FinishSync
```

or:

```text
ReplicaAck
    ↓
ReplicaApply
    ↓
ReplicaVisible
```

General safety property:

```text
ReplicaFrontier must not advance beyond WriteFrontier.
```

Numeric form:

```text
ReplicaFrontier(server, partition) <= WriteFrontier(partition)
```

Set form:

```text
ReplicaFrontier(replica) ⊆ WriteFrontier
```

------

## 11. Query Modeling Method

The query module computes `QueryFrontier` according to the consistency policy and constrains query results.

A typical process is:

```text
SelectConsistencyLevel
    ↓
ComputeRequiredFrontier
    ↓
CheckAvailableFrontier
    ↓
ExecuteQuery
    ↓
ReturnResult
```

where:

```text
RequiredFrontier:
    The minimum boundary required by the selected consistency level.

AvailableFrontier:
    The boundary actually available at the current serving node or replica.

ExecuteQuery:
    Execution is permitted only when RequiredFrontier <= AvailableFrontier.
```

General safety property:

```text
QueryResult ⊆ FinalQueryFrontier(principal, level)
```

The model does not verify ranking, recall, or performance of the query algorithm itself; it only verifies that returned results do not cross the safety boundary.

------

## 12. Consistency-Policy Modeling Method

A consistency policy defines the visibility requirement that a query must satisfy.

General consistency policies may be abstracted as:

```text
Strict:
    The query must observe the latest write boundary.

Bounded:
    The query may lag by a bounded amount.

Session:
    The query must observe at least the writes previously performed by the same principal.

Eventual:
    The query only needs to remain within the currently available boundary.
```

A specific database may replace these policy names, but should preserve the following semantics:

```text
1. Different consistency levels correspond to different RequiredFrontiers;
2. RequiredFrontier <= AvailableFrontier must be checked before query execution;
3. Observed query data must not exceed AvailableFrontier;
4. Query results must satisfy the selected consistency level.
```

------

## 13. Migration Modeling Method

The migration module is responsible for advancing `MigrationFrontier` and ensuring that data migration or routing switchover does not destroy committed data.

A three-stage migration abstraction with a relatively small state space is recommended:

```text
Stable
Migrating
Activated
```

Meaning:

```text
Stable:
    No migration is currently in progress, and the system serves data from the existing location.

Migrating:
    The target side is catching up with data from the source side.

Activated:
    The target side has satisfied the safety condition and may perform,
    or has already performed, the service switchover.
```

General migration actions:

```text
StartMigration
AdvanceMigration
ActivateMigration
FinishMigration
```

Core safety condition:

```text
Before ActivateMigration, the target side must contain all data required by the migration-safety condition.
```

Recommended safety properties:

```text
NoCommittedDataLoss:
    Committed data must not be lost because of migration.

NoUnsafeActivation:
    The target side must not be activated before it has caught up.

NoDoubleOwner:
    A migration unit must not have an invalid state with multiple active owners.

MigrationPreservesFrontier:
    Migration must not violate the data boundary that has already become queryable.
```

------

## 14. Frontier Interface Module

The `Frontier Interface` module provides a unified view of Frontiers defined across different submodules.

It should define:

```text
WriteFrontier(partition)
ReplicaFrontier(server, partition) or ReplicaFrontier(replica)
QueryFrontier(server, namespace) or QueryFrontier(level)
MigrationFrontier(partition)
TargetFrontier(partition)
FinalQueryFrontier(principal, level)
```

It should also declare global relationships among the Frontiers:

```text
ReplicaFrontier <= WriteFrontier
QueryFrontier <= ReplicaFrontier
MigrationFrontier <= WriteFrontier
TargetFrontier >= MigrationFrontier
QueryResult ⊆ FinalQueryFrontier
```

This module should not contain excessive database-specific logic. Database-specific semantics should be placed in the write, replica, query, or migration module of the concrete instance.

------

## 15. Integrated Module

The `Integrated` module composes all submodules.

It typically contains:

```text
Vars:
    All state variables.

Init:
    Initial conditions for all state variables.

Next:
    Disjunction of all submodule actions.

Spec:
    Init /\ [][Next]_Vars

IntegratedSafety:
    Conjunction of all global safety properties.
```

The `Integrated` module must guarantee that:

```text
1. Every action completely specifies the next state;
2. Unmodified variables are explicitly listed under UNCHANGED;
3. All local safety properties can be composed into global safety properties;
4. The model checker can check TypeOK and IntegratedSafety.
```

------

## 16. Minimum Set of Safety Properties

A Frontier-based model should include at least the following properties.

### 16.1 TypeOK

All variables always remain within their declared types.

### 16.2 AuthSafety

Every successful operation must have the corresponding permission.

### 16.3 WriteSafety

Committed or applied data must first enter `WriteFrontier`.

### 16.4 ReplicaSafety

`ReplicaFrontier` must not advance beyond `WriteFrontier`.

### 16.5 QuerySafety

A query must not advance beyond `QueryFrontier` or `FinalQueryFrontier`.

### 16.6 MigrationSafety

Migration must not cause committed data loss, and switchover must not complete before the target has caught up.

### 16.7 FrontierSafety

All dependency relationships among Frontiers must hold at all times.

------

## 17. Constraints for LLM-Based Generation

When this method is used to guide a large language model in generating a formal model for a target database, the following rules should be followed:

```text
1. First read this general method and understand the Frontier structure;
2. Then read the existing instance code to learn module organization and action style;
3. Finally read the target-database specification to determine concrete variable and action semantics;
4. Do not copy database-specific variable names from an existing instance;
5. Do not introduce mechanisms absent from the target specification;
6. Preserve the methodological structure of WriteFrontier, ReplicaFrontier,
   QueryFrontier, MigrationFrontier, and FinalQueryFrontier;
7. A numeric or set-valued Frontier representation may be selected according to the target database;
8. Every action must completely specify the next state;
9. Unmodified variables must be explicitly listed under UNCHANGED;
10. Every module must include TypeOK;
11. Every safety invariant must be traceable to either the general method or the target specification;
12. The generated model must be checkable by the model checker.
```

------

## 18. Core Contribution of the Method

The core contribution of the Frontier-based method is:

```text
Representing write safety, replica safety, query consistency, and migration safety
in distributed databases within a unified framework of constraints among Frontiers.
```

It abstracts complex system behavior into:

```text
write boundary
    ↓
replica boundary
    ↓
query boundary
    ↓
migration-safety boundary
    ↓
final query result
```

This abstraction allows different distributed databases to be formally modeled and verified within the same methodological framework.

------

## 19. Final Correctness Statement

A model conforming to this method should guarantee at least the following:

```text
Any data item returned by a successful query must be:
    accessed by an authorized principal,
    already within the write-safety boundary,
    already satisfying replica or synchronization safety conditions,
    consistent with the query-consistency requirement,
    and not lost during migration or routing switchover.
```

This is the core verification objective of the Frontier-based method.
