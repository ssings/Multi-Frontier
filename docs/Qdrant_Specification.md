# Qdrant Frontier-Based Formal Modeling Specification

1. Specification Goal

This document defines a Frontier-based formal modeling specification for Qdrant.

The specification constrains an LLM to generate a Qdrant-adapted TLA+ model from the general Frontier method and existing instance code.

This document is not an official Qdrant implementation specification. It is a formal-modeling abstraction intended to preserve the key distributed-database semantics relevant to this study while excluding low-level implementation details that are outside the research scope.

2. Modeling Scope

The model includes:

Principal
Collection
Point
Shard
Replica
Node
Permission
WriteState
WAL
Replica acknowledgement
Replica visibility
Read consistency
Write consistency factor
Replica selection (local Search parameter, not a state variable)
Search frontier
shard migration
Safety invariants

The model excludes:

Segment internal structure
HNSW graph structure
ANN TopK correctness
Recall verification
Vector-distance computation
Payload-index correctness
Optimizer behavior
Quantization
Low-level Raft protocol details
WAL file implementation details
Snapshot file implementation details

Raft is abstracted only as the result of cluster-topology and collection-structure agreement. Leader election, terms, log replication, and other internal Raft mechanisms are not modeled.

3. Basic Objects

3.1 Principal

A Principal represents an operation subject, such as:

API key
JWT subject
User
Service identity

The model only needs to determine whether a Principal has permission to perform the requested operation.

3.2 Collection

A Collection is Qdrant's logical data container.

The model defines:

Collection

Each Point belongs to one Collection:

pointCollection : Point -> Collection

3.3 Point

A Point is the basic Qdrant data object.

A real Point may contain:

point id
vector
payload

The model abstracts away vector and payload content and only tracks whether a Point:

has been written;
has entered the WAL;
has been acknowledged by replicas;
has been applied;
satisfies read consistency;
is safe with respect to migration;
may be returned by Search.

3.4 Shard

A Shard is the data-partitioning unit of a Collection.

Each Point belongs to one Shard:

pointShard : Point -> Shard

Shard is the migration unit in this specification.

3.5 Replica

A Replica is a replica of a Shard.

Each Shard owns a set of Replicas:

replicas : Shard -> SUBSET Replica

Each Replica is located on one Node:

replicaNode : Replica -> Node

3.6 Node

A Node represents a Qdrant cluster node or peer.

The model uses Nodes to represent:

Replica location;
Shard owner;
shard migration source;
shard migration target.

4. Permission Model

4.1 Operation

The model defines:

Operation ::= Read | Write | Manage | Migrate

Semantics:

Read:
    permits search or point reads.

Write:
    permits write, upsert, or point modification.

Manage:
    management permission, abstracted as including Read, Write, and migration.

Migrate:
    permits shard migration.

4.2 Permission State

permission : Principal -> Collection -> SUBSET Operation

4.3 CanAccess

CanAccess(p, c, op) ==
    op ∈ permission[p][c]
    \/ Manage ∈ permission[p][c]

4.4 Grant / Revoke

Grant:

Grant(p, c, op):
    permission[p][c] := permission[p][c] ∪ {op}

Revoke:

Revoke(p, c, op):
    permission[p][c] := permission[p][c] \ {op}

4.5 AuthSafety

Every successful operation must be authorized.

SuccessfulWrite(p, pt) =>
    CanAccess(p, pointCollection[pt], Write)

SuccessfulSearch(p, result) =>
    ∀ pt ∈ result :
        CanAccess(p, pointCollection[pt], Read)

SuccessfulMigrate(p, s) =>
    p has Migrate or Manage permission on the collection containing shard s

The model should record:

lastWrite
lastSearch
lastMigrate

so that the authorization status of the most recent successful operation can be checked.

5. Write Model

5.1 WriteState

WriteState ::= None | WalLogged | Applied | Failed

Semantics:

None:
    the Point has not been written.

WalLogged:
    the Point has entered the WAL.

Applied:
    the Point satisfies the modeled write-consistency condition
    and has entered the committed/applied state.

Failed:
    the write failed and the Point cannot enter SearchFrontier.

5.2 WAL

The WAL is abstracted as the set of Points accepted by the write path:

wal : SUBSET Point

