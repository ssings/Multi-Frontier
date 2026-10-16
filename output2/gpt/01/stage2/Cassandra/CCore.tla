------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals, FiniteSets

CONSTANTS
    Principals,
    Nodes,
    Keyspaces,
    Tables,
    Partitions,
    DataItems,
    Mutations,
    TokenRanges,
    Epochs,
    tableKeyspace,
    partitionTable,
    partitionRange,
    rangeKeyspace,
    itemPartition,
    mutationItem,
    mutationTimestamp,
    mutationKind,
    ReplicaSets,
    TopologyOperators

PermissionKinds == {"SELECT", "MODIFY", "AUTHORIZE"}

ConsistencyLevels == {"ONE", "QUORUM", "ALL"}

WriteStates == {"None", "Accepted", "Succeeded", "Failed"}

ReadStates == {"Idle", "Pending", "Succeeded", "Failed", "Rejected"}

MigrateStates == {"Stable", "Streaming", "Activated", "CleanupEligible"}

MutationKinds == {"Put", "Delete"}

Resources == Keyspaces \cup Tables

InitialEpoch ==
    CHOOSE e \in Epochs : TRUE

AnyPrincipal ==
    CHOOSE p \in Principals : TRUE

AnyNode ==
    CHOOSE n \in Nodes : TRUE

AnyTable ==
    CHOOSE t \in Tables : TRUE

AnyPartition ==
    CHOOSE p \in Partitions : TRUE

AnyMutation ==
    CHOOSE m \in Mutations : TRUE

AnyRange ==
    CHOOSE r \in TokenRanges : TRUE

AnyResource ==
    CHOOSE x \in Resources : TRUE

RangeOfPartition(p) ==
    partitionRange[p]

RangeOfItem(i) ==
    RangeOfPartition(itemPartition[i])

RangeOfMutation(m) ==
    RangeOfItem(mutationItem[m])

TableOfItem(i) ==
    partitionTable[itemPartition[i]]

TableOfMutation(m) ==
    TableOfItem(mutationItem[m])

KeyspaceOfRange(r) ==
    rangeKeyspace[r]

ReplicaSet(e, r) ==
    ReplicaSets[e][KeyspaceOfRange(r)][r]

ItemsOfPartition(p) ==
    {i \in DataItems : itemPartition[i] = p}

MutationsOfItem(i) ==
    {m \in Mutations : mutationItem[m] = i}

MutationsOfRange(r) ==
    {m \in Mutations : RangeOfMutation(m) = r}

RequiredResponses(replicaCount, level) ==
    CASE level = "ONE" -> 1
      [] level = "QUORUM" -> (replicaCount \div 2) + 1
      [] level = "ALL" -> replicaCount

WinnerSet(S) ==
    {m \in S :
        \A x \in S :
            mutationItem[x] = mutationItem[m] =>
                mutationTimestamp[x] <= mutationTimestamp[m]}

ResolvedPutsFor(S, p) ==
    {m \in WinnerSet(S) :
        /\ itemPartition[mutationItem[m]] = p
        /\ mutationKind[m] = "Put"}

CoreAssumption ==
    /\ Principals # {}
    /\ Nodes # {}
    /\ Keyspaces # {}
    /\ Tables # {}
    /\ Partitions # {}
    /\ DataItems # {}
    /\ Mutations # {}
    /\ TokenRanges # {}
    /\ Epochs # {}
    /\ Cardinality(Epochs) >= 2
    /\ TopologyOperators \subseteq Principals
    /\ TopologyOperators # {}
    /\ tableKeyspace \in [Tables -> Keyspaces]
    /\ partitionTable \in [Partitions -> Tables]
    /\ partitionRange \in [Partitions -> TokenRanges]
    /\ rangeKeyspace \in [TokenRanges -> Keyspaces]
    /\ itemPartition \in [DataItems -> Partitions]
    /\ mutationItem \in [Mutations -> DataItems]
    /\ mutationTimestamp \in [Mutations -> Nat]
    /\ mutationKind \in [Mutations -> MutationKinds]
    /\ ReplicaSets \in
        [Epochs -> [Keyspaces -> [TokenRanges -> SUBSET Nodes]]]
    /\ \A p \in Partitions :
        tableKeyspace[partitionTable[p]]
            = rangeKeyspace[partitionRange[p]]
    /\ \A e \in Epochs :
        \A r \in TokenRanges :
            ReplicaSet(e, r) # {}
    /\ \A m1, m2 \in Mutations :
        mutationTimestamp[m1] = mutationTimestamp[m2] =>
            m1 = m2

CoreTypeOK ==
    CoreAssumption

====
