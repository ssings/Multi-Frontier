# Common Error-Prone Rules for TLA+ Code Generation

This file is used for the pre-generation prompt, post-generation Python static pre-checks, and iterative repair constraints for group T3. It supplements rules on TLA+ syntax, module ordering, cfg/helper files, next-state completeness, and degenerate coding patterns, without otherwise changing the Qdrant-specific semantics.

## 1. Characters and Basic Syntax

### 1.1 Use ASCII TLA+ Operators

Use the following consistently:

```text
/\  \/  \in  \notin  \subseteq  \cup  \cap
\A  \E  =>  <=>  #  ~  []  <>  '
```

Do not mix Unicode symbols such as `∈`, `∀`, `∃`, `∧`, `∨`, `⊆`, `≤`, or `≥` into the code, and do not replace the ASCII next-state prime `'` with a curly quotation mark.

### 1.2 Definitions and Assignments

```text
TLA+ operator definition:          ==
ordinary constant assignment cfg: =
cfg definition override:          <-
next-state variable:               x'
function or record update:         EXCEPT
```

Do not use pseudocode-style assignments such as `x := value` inside actions.

### 1.3 Comments

Use the following form for single-line comments:

```text
\* comment
```

Do not use `//`.

### 1.4 Domains of Bounded Quantifiers

Multiple variables may be comma-separated in the same quantifier only when they share the same domain:

```text
\A x, y \in S : P
\E x, y \in S : P
```

When different variables range over different sets, do not write:

```text
\E x \in S, y \in T : P
\A x \in S, y \in T : P
```

They must be rewritten as nested quantifiers:

```text
\E x \in S :
    \E y \in T :
        P

\A x \in S :
    \A y \in T :
        P
```

Continue nesting when more variables have different domains:

```text
\E admin \in Principals :
    \E target \in Principals :
        \E c \in Collections :
            \E op \in Operations :
                Action(admin, target, c, op)
```

This is a TLA+ syntax error and should be detected by SANY. A typical error message is:

```text
Parse Error
Encountered "," ...
```

The Python static checker does not duplicate this syntax check so that the evaluation boundary remains clear:

```text
L1: passes structural and interface static checks;
L2: all modules pass SANY.
```

T3 reads this rule during initial generation to prevent the error. If SANY still reports this kind of problem, the iterative repair prompt should include this rule fragment together with the error location.

## 2. EXTENDS and Unknown Operator Errors

Import `Naturals` or `Integers` when using `Nat` or arithmetic operators; import `FiniteSets` when using `Cardinality`.

When an `Unknown operator` error occurs, check the following in order:

1. spelling and capitalization;
2. whether the module containing the definition is visible through the fixed dependency chain;
3. whether a later module has been referenced incorrectly;
4. whether the referenced cfg helper name actually exists;
5. `LET/IN` scope;
6. whether a Unicode prime character was introduced accidentally.

Do not bypass the error by deleting all references to a required operator.

## 3. cfg and QCfgHelpers

### 3.1 Set-Valued Constants

The fixed cfg may directly use:

```text
Principals = {P1, P2}
Nodes = {N1, N2, N3}
Shards = {S1}
Collections = {C1}
Points = {PT1, PT2}
Replicas = {R1, R2, R3}
```

These are TLC model values. They do not need to be declared individually in `QCore.tla`, and they must not be hard-coded into the business logic.

### 3.2 Function-Valued Constants

Use the following fixed overrides:

```text
writeConsistencyFactor <- WriteConsistencyFactorCfg
replicas               <- ReplicasCfg
replicaNode            <- ReplicaNodeCfg
pointShard             <- PointShardCfg
pointCollection        <- PointCollectionCfg
shardCollection        <- ShardCollectionCfg
```

The static checker must confirm that every name on the right-hand side of `<-` can be resolved from the root module.

### 3.3 Protection of Fixed Files

`QCfgHelpers.tla` is read-only. Python should compare its hash before and after generation and repair. If it changes:

1. restore the fixed version;
2. mark the current iteration as an interface violation;
3. record the violation in the corresponding `errXX_static.txt` or `errXX_api.txt` file.

### 3.4 Do Not Put Complex Expressions in cfg