If:

pt ∈ wal

then Point pt has crossed the Qdrant WriteFrontier.

However:

pt ∈ wal

does not imply that the Point may already be returned by Search. The Point must additionally satisfy replica acknowledgement, Applied, read consistency, and migration safety.

5.3 Applied

applied : SUBSET Point

If:

pt ∈ applied

then the Point has satisfied the modeled commit condition.

5.4 AckSet

ackSet : Point -> SUBSET Replica

If:

r ∈ ackSet[pt]

then Replica r has acknowledged Point pt.

5.5 ReplicaHas

replicaHas : Replica -> SUBSET Point

If:

pt ∈ replicaHas[r]

then Replica r currently owns, has applied, or can serve Point pt in the abstraction.

5.6 WriteConsistencyFactor

writeConsistencyFactor : Collection -> Nat

Commit condition:

Cardinality(ackSet[pt]) >=
    writeConsistencyFactor[pointCollection[pt]]

Constraints:

1 <= writeConsistencyFactor[c]
writeConsistencyFactor[c] <= replica count of the corresponding shard

If the number of acknowledgements is insufficient, a write cannot transition from WalLogged to Applied.

6. Write Actions

6.1 ReceiveWrite

ReceiveWrite(p, pt)

Preconditions:

p ∈ Principal
pt ∈ Point
CanAccess(p, pointCollection[pt], Write)
writeState[pt] = None

Effects:

writeState[pt] := WalLogged
wal := wal ∪ {pt}
lastWrite := record this successful authorized write

Meaning: the Point is accepted by the system and enters WriteFrontier.

6.2 ReplicaAck

ReplicaAck(pt, r)

Preconditions:

pt ∈ wal
writeState[pt] = WalLogged
r ∈ replicas[pointShard[pt]]

Effects:

ackSet[pt] := ackSet[pt] ∪ {r}
replicaHas[r] := replicaHas[r] ∪ {pt}

Meaning: one replica has acknowledged or applied the Point.

6.3 CommitWrite

CommitWrite(pt)

Preconditions:

writeState[pt] = WalLogged
Cardinality(ackSet[pt]) >=
    writeConsistencyFactor[pointCollection[pt]]

Effects:

writeState[pt] := Applied
applied := applied ∪ {pt}
shardData[pointShard[pt]] :=
    shardData[pointShard[pt]] ∪ {pt}

Meaning: the Point reaches the modeled commit state and becomes eligible for subsequent visibility checks.

7. Qdrant Frontier Definitions

Qdrant uses set-valued Frontiers in this model.

7.1 WriteFrontier

WriteFrontier == wal

Meaning: the set of Points that have entered the WAL.

Safety property:

applied ⊆ WriteFrontier

7.2 CommitFrontier

CommitFrontier == applied

Meaning: the set of Points that satisfy the modeled commit condition.

Safety property:

CommitFrontier ⊆ WriteFrontier

7.3 ReplicaFrontier

From the perspective of one Replica:

ReplicaFrontier(r) == replicaHas[r]

Meaning: the Points currently visible or serviceable by Replica r.

Safety property:

ReplicaFrontier(r) ⊆ WriteFrontier

that is:

replicaHas[r] ⊆ wal

7.4 ReplicaContains

From the perspective of one Point:

ReplicaContains(pt) ==
    { r ∈ replicas[pointShard[pt]] :
        pt ∈ replicaHas[r]
    }

Meaning: the replicas that currently contain Point pt.

7.5 QueryFrontier

QueryFrontier is determined by read consistency and the local replica selection for the current Search.

QueryFrontier(level, sel) ==
    { pt ∈ Point :
        pt ∈ CommitFrontier
        /\ Visible(pt, level, sel)
    }

where:

sel ∈ ReplicaSelections

sel is not a global state variable. It is a local parameter of one Search action and selects one legal Replica for each Shard:

sel : Shard -> Replica

Meaning:

The set of committed Points that are visible under the current
read-consistency level and the current local replica selection sel.

For One, visibility is determined by the Replica selected for the Point's Shard. For Majority and All, sel is retained for a uniform interface but does not affect the replica-count test.

Safety property:

∀ level ∈ ReadConsistency,
  sel ∈ ReplicaSelections :
    QueryFrontier(level, sel) ⊆ CommitFrontier

