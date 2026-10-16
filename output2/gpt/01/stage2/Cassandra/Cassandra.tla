------------------------------ MODULE Cassandra ------------------------------

EXTENDS CassandraCfgSupport

SmokeInit ==
    /\ Init
    /\ permission = SmokePermissions

SmokeNext ==
    /\ Next
    /\ permission' = SmokePermissions

SmokeSpec ==
    SmokeInit /\ [][SmokeNext]_Vars

SmokeStateBound ==
    /\ permission = SmokePermissions
    /\ \A r \in TokenRanges :
        migrateState[r] = "Stable"

====