Complex functions, nested `:>/@@` expressions, `LET/IN`, and set comprehensions must not be written into the cfg by the model. They are provided by the fixed helper module.

## 4. Functions, Sets, and Records

### 4.1 Function Construction

```text
[p \in Principals |-> [c \in Collections |-> {}]]
```

Do not use Python dictionaries or JSON syntax.

### 4.2 Function Updates

```text
[f EXCEPT ![x] = @ \cup {v}]
[f EXCEPT ![x][y] = @ \cup {v}]
```

Do not omit `@`, and do not write `f[x]'`.

### 4.3 Record Updates

```text
[r EXCEPT !.authorized = TRUE]
```

When replacing a complete record, all fields required by `TypeOK` must be provided.

### 4.4 DOMAIN Safety

Before accessing `pointShard[pt]`, ensure that `pt \in Points`; apply the same rule to accesses of other functions.

### 4.5 Element Types

```text
shardLocation[s] \subseteq Nodes
ackSet[pt] \subseteq Replicas
replicaHas[r] \subseteq Points
copiedData[s] \subseteq Points
```

Do not mix values of other object types into these sets.

## 5. LET/IN and Scope

Standard form:

```text
LET Local(x) == expression
    Other == expression
IN body
```

Avoid deeply nested `LET/IN` expressions inside set constructions and actions. Reusable logic should be defined as a top-level operator.

The cfg `<-` syntax must not be copied into `.tla` files.

## 6. Variables, Init, and TypeOK

### 6.1 Declare Each Variable Only Once

Each variable may be declared by only one business module. Later modules must use it through `EXTENDS` rather than redeclaring it.

### 6.2 Complete Initialization in Init

Every variable must be assigned along the `Init` call path. Initial record values must include all fields.

Typical initial values include:

```text
wal = {}
applied = {}
writeState = [pt \in Points |-> "None"]
ackSet = [pt \in Points |-> {}]
replicaHas = [r \in Replicas |-> {}]
```

### 6.3 Unique TypeOK Names

```text
CoreTypeOK
AuthTypeOK
WriteTypeOK
ReplicaTypeOK
MigrationTypeOK
SearchTypeOK
```

Do not define a generic `TypeOK` in multiple modules.

`QFrontierInterface` should in principle contain no state variables; do not declare artificial Frontier variables merely to satisfy a template.

## 7. Action Next-State Completeness

For every relevant variable, an action must either:

```text
specify x' = ...
```

or include it in:

```text
UNCHANGED
```

When TLC reports `Successor state is not completely specified`:

1. read the list of unassigned variables;
2. if the action should update a variable, add the corresponding next-state assignment;
3. otherwise add the variable to `UNCHANGED`;
4. do not delete variables, actions, or invariants.

Actions in earlier modules do not know about variables declared by later modules. Therefore, `QIntegrated` must use wrappers to complete the global next-state relation:

```text
/\ ImportedAction
/\ UNCHANGED OtherModuleVars
```

Do not place a local action directly into the global `Next` relation without such completion.

## 8. Next, Spec, and Global Variables

The following must exist:

```text
Init
Next
GlobalVars
Spec
```

Use the fixed specification form:

```text
Spec == Init /\ [][Next]_GlobalVars
```

`GlobalVars` must include every declared `VARIABLE`, without omissions, duplicates, or references to nonexistent variables.

The following are forbidden:

```text
Next == FALSE
Next == TRUE
Next == UNCHANGED GlobalVars
```

Do not remove key business actions and leave only authorization actions or actions with no business semantics.

## 9. Common Invariant Errors

### 9.1 Invariants Required by cfg Must Exist

```text
GlobalTypeInvariant
AuthSafety
WalBeforeApply
ReplicaNotAheadOfWAL
FrontierSafety
MigrationSafety
```

They must all be resolvable from `QIntegrated`.

### 9.2 Tautological Invariants Are Forbidden

Do not use:

```text
AuthSafety == TRUE
FrontierSafety == TRUE
MigrationSafety == TRUE
wal \subseteq wal
```

### 9.3 Failure in the Initial State

Check the following first:

1. cfg/helper values;
2. `DOMAIN` of functions initialized in `Init`;
3. record fields;
4. whether the owner belongs to the location set;
5. initial permissions;
6. containment relationships among `wal`, `applied`, `replicaHas`, and `shardData`.