7.6 MigrateFrontier

MigrateFrontier represents migration-safe data:

MigrateFrontier ==
    { pt ∈ Point :
        MigrationSafe(pt)
    }

Basic definition:

MigrationSafe(pt) ==
    pt ∈ shardData[pointShard[pt]]

A stronger version may require that if the Point's Shard is migrating or has activated the target, committed data must already be present in the copied target-side state.

7.7 SearchFrontier

SearchFrontier is the final searchable boundary composed from multiple Frontiers:

SearchFrontier(p, level, sel) ==
    { pt ∈ Point :
        CanAccess(p, pointCollection[pt], Read)
        /\ pt ∈ CommitFrontier
        /\ pt ∈ QueryFrontier(level, sel)
        /\ pt ∈ MigrateFrontier
    }

where:

sel ∈ ReplicaSelections

Meaning:

The Points Principal p may legally receive under the current read-consistency
level and the local replica selection of this Search.

Core safety property:

searchResult ⊆ SearchFrontier(p, level, sel)

sel exists only within the current Search action and is not added to global VARIABLES.

8. Read-Consistency Model

8.1 ReadConsistency

The first version keeps only:

ReadConsistency ::= One | Majority | All

To limit the state space, the first version does not add:

Quorum
NumericReplicaCount(k)

Abstract semantics:

One:
    one Search independently selects one Replica for each Shard;
    a Point is visible only if it exists on the Replica selected for its Shard.

Majority:
    the Point exists on at least a majority of the Replicas of its Shard.

All:
    the Point exists on every Replica of its Shard.

The model does not simulate random numbers. Possible runtime replica choices are represented by TLA+ nondeterminism so TLC can explore every legal selection.

8.2 ReplicaSelection

To support multiple Shards without adding new state variables, define the set of all legal Shard-to-Replica selection mappings:

ReplicaSelections ==
    { sel ∈ [Shard -> Replica] :
        ∀ s ∈ Shard :
            sel[s] ∈ replicas[s]
    }

With implementation constants named Shards and Replicas, the TLA+ form is:

ReplicaSelections ==
    {sel \in [Shards -> Replicas] :
        \A s \in Shards :
            sel[s] \in replicas[s]}

Each:

sel ∈ ReplicaSelections

represents one Search-time choice of one legal Replica for every Shard.

Example:

replicas[S1] = {R1, R2, R3}
replicas[S2] = {R4, R5}

One legal selection is:

sel[S1] = R2
sel[S2] = R5

A later Search may independently choose:

sel[S1] = R1
sel[S2] = R4

Therefore:

sel is not a VARIABLE;
sel is not initialized by Init;
sel is not part of SearchVars;
sel is not part of GlobalVars;
each Search may choose a new sel.

8.3 Visible

Visibility is defined as:

Visible(pt, level, sel) ==
    CASE level = One ->
        pt ∈ replicaHas[sel[pointShard[pt]]]

    [] level = Majority ->
        Cardinality(ReplicaContains(pt))
            >= Majority(replicas[pointShard[pt]])

    [] level = All ->
        ReplicaContains(pt)
            = replicas[pointShard[pt]]

One must not be defined as:

Cardinality(ReplicaContains(pt)) >= 1

because that formula means only that at least one Replica somewhere contains pt; it does not represent which Replica was selected by this request.

The corrected first-version abstraction is:

pt ∈ replicaHas[sel[pointShard[pt]]]

Example:

replicas[S1] = {R1, R2, R3}
P1 ∈ replicaHas[R1]
P1 ∉ replicaHas[R2]
P1 ∉ replicaHas[R3]

If:

sel[S1] = R1

then:

Visible(P1, One, sel) = TRUE

If:

sel[S1] = R2

then:

Visible(P1, One, sel) = FALSE

For multiple Shards, the same sel may simultaneously represent:

S1 -> R1
S2 -> R5
S3 -> R8

Thus one cross-Shard Search may independently choose one Replica per Shard without introducing any new state variable.

8.4 Majority

Majority(rs) ==
    Floor(Cardinality(rs) / 2) + 1

8.5 ReadVisibility

