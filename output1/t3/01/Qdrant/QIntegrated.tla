--------------------------- MODULE QIntegrated ---------------------------

EXTENDS QFrontierInterface, QCfgHelpers

GlobalVars ==
    <<AuthVars,
      WriteVars,
      MigrateVars,
      SearchVars>>

Init ==
    /\ InitAuth
    /\ InitWrite
    /\ InitMigrate
    /\ InitSearch

Next ==
    \/ NextAuth
       /\ UNCHANGED <<WriteVars, MigrateVars, SearchVars>>
    \/ NextWrite
       /\ UNCHANGED <<AuthVars, MigrateVars, SearchVars>>
    \/ NextMigrate
       /\ UNCHANGED <<AuthVars, WriteVars, SearchVars>>
    \/ NextSearch
       /\ UNCHANGED <<AuthVars, WriteVars, MigrateVars>>

Spec == Init /\ [][Next]_GlobalVars

GlobalTypeInvariant ==
    /\ AuthTypeOK
    /\ WriteTypeOK
    /\ ReplicaTypeOK
    /\ MigrateTypeOK
    /\ SearchTypeOK

=============================================================================
