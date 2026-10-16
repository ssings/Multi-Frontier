----------------------------- MODULE CMigrate -----------------------------

EXTENDS CReplica

VARIABLES
    currentReplicas,
    migrateState,
    migrateSrc,
    migrateDst,
    copiedData

MigrateVars == <<currentReplicas, migrateState, migrateSrc,
                  migrateDst, copiedData>>

MigrationSafe(d) ==
    LET tr == TokenRangeOf(d) IN
    \E r \in replicaSet[tr] :
        /\ replicaNode[r] \in currentReplicas[tr]
        /\ d \in replicaHas[r]

InitMigrate ==
    /\ currentReplicas = [tr \in TokenRanges |-> ReplicaSetNodesOf(tr)]
    /\ migrateState = [tr \in TokenRanges |-> "Stable"]
    /\ migrateSrc = currentReplicas
    /\ migrateDst = currentReplicas
    /\ copiedData = [tr \in TokenRanges |-> {}]

StartMigrate(p, tr, dst) ==
    /\ p \in Principals
    /\ tr \in TokenRanges
    /\ dst \in SUBSET Nodes
    /\ CanMigrate(p)
    /\ migrateState[tr] = "Stable"
    /\ dst # currentReplicas[tr]
    /\ migrateState' = [migrateState EXCEPT ![tr] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![tr] = currentReplicas[tr]]
    /\ migrateDst' = [migrateDst EXCEPT ![tr] = dst]
    /\ copiedData' = [copiedData EXCEPT ![tr] = {}]
    /\ lastMigrate' = [kind |-> "Some", principal |-> p,
                        tokenRange |-> tr, phase |-> "Start",
                        authorized |-> TRUE]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas,
                   permission, lastWrite, lastQuery>>

RejectMigrate(p, tr, dst) ==
    /\ p \in Principals
    /\ tr \in TokenRanges
    /\ dst \in SUBSET Nodes
    /\ ~CanMigrate(p)
    /\ lastMigrate' = [kind |-> "Some", principal |-> p,
                        tokenRange |-> tr, phase |-> "Start",
                        authorized |-> FALSE]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastQuery>>

AdvanceMigrate(tr) ==
    /\ tr \in TokenRanges
    /\ migrateState[tr] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![tr] =
        {d \in committed : TokenRangeOf(d) = tr}]
    /\ lastMigrate' = [kind |-> "Some", principal |-> lastMigrate.principal,
                        tokenRange |-> tr, phase |-> "Advance",
                        authorized |-> TRUE]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas, migrateState,
                   migrateSrc, migrateDst,
                   permission, lastWrite, lastQuery>>

ActivateMigrate(tr) ==
    LET targetData == {d \in committed : TokenRangeOf(d) = tr}
        targetReplicas ==
            {r \in replicaSet[tr] : replicaNode[r] \in migrateDst[tr]}
    IN
    /\ tr \in TokenRanges
    /\ migrateState[tr] = "Migratering"
    /\ targetData \subseteq copiedData[tr]
    /\ \E r \in targetReplicas :
        /\ replicaHas' = [replicaHas EXCEPT ![r] =
              @ \cup copiedData[tr]]
    /\ currentReplicas' = [currentReplicas EXCEPT ![tr] =
        migrateDst[tr]]
    /\ migrateState' = [migrateState EXCEPT ![tr] = "Activated"]
    /\ lastMigrate' = [kind |-> "Some", principal |-> lastMigrate.principal,
                        tokenRange |-> tr, phase |-> "Activate",
                        authorized |-> TRUE]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   migrateSrc, migrateDst, copiedData,
                   permission, lastWrite, lastQuery>>

FinishMigrate(tr) ==
    /\ tr \in TokenRanges
    /\ migrateState[tr] = "Activated"
    /\ migrateState' = [migrateState EXCEPT ![tr] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![tr] = {}]
    /\ lastMigrate' = [kind |-> "Some", principal |-> lastMigrate.principal,
                        tokenRange |-> tr, phase |-> "Finish",
                        authorized |-> TRUE]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed,
                   replicaHas, currentReplicas,
                   migrateSrc, migrateDst,
                   permission, lastWrite, lastQuery>>

MigrateTypeOK ==
    /\ currentReplicas \in [TokenRanges -> SUBSET Nodes]
    /\ migrateState \in [TokenRanges -> {"Stable","Migratering","Activated"}]
    /\ migrateSrc \in [TokenRanges -> SUBSET Nodes]
    /\ migrateDst \in [TokenRanges -> SUBSET Nodes]
    /\ copiedData \in [TokenRanges -> SUBSET DataItems]

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
