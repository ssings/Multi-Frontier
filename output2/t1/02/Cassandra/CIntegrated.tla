------------------------------- MODULE CIntegrated -------------------------------

EXTENDS CFrontierInterface, CCfgHelpers

Vars == <<permission,
          writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
          shardOwner, shardLocation, migrateState,
          migrateSrc, migrateDst, copiedData, lastMigrate,
          readResult, lastRead>>

Init ==
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitRead

Next ==
    \/ /\ NextAuth
       /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                      shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData,
                      lastMigrate, readResult, lastRead>>
    \/ /\ NextWrite
       /\ UNCHANGED <<shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData,
                      lastMigrate, readResult, lastRead>>
    \/ /\ NextMigrate
       /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData,
                      lastWrite, readResult, lastRead>>
    \/ /\ NextRead
       /\ UNCHANGED <<permission, writeState, wal, applied, ackSet, replicaHas, shardData,
                      lastWrite, shardOwner, shardLocation, migrateState, migrateSrc, migrateDst,
                      copiedData, lastMigrate>>

Spec ==
    /\ CoreAssumption
    /\ Init
    /\ [][Next]_Vars

GlobalTypeInvariant ==
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ ReplicaTypeOK
    /\ MigrateTypeOK
    /\ ReadTypeOK

AuthSafety ==
    /\ (lastWrite.authorized) => CanAccess(lastWrite.principal, recordKeyspace[lastWrite.record], "Write")
    /\ (lastRead.authorized) => CanAccess(lastRead.principal, lastRead.keyspace, "Read")
    /\ (lastMigrate.authorized) => CanAccess(lastMigrate.principal, partitionKeyspace[lastMigrate.partition], "Migrate")
    /\ lastWrite.kind = "Some" /\ ~lastWrite.authorized => ~CanAccess(lastWrite.principal, recordKeyspace[lastWrite.record], "Write")
    /\ lastRead.kind = "Some" /\ ~lastRead.authorized => ~CanAccess(lastRead.principal, lastRead.keyspace, "Read")
    /\ lastMigrate.kind = "Some" /\ ~lastMigrate.authorized =>
       ~CanAccess(lastMigrate.principal, partitionKeyspace[lastMigrate.partition], "Migrate")

WalBeforeApply ==
    applied \subseteq wal

ReplicaNotAheadOfWAL ==
    \A rep \in Replicas : replicaHas[rep] \subseteq wal

IntegratedSafety ==
    /\ GlobalTypeInvariant
    /\ AuthSafety
    /\ WalBeforeApply
    /\ ReplicaNotAheadOfWAL
    /\ MigrateSafety
    /\ FrontierSafety

=============================================================================
\* Modification History
\* Created for Cassandra Frontier-based TLA+ model
