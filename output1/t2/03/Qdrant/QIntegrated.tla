--------------------------- MODULE QIntegrated ---------------------------
EXTENDS QSearch

vars == <<permission, writeState, wal, applied, ackSet, replicaHas, shardData, lastWrite,
         shardOwner, shardLocation, migrateState, migrateSrc, migrateDst, copiedData, lastMigrate,
         searchResult, lastSearch>>

Init == InitAuth /\ InitWrite /\ InitMigrate /\ InitSearch

Next == NextAuth \/ NextWrite \/ NextMigrate \/ NextSearch

Spec == Init /\ [][Next]_vars

=============================================================================