Do not simply delete the invariant.

## 10. Common Frontier Errors

### 10.1 All Frontier Operators Must Be Defined Only in QFrontierInterface

The static checker should verify the definition locations of:

```text
WriteFrontier
CommitFrontier
ReplicaFrontier
QueryFrontier
MigrationFrontier
SearchFrontier
FrontierSafety
```

They must be defined in `QFrontierInterface.tla`, not scattered across `QWrite`, `QReplica`, `QMigration`, or `QSearch`.

### 10.2 Multi-Layer Relationships

At minimum, confirm that:

1. `WriteFrontier` uses `wal`;
2. `CommitFrontier` uses `applied`;
3. `ReplicaFrontier` uses `replicaHas`;
4. `QueryFrontier` uses `CommitFrontier` and `Visible`;
5. `MigrationFrontier` uses `CommitFrontier` and `MigrationSafe`;
6. `SearchFrontier` is equivalent to `SearchEligibleSet`;
7. `FrontierSafety` references the Frontier operators above.

### 10.3 Frontiers Must Not Be Fixed to the Empty Set

The following are forbidden:

```text
SearchFrontier(...) == {}
QueryFrontier(...) == {}
MigrationFrontier == {}
SearchEligibleSet(...) == {}
```

The result of an individual unauthorized query may be empty, but a successful `Search` must not be unconditionally empty.

### 10.4 Set-Valued Frontiers

This model uses set-valued Frontiers. Do not copy numeric-version semantics such as:

```text
frontier + 1
pt.version <= frontier
```

## 11. Authorization Errors

Historical successful operations must be validated using the saved `authorized` value recorded at execution time, rather than by re-checking the current permission state.

`RejectWrite`, `RejectSearch`, and `RejectMigration` must not modify:

```text
wal
applied
ackSet
replicaHas
shardData
shardOwner
shardLocation
migrationState
copiedData
```

`CanAccess` must treat `"Manage"` as including the requested permission.

## 12. Write and Synchronization Errors

1. `ReceiveWrite` must not unconditionally add a point to `applied` at the same time.
2. `CommitWrite` must check the number of acknowledgements.
3. `ReplicaAck` may act only on a valid replica.
4. After a point becomes `Applied`, `SyncReplica` or an equivalent action must allow `replicaHas` to continue expanding.
5. Any action that adds a point to `replicaHas` must guarantee `pt \in wal`.
6. `CommitWrite` must maintain `shardData`.

## 13. Migration Errors

The model must guarantee:

```text
src = shardOwner[s]
dst # src
src \in Nodes
dst \in Nodes
copiedData'[s] = shardData[s]
applied \cap PointsOfShard(s) \subseteq copiedData[s]
```

During activation, `copiedData[s]` must be installed into `shardData[s]`. Otherwise, after `FinishMigration` clears the temporary copied data, it becomes impossible to prove that the new owner retains all committed data.

Do not add an `activeReplica` variable that duplicates `shardOwner` and may become inconsistent with it.

## 14. Error Stage Classification

```text
static   Python static pre-check failure
sany     SANY parsing or semantic-checking failure
tlc      TLC invariant violation, deadlock, or runtime error
timeout  one-minute smoke-test limit reached without an earlier error
api      API request, response-format, or patch-application failure
```

Each iteration records only the earliest failing stage: do not run SANY after a static failure, and do not run TLC after a SANY failure.

## 15. Incremental Repair Rules

### 15.1 Full Regeneration Is Forbidden

After the initial generation, every repair must use the current on-disk version as the baseline:

1. modify only the necessary files and code blocks that cause the current error;
2. leave unrelated files unchanged;
3. do not change the ordering or public interfaces of the eight modules;
4. do not modify the cfg or `QCfgHelpers.tla`;
5. do not regenerate the entire model.

### 15.2 Send Only Necessary Context

Prefer sending:

1. the complete error message;
2. the current contents of the module containing the error;
3. relevant signatures from directly dependent modules;
4. the interface-constraint paragraphs related to the error.

Do not repeatedly send all Milvus files, the entire specification, or unrelated Qdrant modules in every iteration.

### 15.3 Return Format

Preferred formats:

```text
A. unified diff;
B. if a diff cannot be returned reliably, return the complete contents of only the files actually modified.
```

