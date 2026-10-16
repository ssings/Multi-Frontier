---------------------------- MODULE Cassandra ----------------------------

EXTENDS CassandraFrontier, Naturals, FiniteSets

PrincipalRoleCfg ==
    [p \in {"principalA", "principalB"} |->
        "roleClient"]

RoleMembersCfg ==
    [r \in {"roleClient"} |->
        {}]

RoleReachCfg ==
    [r \in {"roleClient"} |->
        {r}]

TableKeyspaceCfg ==
    [t \in {"tableMain"} |->
        "ksMain"]

ItemTableCfg ==
    [item \in {"itemA", "itemB"} |->
        "tableMain"]

ItemPartitionCfg ==
    [item \in {"itemA", "itemB"} |->
        "partitionMain"]

PartitionRangeCfg ==
    [partition \in {"partitionMain"} |->
        "rangeMain"]

RangeKeyspaceCfg ==
    [ra \in {"rangeMain"} |->
        "ksMain"]

MutationItemCfg ==
    [m \in {"mutationA", "mutationB"} |->
        IF m = "mutationA"
        THEN "itemA"
        ELSE "itemB"]

MutationVersionCfg ==
    [m \in {"mutationA", "mutationB"} |->
        IF m = "mutationA"
        THEN 1
        ELSE 2]

MutationRankCfg ==
    [m \in {"mutationA", "mutationB"} |->
        IF m = "mutationA"
        THEN 1
        ELSE 2]

MutationKindCfg ==
    [m \in {"mutationA", "mutationB"} |->
        "Value"]

ReplicationFactorCfg ==
    [ks \in {"ksMain"} |->
        3]

InitialRoutingCfg ==
    [ra \in {"rangeMain"} |->
        {"nodeA", "nodeB", "nodeC"}]

InitialPermissionsCfg ==
    [r \in {"roleClient"} |->
        [resource \in {"tableMain", "ksMain", "ALL_KEYSPACES"} |->
            IF resource = "tableMain"
            THEN {"SELECT", "MODIFY"}
            ELSE {}]]

ReadPrincipalCfg ==
    [rd \in {"readA"} |->
        "principalA"]

ReadCoordinatorCfg ==
    [rd \in {"readA"} |->
        "nodeA"]

ReadItemCfg ==
    [rd \in {"readA"} |->
        "itemA"]

ReadLevelCfg ==
    [rd \in {"readA"} |->
        "QUORUM"]

=============================================================================
