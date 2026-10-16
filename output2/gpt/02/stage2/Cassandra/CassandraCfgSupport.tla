----------------------- MODULE CassandraCfgSupport -----------------------

EXTENDS Naturals, FiniteSets

PrincipalRoleCfgBase ==
    [p \in {"principalA", "principalB"} |->
        "roleClient"]

RoleMembersCfgBase ==
    [r \in {"roleClient"} |->
        {}]

RoleReachCfgBase ==
    [r \in {"roleClient"} |->
        {r}]

TableKeyspaceCfgBase ==
    [t \in {"tableMain"} |->
        "ksMain"]

ItemTableCfgBase ==
    [item \in {"itemA", "itemB"} |->
        "tableMain"]

ItemPartitionCfgBase ==
    [item \in {"itemA", "itemB"} |->
        "partitionMain"]

PartitionRangeCfgBase ==
    [partition \in {"partitionMain"} |->
        "rangeMain"]

RangeKeyspaceCfgBase ==
    [ra \in {"rangeMain"} |->
        "ksMain"]

MutationItemCfgBase ==
    [m \in {"mutationA", "mutationB"} |->
        IF m = "mutationA"
        THEN "itemA"
        ELSE "itemB"]

MutationVersionCfgBase ==
    [m \in {"mutationA", "mutationB"} |->
        IF m = "mutationA"
        THEN 1
        ELSE 2]

MutationRankCfgBase ==
    [m \in {"mutationA", "mutationB"} |->
        IF m = "mutationA"
        THEN 1
        ELSE 2]

MutationKindCfgBase ==
    [m \in {"mutationA", "mutationB"} |->
        "Value"]

ReplicationFactorCfgBase ==
    [ks \in {"ksMain"} |->
        3]

InitialRoutingCfgBase ==
    [ra \in {"rangeMain"} |->
        {"nodeA", "nodeB", "nodeC"}]

InitialPermissionsCfgBase ==
    [r \in {"roleClient"} |->
        [resource \in {"tableMain", "ksMain", "ALL_KEYSPACES"} |->
            IF resource = "tableMain"
            THEN {"SELECT", "MODIFY"}
            ELSE {}]]

ReadPrincipalCfgBase ==
    [rd \in {"readA"} |->
        "principalA"]

ReadCoordinatorCfgBase ==
    [rd \in {"readA"} |->
        "nodeA"]

ReadItemCfgBase ==
    [rd \in {"readA"} |->
        "itemA"]

ReadLevelCfgBase ==
    [rd \in {"readA"} |->
        "QUORUM"]

=============================================================================
