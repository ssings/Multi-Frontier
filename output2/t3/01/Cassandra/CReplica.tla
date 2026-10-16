------------------------------- MODULE CReplica -------------------------------

EXTENDS CWrite

RequiredReads(level, rf) ==
    CASE level = "ONE"     -> 1
      [] level = "QUORUM"  -> (rf \div 2) + 1
      [] level = "ALL"     -> rf

ReplicaContains(dataItem) ==
    {r \in replicaSet[dataItemTokenRange[dataItem]] : dataItem \in replicaHas[r]}

Visible(dataItem, level) ==
    LET rf == Cardinality(replicaSet[dataItemTokenRange[dataItem]]) IN
    Cardinality(ReplicaContains(dataItem)) >= RequiredReads(level, rf)

ReplicaTypeOK == TRUE

=============================================================================
