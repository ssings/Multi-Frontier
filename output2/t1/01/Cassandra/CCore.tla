------------------------------- MODULE CCore -------------------------------

EXTENDS Naturals

CONSTANTS
    Principals,
    Nodes,
    TokenRanges,
    Keyspaces,
    Tables,
    DataItems,
    Replicas,
    dataItemTable,
    tableKeyspace,
    dataItemToken,
    tokenRangeForToken,
    replicaSet,
    replicationFactor,
    replicaNode

Operations == {"Read", "Write", "Manage", "Migrate"}

WriteConsistencyLevels == {"ONE", "QUORUM", "ALL"}

ReadConsistencyLevels == {"ONE", "QUORUM", "ALL"}

KeyspaceOf(d) == tableKeyspace[dataItemTable[d]]

TokenRangeOf(d) == tokenRangeForToken[dataItemToken[d]]

ReplicaSetNodesOf(tr) ==
    {replicaNode[r] : r \in replicaSet[tr]}

CoreAssumption ==
    /\ Principals # {}
    /\ Nodes # {}
    /\ TokenRanges # {}
    /\ Keyspaces # {}
    /\ Tables # {}
    /\ DataItems # {}
    /\ Replicas # {}
    /\ DOMAIN dataItemTable = DataItems
    /\ DOMAIN tableKeyspace = Tables
    /\ DOMAIN dataItemToken = DataItems
    /\ DOMAIN tokenRangeForToken = {dataItemToken[d] : d \in DataItems}
    /\ DOMAIN replicaSet = TokenRanges
    /\ DOMAIN replicationFactor = Keyspaces
    /\ \A ks \in Keyspaces : replicationFactor[ks] \in Nat \ {0}
    /\ DOMAIN replicaNode = Replicas
    /\ \A tr \in TokenRanges : replicaSet[tr] # {}
    /\ \A d \in DataItems :
        /\ dataItemToken[d] \in DOMAIN tokenRangeForToken
        /\ TokenRangeOf(d) \in TokenRanges

CoreTypeOK == TRUE

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