sel is not stored in lastSearch. ReadVisibility is expressed existentially: the complete most-recent result must be explainable by at least one legal selection used consistently for the whole result set.

ReadVisibility ==
    lastSearch.kind = "None"
    \/
    ∃ sel ∈ ReplicaSelections :
        ∀ pt ∈ lastSearch.result :
            Visible(pt, lastSearch.level, sel)

The same sel applies to the entire result set. Therefore, all Points from the same Shard use the same selected Replica; the model may not select a different Replica separately for each Point.

9. Search Model

9.1 Search

At the external-interface level, Search may still be abstracted as:

Search(p, query, level)

Internally, the TLA+ action uses one local replica-selection parameter:

Search(p, query, level, sel)

where:

sel ∈ ReplicaSelections

sel is an action parameter, not a state variable.

The model does not represent:

vector distance
TopK ordering
HNSW traversal
ANN recall
concrete payload-filter execution

Nondeterministic Search selection may be expressed as:

NextSearch ==
    \E p \in Principals,
       c \in Collections,
       level \in ReadConsistencyLevels,
       sel \in ReplicaSelections :
        Search(p, c, level, sel)
    \/ ...

TLC therefore explores different legal sel mappings, including cases where different Shards choose different Replicas.

9.2 CandidateSet

CandidateSet(p, level, sel) ==
    SearchFrontier(p, level, sel)

If the concrete implementation also passes a Collection parameter, it may use:

CandidateSet(p, c, level, sel)

while retaining:

pointCollection[pt] = c

inside the candidate-set definition.

9.3 SearchResult

searchResult : SUBSET Point

The Search action must satisfy:

searchResult' ∈ SUBSET CandidateSet(p, level, sel)

or equivalently:

searchResult' ⊆ CandidateSet(p, level, sel)

9.4 lastSearch

lastSearch keeps its existing fields and does not add a selectedReplica or sel field:

lastSearch =
    [ kind       : {"None", "Some"},
      principal  : Principal,
      level      : ReadConsistency,
      result     : SUBSET Point,
      authorized : BOOLEAN,
      executed   : BOOLEAN ]

Therefore:

no new TLA+ VARIABLE is introduced;
SearchVars is unchanged;
GlobalVars is unchanged;
InitSearch does not store the replica selection.

Replica selection is used only as the local Search-action parameter sel.

9.5 SearchSafety

Because lastSearch does not store sel, the safety property uses existential quantification:

SearchSafety ==
    lastSearch.kind = "None"
    \/
    ∃ sel ∈ ReplicaSelections :
        lastSearch.result
            ⊆ SearchFrontier(
                lastSearch.principal,
                lastSearch.level,
                sel)

This requires the complete most-recent Search result to be explainable by one legal Shard-to-Replica mapping.

For One, this prevents a result from being assembled by choosing a different Replica independently for different Points of the same Shard.

10. Shard Migrate Model

10.1 Migration Unit

The migration unit is:

Shard

Segment-level migration is not modeled.

10.2 MigrateState

To limit the state space:

MigrateState ::= Stable | Migrating | Activated

Semantics:

Stable:
    the Shard is not currently migrating.

Migrating:
    the target Node is copying data or catching up.

Activated:
    the target has satisfied the migration-safety condition
    and may become the new owner.

10.3 Migrate Variables

shardOwner    : Shard -> Node
shardLocation : Shard -> SUBSET Node
shardData     : Shard -> SUBSET Point

migrateState : Shard -> MigrateState
migrateSrc   : Shard -> Node
migrateDst   : Shard -> Node
copiedData    : Shard -> SUBSET Point
activeReplica : Shard -> SUBSET Node

10.4 PointsOfShard

PointsOfShard(s) ==
    { pt ∈ Point : pointShard[pt] = s }

10.5 StartMigrate

StartMigrate(p, s, src, dst)

Preconditions:

p ∈ Principal
CanAccess(p, CollectionOfShard(s), Migrate)
migrateState[s] = Stable
src = shardOwner[s]
dst # src

Effects:

migrateState[s] := Migrating
migrateSrc[s] := src
migrateDst[s] := dst
shardLocation[s] := shardLocation[s] ∪ {dst}
copiedData[s] := {}
lastMigrate := record phase = "Start"

10.6 AdvanceMigrate

