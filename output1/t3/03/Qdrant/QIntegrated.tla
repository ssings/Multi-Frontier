------------------------------ MODULE QIntegrated -------------------------

EXTENDS QFrontierInterface, QCfgHelpers

\* GlobalVars encompasses all state variables
GlobalVars ==
    <<permission,
      writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
      shardOwner, shardLocation, migrateState,
      migrateSrc, migrateDst, copiedData, lastMigrate,
      searchResult, lastSearch>>

\* Initialize all modules
Init ==
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitSearch

\* Full next‑state relation
Next ==
    \/ NextAuth
        /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                       shardOwner, shardLocation, migrateState,
                       migrateSrc, migrateDst, copiedData, lastMigrate,
                       searchResult, lastSearch>>
    \/ NextWrite
        /\ UNCHANGED <<permission,
                       shardOwner, shardLocation, migrateState,
                       migrateSrc, migrateDst, copiedData, lastMigrate,
                       searchResult, lastSearch>>
    \/ NextMigrate
        /\ UNCHANGED <<permission,
                       writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                       searchResult, lastSearch>>
    \/ NextSearch
        /\ UNCHANGED <<permission,
                       writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
                       shardOwner, shardLocation, migrateState,
                       migrateSrc, migrateDst, copiedData, lastMigrate>>

\* Specification
Spec == Init /\ [][Next]_GlobalVars

\* Global type invariant (composition of all TypeOKs)
GlobalTypeInvariant ==
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ MigrateTypeOK
    /\ SearchTypeOK

\* Safety invariants are inherited from QFrontierInterface:
\*   AuthSafety, WalBeforeApply, ReplicaNotAheadOfWAL, MigrateSafety, FrontierSafety
\* (They must not be re‑defined here.)

=============================================================================
