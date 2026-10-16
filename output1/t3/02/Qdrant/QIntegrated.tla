------------------------------- MODULE QIntegrated -------------------------------

EXTENDS QFrontierInterface, QCfgHelpers

GlobalVars ==
    <<permission, writeState, wal, applied, ackSet, replicaHas, shardData,
      lastWrite, shardOwner, shardLocation, migrateState, migrateSrc,
      migrateDst, copiedData, lastMigrate, searchResult, lastSearch>>

Init ==
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitSearch

Next ==
    \/ NextAuth
       /\ UNCHANGED <<writeState, wal, applied, ackSet, replicaHas, shardData,
                      lastWrite, shardOwner, shardLocation, migrateState,
                      migrateSrc, migrateDst, copiedData, lastMigrate,
                      searchResult, lastSearch>>
    \/ NextWrite
       /\ UNCHANGED <<shardOwner, shardLocation, migrateState, migrateSrc,
                      migrateDst, copiedData, lastMigrate, searchResult,
                      lastSearch>>
    \/ NextMigrate
       /\ UNCHANGED <<searchResult, lastSearch>>
    \/ NextSearch

Spec == Init /\ [][Next]_GlobalVars

\* All invariants required by the specification are defined in QFrontierInterface
\* and are automatically available here through EXTENDS.

=============================================================================