AdvanceMigrate(p, s)

Preconditions:

p ∈ Principal
CanAccess(p, CollectionOfShard(s), Migrate)
migrateState[s] = Migrating

Two abstractions are permitted.

Incremental:

copiedData'[s] ∈ SUBSET shardData[s]
copiedData[s] ⊆ copiedData'[s]

Simplified:

copiedData'[s] = shardData[s]

The first version should prefer the simplified form to control the state space.

10.7 ActivateMigrate

ActivateMigrate(p, s)

Preconditions:

p ∈ Principal
CanAccess(p, CollectionOfShard(s), Migrate)
migrateState[s] = Migrating
applied ∩ PointsOfShard(s) ⊆ copiedData[s]

Effects:

shardOwner[s] := migrateDst[s]
activeReplica[s] := {migrateDst[s]}
migrateState[s] := Activated
lastMigrate := record phase = "Activate"

Meaning: the target contains all committed data required by the abstraction and may be safely activated.

10.8 FinishMigrate

FinishMigrate(p, s)

Preconditions:

p ∈ Principal
CanAccess(p, CollectionOfShard(s), Migrate)
migrateState[s] = Activated

Effects:

shardLocation[s] := {shardOwner[s]}
migrateState[s] := Stable
copiedData[s] := {}
lastMigrate := record phase = "Finish"

11. Migration Safety Properties

11.1 NoDoubleOwner

∀ s ∈ Shard :
    Cardinality(activeReplica[s]) <= 1

Meaning: a Shard may not have multiple active owners simultaneously.

11.2 NoCommittedDataLoss

∀ pt ∈ Point :
    pt ∈ applied => pt ∈ shardData[pointShard[pt]]

Meaning: committed Points may not be lost because of shard migration.

11.3 MigrateActivationSafe

migrateState[s] = Activated =>
    applied ∩ PointsOfShard(s) ⊆ copiedData[s] ∪ shardData[s]

More strictly, the precondition of ActivateMigrate must guarantee:

applied ∩ PointsOfShard(s) ⊆ copiedData[s]

11.4 MigratePreservesFrontier

Semantic form:

If pt belonged to SearchFrontier before migration and remains applied,
then pt remains MigrationSafe after migration completes.

The first version may approximate this with the safety property:

pt ∈ applied => pt ∈ shardData[pointShard[pt]]

12. Frontier Safety Properties

12.1 WalBeforeApply

applied ⊆ wal

12.2 ReplicaNotAheadOfWAL

∀ r ∈ Replica :
    replicaHas[r] ⊆ wal

12.3 CommitFrontierSafety

CommitFrontier ⊆ WriteFrontier

12.4 ReplicaFrontierSafety

∀ r ∈ Replica :
    ReplicaFrontier(r) ⊆ WriteFrontier

12.5 QueryFrontierSafety

∀ level ∈ ReadConsistency,
  sel ∈ ReplicaSelections :
    QueryFrontier(level, sel) ⊆ CommitFrontier

Meaning: no legal Shard-to-Replica choice may cause QueryFrontier to move beyond CommitFrontier.

12.6 MigrateFrontierSafety

∀ pt ∈ MigrateFrontier :
    MigrationSafe(pt)

12.7 SearchFrontierSafety

∀ p ∈ Principal,
  level ∈ ReadConsistency,
  sel ∈ ReplicaSelections,
  pt ∈ Point :

    pt ∈ SearchFrontier(p, level, sel)
    =>
        CanAccess(p, pointCollection[pt], Read)
        /\ pt ∈ CommitFrontier
        /\ pt ∈ QueryFrontier(level, sel)
        /\ pt ∈ MigrateFrontier

sel is a quantified local selection mapping, not a state variable.

12.8 SearchResultSafety

sel is not stored in lastSearch, so use existential quantification:

lastSearch.kind = "None"
\/
∃ sel ∈ ReplicaSelections :
    lastSearch.result
        ⊆ SearchFrontier(
            lastSearch.principal,
            lastSearch.level,
            sel)

For One, the same sel must explain the entire result set. Different Points from the same Shard may not use different Replica choices.

13. Recommended TLA+ Module Structure

Recommended modules:

QCore.tla
    Defines Principal, Collection, Point, Shard, Replica, Node,
    Operation, ReadConsistency, and MigrateState.

