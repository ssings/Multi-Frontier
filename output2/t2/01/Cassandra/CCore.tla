------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals

CONSTANTS
    Principals,
    Nodes,
    Replicas,
    TokenRanges,
    Keyspaces,
    Tables,
    DataItems,
    ConsistencyLevels,
    replicaNode,
    replicaSet,
    dataItemTokenRange,
    dataItemTable,
    tableKeyspace

\* Derived operators
TokenRangeOf(d) == dataItemTokenRange[d]

DataItemKeyspace(d) ==
    tableKeyspace[dataItemTable[d]]

Operations == {"Read", "Write", "Manage", "Migrate"}

CoreAssumption ==
    /\ Principals # {}
    /\ Nodes # {}
    /\ Replicas # {}
    /\ TokenRanges # {}
    /\ Keyspaces # {}
    /\ Tables # {}
    /\ DataItems # {}
    /\ ConsistencyLevels = {"ONE", "QUORUM", "ALL"}
    /\ \A r \in Replicas : replicaNode[r] \in Nodes
    /\ \A tr \in TokenRanges : replicaSet[tr] \subseteq Replicas
    /\ \A tr \in TokenRanges : replicaSet[tr] # {}
    /\ \A d \in DataItems : TokenRangeOf(d) \in TokenRanges
    /\ \A d \in DataItems : dataItemTable[d] \in Tables
    /\ \A t \in Tables : tableKeyspace[t] \in Keyspaces

CoreTypeOK ==
    CoreAssumption

=============================================================================
