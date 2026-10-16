------------------------- MODULE CassandraCfgSupport -------------------------

EXTENDS CassandraFrontier

FirstPrincipal ==
    CHOOSE p \in Principals : TRUE

FirstNode ==
    CHOOSE n \in Nodes : TRUE

SecondNode ==
    CHOOSE n \in Nodes : n # FirstNode

ThirdNode ==
    CHOOSE n \in Nodes :
        /\ n # FirstNode
        /\ n # SecondNode

FourthNode ==
    CHOOSE n \in Nodes :
        /\ n # FirstNode
        /\ n # SecondNode
        /\ n # ThirdNode

OnlyKeyspace ==
    CHOOSE k \in Keyspaces : TRUE

OnlyTable ==
    CHOOSE t \in Tables : TRUE

OnlyPartition ==
    CHOOSE p \in Partitions : TRUE

OnlyRange ==
    CHOOSE r \in TokenRanges : TRUE

FirstItem ==
    CHOOSE i \in DataItems : TRUE

SecondItem ==
    CHOOSE i \in DataItems : i # FirstItem

FirstMutation ==
    CHOOSE m \in Mutations : TRUE

SecondMutation ==
    CHOOSE m \in Mutations : m # FirstMutation

TableKeyspaceCfg ==
    [t \in Tables |-> OnlyKeyspace]

PartitionTableCfg ==
    [p \in Partitions |-> OnlyTable]

PartitionRangeCfg ==
    [p \in Partitions |-> OnlyRange]

RangeKeyspaceCfg ==
    [r \in TokenRanges |-> OnlyKeyspace]

ItemPartitionCfg ==
    [i \in DataItems |-> OnlyPartition]

MutationItemCfg ==
    [m \in Mutations |->
        IF m = FirstMutation
        THEN FirstItem
        ELSE SecondItem]

MutationTimestampCfg ==
    [m \in Mutations |->
        IF m = FirstMutation
        THEN 1
        ELSE 2]

MutationKindCfg ==
    [m \in Mutations |-> "Put"]

ReplicaSetsCfg ==
    [e \in Epochs |->
        [k \in Keyspaces |->
            [r \in TokenRanges |->
                IF e = InitialEpoch
                THEN {FirstNode, SecondNode, ThirdNode}
                ELSE {FirstNode, SecondNode, FourthNode}]]]

TopologyOperatorsCfg ==
    {FirstPrincipal}

SmokePermissions ==
    [p \in Principals |->
        [resource \in Resources |-> PermissionKinds]]

====
