------------------------------ MODULE QIntegrated ------------------------------

EXTENDS QSearch

\* Aggregate all variables into a single tuple for TLC
vars == <<
    permission,
    writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
    shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
    searchResult, lastSearch
>>

\* Initial state of all modules
Init == InitAuth /\ InitWrite /\ InitMigrate /\ InitSearch

\* Next-state relation of all modules
Next == NextAuth \/ NextWrite \/ NextMigrate \/ NextSearch

=============================================================================
