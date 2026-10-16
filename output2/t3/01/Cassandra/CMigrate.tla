------------------------------- MODULE CMigrate -------------------------------

EXTENDS CReplica

VARIABLES
    currentReplicas,
    migrateState,
    migrateSrc,
    migrateDst,
    copiedData

InitMigrate ==
    /\ currentReplicas = replicaSet
    /\ migrateState = [tr \in TokenRanges |-> "Stable"]
    /\ migrateSrc = [tr \in TokenRanges |-> {}]
    /\ migrateDst = [tr \in TokenRanges |-> {}]
    /\ copiedData = [tr \in TokenRanges |-> {}]

MigrationSafe(dataItem) ==
    LET tr == dataItemTokenRange[dataItem] IN
    \E r \in currentReplicas[tr] : dataItem \in replicaHas[r]

StartMigrate(principal, k, tr, newDstSet) ==
    /\ principal \in Principals
    /\ k \in Keyspaces
    /\ tr \in TokenRanges
    /\ newDstSet \subseteq Nodes
    /\ newDstSet # currentReplicas[tr]
    /\ CanAccess(principal, k, "Migrate")
    /\ migrateState[tr] = "Stable"
    /\ migrateState' = [migrateState EXCEPT ![tr] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![tr] = currentReplicas[tr]]
    /\ migrateDst' = [migrateDst EXCEPT ![tr] = newDstSet]
    /\ copiedData' = [copiedData EXCEPT ![tr] = {}]
    /\ currentReplicas' = currentReplicas
    /\ lastMigrate' = [ kind |-> "Some",
                         principal |-> principal,
                         keyspace |-> k,
                         tokenRange |-> tr,
                         phase |-> "Start",
                         authorized |-> TRUE ]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, replicaHas, permission, lastWrite, lastQuery>>

RejectMigrate(principal, k, tr, newDstSet) ==
    /\ principal \in Principals
    /\ k \in Keyspaces
    /\ tr \in TokenRanges
    /\ newDstSet \subseteq Nodes
    /\ ~CanAccess(principal, k, "Migrate")
    /\ UNCHANGED <<currentReplicas, migrateState, migrateSrc, migrateDst, copiedData,
                   writeRequested, writeLevel, ackCount, committed, replicaHas, permission>>
    /\ lastMigrate' = [ kind |-> "None",
                         principal |-> principal,
                         keyspace |-> k,
                         tokenRange |-> tr,
                         phase |-> "Start",
                         authorized |-> FALSE ]
    /\ UNCHANGED <<lastWrite, lastQuery>>

AdvanceMigrate(principal, tr) ==
    /\ principal \in Principals
    /\ tr \in TokenRanges
    /\ migrateState[tr] = "Migratering"
    /\ copiedData' = [copiedData EXCEPT ![tr] = {d \in committed : dataItemTokenRange[d] = tr}]
    /\ UNCHANGED <<currentReplicas, migrateState, migrateSrc, migrateDst,
                   writeRequested, writeLevel, ackCount, committed, replicaHas, permission,
                   lastWrite, lastQuery, lastMigrate>>

ActivateMigrate(principal, tr) ==
    /\ principal \in Principals
    /\ tr \in TokenRanges
    /\ migrateState[tr] = "Migratering"
    /\ {d \in committed : dataItemTokenRange[d] = tr} \subseteq copiedData[tr]
    /\ currentReplicas' = [currentReplicas EXCEPT ![tr] = migrateDst[tr]]
    /\ migrateState' = [migrateState EXCEPT ![tr] = "Activated"]
    /\ replicaHas' = [r \in Replicas |->
                        IF r \in migrateDst[tr]
                        THEN replicaHas[r] \cup copiedData[tr]
                        ELSE replicaHas[r]]
    /\ copiedData' = copiedData
    /\ lastMigrate' = [ kind |-> "Some",
                         principal |-> principal,
                         keyspace |-> CHOOSE k \in Keyspaces : TRUE,
                         tokenRange |-> tr,
                         phase |-> "Activate",
                         authorized |-> TRUE ]
    /\ UNCHANGED <<writeRequested, writeLevel, ackCount, committed, permission,
                   migrateSrc, migrateDst, lastWrite, lastQuery>>

FinishMigrate(principal, tr) ==
    /\ principal \in Principals
    /\ tr \in TokenRanges
    /\ migrateState[tr] = "Activated"
    /\ migrateState' = [migrateState EXCEPT ![tr] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![tr] = {}]
    /\ lastMigrate' = [ kind |-> "Some",
                         principal |-> principal,
                         keyspace |-> CHOOSE k \in Keyspaces : TRUE,
                         tokenRange |-> tr,
                         phase |-> "Finish",
                         authorized |-> TRUE ]
    /\ UNCHANGED <<currentReplicas, migrateSrc, migrateDst, replicaHas,
                   writeRequested, writeLevel, ackCount, committed, permission,
                   lastWrite, lastQuery>>

MigrateTypeOK ==
    /\ currentReplicas \in [TokenRanges -> SUBSET Nodes]
    /\ migrateState \in [TokenRanges -> {"Stable", "Migratering", "Activated"}]
    /\ migrateSrc \in [TokenRanges -> SUBSET Nodes]
    /\ migrateDst \in [TokenRanges -> SUBSET Nodes]
    /\ copiedData \in [TokenRanges -> SUBSET DataItems]

=============================================================================
