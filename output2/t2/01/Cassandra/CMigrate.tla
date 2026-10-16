------------------------------- MODULE CMigrate -------------------------------

EXTENDS CReplica

VARIABLES
    tokenReplicas,
    migrateState,
    migrateSrcNodes,
    migrateDstNodes,
    copiedData,
    lastMigrate

MigrateRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      tokenRange : TokenRanges,
      authorized : BOOLEAN ]

MigrateTypeInvariant ==
    /\ tokenReplicas \in [TokenRanges -> SUBSET Replicas]
    /\ migrateState \in [TokenRanges -> {"Stable", "Migratering", "Activated"}]
    /\ migrateSrcNodes \in [TokenRanges -> SUBSET Nodes]
    /\ migrateDstNodes \in [TokenRanges -> SUBSET Nodes]
    /\ copiedData \in [TokenRanges -> SUBSET DataItems]
    /\ lastMigrate \in MigrateRecordT

CurrentNodes(tr) ==
    {replicaNode[r] : r \in tokenReplicas[tr]}

MigrationSafe(d) ==
    \E r \in tokenReplicas[TokenRangeOf(d)] : d \in replicaHas[r]

InitMigrate ==
    /\ tokenReplicas = [tr \in TokenRanges |-> replicaSet[tr]]
    /\ migrateState = [tr \in TokenRanges |-> "Stable"]
    /\ migrateSrcNodes = [tr \in TokenRanges |-> {}]
    /\ migrateDstNodes = [tr \in TokenRanges |-> {}]
    /\ copiedData = [tr \in TokenRanges |-> {}]
    /\ lastMigrate =
        [ kind       |-> "None",
          principal  |-> CHOOSE p \in Principals : TRUE,
          tokenRange |-> CHOOSE tr \in TokenRanges : TRUE,
          authorized |-> FALSE ]

StartMigrate(p, tr, dstNodes) ==
    /\ p \in Principals
    /\ tr \in TokenRanges
    /\ dstNodes \subseteq Nodes
    /\ CanMigrate(p)
    /\ migrateState[tr] = "Stable"
    /\ dstNodes # CurrentNodes(tr)
    /\ dstNodes # {}
    /\ migrateState' = [migrateState EXCEPT ![tr] = "Migratering"]
    /\ migrateSrcNodes' = [migrateSrcNodes EXCEPT ![tr] = CurrentNodes(tr)]
    /\ migrateDstNodes' = [migrateDstNodes EXCEPT ![tr] = dstNodes]
    /\ copiedData' = [copiedData EXCEPT ![tr] = {}]
    /\ tokenReplicas' = tokenReplicas
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          tokenRange |-> tr,
          authorized |-> TRUE ]
    /\ UNCHANGED <<permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas,
                   lastWrite>>

RejectMigrate(p, tr) ==
    /\ p \in Principals
    /\ tr \in TokenRanges
    /\ ~CanMigrate(p)
    /\ UNCHANGED <<tokenReplicas, migrateState, migrateSrcNodes,
                   migrateDstNodes, copiedData,
                   permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas,
                   lastWrite>>
    /\ lastMigrate' =
        [ kind       |-> "Some",
          principal  |-> p,
          tokenRange |-> tr,
          authorized |-> FALSE ]

AdvanceMigrate(tr) ==
    /\ tr \in TokenRanges
    /\ migrateState[tr] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![tr] =
                        {d \in committed : TokenRangeOf(d) = tr}]
    /\ UNCHANGED <<tokenReplicas, migrateState, migrateSrcNodes,
                   migrateDstNodes, lastMigrate,
                   permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas,
                   lastWrite>>

ActivateMigrate(tr) ==
    /\ tr \in TokenRanges
    /\ migrateState[tr] = "Migratering"
    /\ {d \in committed : TokenRangeOf(d) = tr} \subseteq copiedData[tr]
    /\ LET newReplicas == {r \in Replicas : replicaNode[r] \in migrateDstNodes[tr]}
       IN /\ tokenReplicas' = [tokenReplicas EXCEPT ![tr] = newReplicas]
          /\ replicaHas' = [r \in Replicas |->
                IF r \in newReplicas
                THEN replicaHas[r] \cup copiedData[tr]
                ELSE replicaHas[r]]
    /\ migrateState' = [migrateState EXCEPT ![tr] = "Activated"]
    /\ UNCHANGED <<migrateSrcNodes, migrateDstNodes, copiedData,
                   lastMigrate,
                   permission,
                   writeRequested, writeLevel, ackCount, committed,
                   lastWrite>>

FinishMigrate(tr) ==
    /\ tr \in TokenRanges
    /\ migrateState[tr] = "Activated"
    /\ migrateState' = [migrateState EXCEPT ![tr] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![tr] = {}]
    /\ UNCHANGED <<tokenReplicas, migrateSrcNodes, migrateDstNodes,
                   lastMigrate,
                   permission,
                   writeRequested, writeLevel, ackCount, committed, replicaHas,
                   lastWrite>>

NextMigrateOnly ==
    \/ \E p, tr, dst : StartMigrate(p, tr, dst)
    \/ \E p, tr : RejectMigrate(p, tr)
    \/ \E tr : AdvanceMigrate(tr)
    \/ \E tr : ActivateMigrate(tr)
    \/ \E tr : FinishMigrate(tr)

=============================================================================
