------------------------------- MODULE CReplica -------------------------------

EXTENDS CWrite

ReplicaContains(d) ==
    {r \in replicaSet[TokenRangeOf(d)] : d \in replicaHas[r]}

Visible(d, level) ==
    LET count == Cardinality(ReplicaContains(d))
        rf    == Cardinality(replicaSet[TokenRangeOf(d)])
    IN CASE level = "ONE"     -> count >= 1
       [] level = "QUORUM"   -> 2 * count > rf
       [] level = "ALL"      -> ReplicaContains(d) = replicaSet[TokenRangeOf(d)]

ReplicaTypeInvariant ==
    WriteTypeInvariant

=============================================================================