If a patch cannot be applied reliably, record the iteration as an `api/patch` error; do not overwrite a file with partial content.

### 15.4 Re-Verification

After each modification, execute the following in order:

1. static pre-checks;
2. SANY checking for all eight generated modules plus the fixed helper;
3. a one-minute TLC smoke test of `QIntegrated` under the fixed cfg.

### 15.5 Batches of 20 Attempts

If 20 attempts are exhausted and the user chooses to continue:

1. continue from the current code;
2. do not restore the initial version;
3. continue error numbering with `err21`, `err22`, and so on;
4. record the batch number and cumulative repair count.

## 16. Python Static Pre-Check Checklist

### [File Layer]

- Are all eight generated files present?
- Does the fixed `QCfgHelpers.tla` exist, and is its hash unchanged?
- Is any file empty?
- Does each `MODULE` name match its filename?
- Does any file contain a Markdown fence?
- Does each module end with `====`?
- Are any extra business modules present?

### [Dependency Layer]

- Does each business module's `EXTENDS` clause follow the fixed dependency chain?
- Does `QSearch` depend only on `QMigration`?
- Does `QFrontierInterface` depend on `QSearch`?
- Does `QIntegrated` depend on both `QFrontierInterface` and `QCfgHelpers`?
- Is there any cyclic dependency or forward reference?

### [Search/Frontier Layering]

- Does `QSearch` define `SearchEligibleSet`?
- Does `QSearch` incorrectly reference any Frontier name?
- Does a successful `Search` return the complete `SearchEligibleSet`?
- Does `QFrontierInterface` declare any `VARIABLE` or action?
- Are all Frontier operators defined only in `QFrontierInterface`?
- Is `SearchFrontier` equivalent to `SearchEligibleSet`?

### [cfg/helper]

- Does the `SPECIFICATION` operator referenced by cfg exist?
- Do all invariants listed in cfg exist?
- Do all helper names referenced by `<-` exist?
- Has the cfg or helper file been modified?
- Are instance-specific names such as `P1`, `N1`, or `S1` hard-coded in the model code?

### [Variables and Actions]

- Is any variable declared more than once?
- Are all variables assigned along the `Init` path?
- Are all variables included in `Vars/GlobalVars`?
- Do the `QIntegrated` wrappers complete `UNCHANGED` variables?
- Does `Next` cover all four categories of actions: Auth, Write, Migration, and Search?

### [Degeneracy Checks]

- Is any invariant defined as `TRUE`?
- Is `Next` defined as `FALSE`, `TRUE`, or pure `UNCHANGED`?
- Is `SearchEligibleSet` or `SearchFrontier` fixed to the empty set?
- Is a successful `Search` allowed to return an arbitrary subset?
- Does `FrontierSafety` actually reference multiple Frontier layers?

Static checks cannot prove complete TLA+ syntax correctness or business-logic correctness. SANY, TLC, and manual review are still required.

## 17. Repair Prompt Templates

### 17.1 Static or SANY Errors

```text
Repair the following error using the current on-disk version as the baseline.
Modify only the necessary files and code blocks that cause the error; do not regenerate the entire model.
Strictly preserve the module order: QCore, QAuth, QWrite, QReplica, QMigration,
QSearch, QFrontierInterface, QIntegrated.
QSearch must not reference any Frontier operator; all Frontier operators must be defined only in QFrontierInterface.
Do not modify the fixed cfg or QCfgHelpers.tla, and do not delete or rename any invariant.
Prefer returning a unified diff; if a reliable diff cannot be produced, return the complete contents of only the files actually modified.

Error stage: {stage}
Error message:
{error}
```

### 17.2 TLC or Invariant Errors

```text
Repair the following TLC error using the current on-disk version as the baseline.
First identify the root cause, then modify only the necessary code.
Do not delete or weaken any invariant; do not change Next to FALSE;
do not force a successful Search to return the empty set or an arbitrary subset of the candidate set;
do not swap QSearch and QFrontierInterface;
do not modify the cfg or QCfgHelpers.tla; do not rewrite the entire model.
Prefer returning a unified diff; if a reliable diff cannot be produced, return the complete contents of only the files actually modified.

Error message:
{error}
```
