--------------------------- MODULE CCfgHelpers ---------------------------
EXTENDS CCore
\* Concrete model values
P1 == "P1"
P2 == "P2"
N1 == "N1"
N2 == "N2"
N3 == "N3"
TR1 == "TR1"
KS1 == "KS1"
T1 == "T1"
D1 == "D1"
D2 == "D2"
R1 == "R1"
R2 == "R2"
R3 == "R3"
TOKEN1 == "TOKEN1"

DataItemTableCfg == [d \in {D1, D2} |-> T1]
TableKeyspaceCfg == [t \in {T1} |-> KS1]
DataItemTokenCfg == [d \in {D1, D2} |-> TOKEN1]
TokenRangeForTokenCfg == [tok \in {TOKEN1} |-> TR1]
ReplicaSetCfg == [tr \in {TR1} |-> {R1, R2, R3}]
ReplicationFactorCfg == [ks \in {KS1} |-> 3]
ReplicaNodeCfg == [r \in {R1,R2,R3} |-> IF r = R1 THEN N1 ELSE IF r = R2 THEN N2 ELSE N3]
=============================================================================
