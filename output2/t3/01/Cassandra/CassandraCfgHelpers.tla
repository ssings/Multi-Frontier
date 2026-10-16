------------------------------- MODULE CassandraCfgHelpers -------------------------------
EXTENDS CCore

ReplicaSetCfg == [tr \in TokenRanges |-> Nodes]

DataItemTokenRangeCfg == [d \in DataItems |-> CHOOSE tr \in TokenRanges : TRUE]

DataItemTableCfg == [d \in DataItems |-> CHOOSE t \in Tables : TRUE]

TableKeyspaceCfg == [t \in Tables |-> CHOOSE k \in Keyspaces : TRUE]

=============================================================================