QAuth.tla
    Defines permission, CanAccess, Grant, Revoke, and AuthSafety.

QWrite.tla
    Defines writeState, wal, applied, ackSet,
    ReceiveWrite, ReplicaAck, and CommitWrite.

QReplica.tla
    Defines replicaHas, ReplicaContains, ReplicaSelections,
    Visible, and ReplicaFrontier.

    ReplicaSelections is an operator, not a VARIABLE.
    One uses the Replica selected by sel[pointShard[pt]].
    Majority and All continue to use ReplicaContains.

QFrontierInterface.tla
    Defines WriteFrontier, CommitFrontier, ReplicaFrontier,
    QueryFrontier(level, sel), MigrateFrontier,
    SearchFrontier(p, level, sel), and FrontierSafety.

QSearch.tla
    Defines Search, searchResult, lastSearch, and SearchSafety.

    Search uses local parameter sel.
    NextSearch nondeterministically chooses sel from ReplicaSelections.
    No global selectedReplica variable is introduced.
    SearchVars is unchanged.
    The first version does not require lastSearch to store sel.

QMigrate.tla
    Defines shardOwner, shardLocation, shardData, migrateState,
    migrateSrc, migrateDst, copiedData, activeReplica,
    StartMigrate, AdvanceMigrate, ActivateMigrate, and FinishMigrate.

QIntegrated.tla
    Composes all modules and defines Init, Next, Spec, and IntegratedSafety.

    If Next only invokes NextSearch, GlobalVars remains unchanged and no additional state variable is introduced.

If the concrete implementation already passes a Collection parameter c to SearchFrontier or SearchEligibleSet, keep that parameter and append the local sel parameter rather than deleting c.

14. LLM Generation Constraints

When generating Qdrant TLA+ code, the LLM must follow these constraints:

1. Preserve the Frontier-based method structure.
2. Use multiple Frontier layers; do not define only SearchFrontier.
3. Use set-valued Frontiers for Qdrant.
4. Do not copy numeric-variable semantics from unrelated instances.
5. Do not introduce Segment.
6. Do not introduce HNSW.
7. Do not verify ANN TopK or Recall.
8. Use Stable / Migrating / Activated as shard migration states.
9. ActivateMigrate must require the target side to contain committed data.
10. SearchResult must be a subset of SearchFrontier.
11. Every action must completely specify the next state.
12. Unmodified variables must be explicitly UNCHANGED.
13. Every module must include TypeOK.
14. Every invariant must be checkable by TLC.
15. Every variable and action must be traceable to this specification
    or to the general Frontier method.

16. One consistency must NOT be defined as:

    Cardinality(ReplicaContains(pt)) >= 1

17. Define the legal multi-Shard replica-selection set:

    ReplicaSelections ==
        {sel ∈ [Shard -> Replica] :
            ∀ s ∈ Shard : sel[s] ∈ replicas[s]}

18. ReplicaSelections must be an operator / set definition.
    selectedReplica is not a global VARIABLE.

19. Every successful Search must nondeterministically choose one local sel
    from ReplicaSelections. Within one Search, every Shard chooses one Replica,
    and different Shards may choose different Replicas.

20. One visibility must be:

    pt ∈ replicaHas[sel[pointShard[pt]]]

21. Within one Search, all Points of the same Shard must use the same sel[s].
    Do not choose a Replica independently for each Point.

22. Majority and All continue to use ReplicaContains.
    They may still accept sel as an unused parameter to preserve a uniform interface.

23. To minimize state, the first version may omit sel from lastSearch.
    In that case SearchSafety / SearchResultSafety must use:

    ∃ sel ∈ ReplicaSelections : ...

    and require the entire result set to be explained by one legal mapping.

24. If the existing code already has a Collection parameter c,
    keep it and append local sel to the existing parameter list.

15. Core Correctness Goals

The final Qdrant Frontier model should verify that every Point returned by Search satisfies:

1. The executing Principal has Read permission.
2. The Point has entered the WAL.
3. The Point has been Applied.
4. The Point satisfies the current read consistency.
5. The Point belongs to the correct shardData.
6. The Point is not lost during shard migration.
7. The Point belongs to SearchFrontier.