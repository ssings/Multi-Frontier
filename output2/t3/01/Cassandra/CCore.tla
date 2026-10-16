------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals, FiniteSets

CONSTANTS
    Principals,
    Nodes,
    TokenRanges,
    Keyspaces,
    Tables,
    DataItems,
    Replicas,
    replicaSet,
    dataItemTokenRange,
    dataItemTable,
    tableKeyspace

Operations == {"Read", "Write", "Manage", "Migrate"}

CoreAssumption ==
    /\ Principals # {}
    /\ Nodes # {}
    /\ TokenRanges # {}
    /\ Keyspaces # {}
    /\ Tables # {}
    /\ DataItems # {}
    /\ Replicas # {}
    /\ DOMAIN replicaSet = TokenRanges
    /\ \A tr \in TokenRanges : replicaSet[tr] \subseteq Nodes
    /\ \A tr \in TokenRanges : replicaSet[tr] # {}
    /\ DOMAIN dataItemTokenRange = DataItems
    /\ \A d \in DataItems : dataItemTokenRange[d] \in TokenRanges
    /\ DOMAIN dataItemTable = DataItems
    /\ \A d \in DataItems : dataItemTable[d] \in Tables
    /\ DOMAIN tableKeyspace = Tables
    /\ \A t \in Tables : tableKeyspace[t] \in Keyspaces

dataItemKeyspace(d) == tableKeyspace[dataItemTable[d]]

CoreTypeOK == TRUE

=============================================================================
