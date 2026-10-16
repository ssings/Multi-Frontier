------------------------------- MODULE CAuth -------------------------------

EXTENDS CCore

VARIABLES permission, lastWrite, lastQuery, lastMigrate

WriteRecordT == [principal: Principals, partition: Partitions, authorized: BOOLEAN]
QueryRecordT == [principal: Principals, keyspace: Keyspaces, level: ReadConsistencyLevels, result: SUBSET Partitions, authorized: BOOLEAN]
MigrateRecordT == [principal: Principals, shard: Shards, phase: {"Start","Advance","Activate","Finish"}, authorized: BOOLEAN]

AuthTypeInvariant ==
    /\ permission \in [Principals -> [Keyspaces -> SUBSET Operations]]
    /\ lastWrite \in WriteRecordT
    /\ lastQuery \in QueryRecordT
    /\ lastMigrate \in MigrateRecordT

CanAccess(p, ks, op) ==
    op \in permission[p][ks]
    \/ "Manage" \in permission[p][ks]

InitAuth ==
    /\ permission = [p \in Principals |-> [ks \in Keyspaces |-> {}]]
    /\ lastWrite = [principal |-> CHOOSE p \in Principals : TRUE,
                    partition |-> CHOOSE pt \in Partitions : TRUE,
                    authorized |-> FALSE]
    /\ lastQuery = [principal |-> CHOOSE p \in Principals : TRUE,
                    keyspace |-> CHOOSE ks \in Keyspaces : TRUE,
                    level |-> CHOOSE lv \in ReadConsistencyLevels : TRUE,
                    result |-> {},
                    authorized |-> FALSE]
    /\ lastMigrate = [principal |-> CHOOSE p \in Principals : TRUE,
                       shard |-> CHOOSE s \in Shards : TRUE,
                       phase |-> "Start",
                       authorized |-> FALSE]

GrantPermission(admin, target, ks, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, ks, "Manage")
    /\ permission' = [permission EXCEPT ![target][ks] = @ \cup {op}]
    /\ UNCHANGED <<lastWrite, lastQuery, lastMigrate>>

RevokePermission(admin, target, ks, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, ks, "Manage")
    /\ permission' = [permission EXCEPT ![target][ks] = @ \ {op}]
    /\ UNCHANGED <<lastWrite, lastQuery, lastMigrate>>

RejectWrite(p, pt) ==
    /\ p \in Principals
    /\ pt \in Partitions
    /\ ~CanAccess(p, partitionKeyspace[pt], "Write")
    /\ lastWrite' = [principal |-> p, partition |-> pt, authorized |-> FALSE]
    /\ UNCHANGED <<permission, lastQuery, lastMigrate>>

RejectQuery(p, ks, lv) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ lv \in ReadConsistencyLevels
    /\ ~CanAccess(p, ks, "Read")
    /\ lastQuery' = [principal |-> p, keyspace |-> ks, level |-> lv, result |-> {}, authorized |-> FALSE]
    /\ UNCHANGED <<permission, lastWrite, lastMigrate>>

RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ src \in Nodes
    /\ dst \in Nodes
    /\ ~CanAccess(p, shardKeyspace[s], "Migrate")
    /\ lastMigrate' = [principal |-> p, shard |-> s, phase |-> "Start", authorized |-> FALSE]
    /\ UNCHANGED <<permission, lastWrite, lastQuery>>

LastWriteAuthorized ==
    \/ lastWrite.authorized = FALSE
    \/ CanAccess(lastWrite.principal, partitionKeyspace[lastWrite.partition], "Write")

LastQueryAuthorized ==
    \/ lastQuery.authorized = FALSE
    \/ CanAccess(lastQuery.principal, lastQuery.keyspace, "Read")

LastMigrateAuthorized ==
    \/ lastMigrate.authorized = FALSE
    \/ CanAccess(lastMigrate.principal, shardKeyspace[lastMigrate.shard], "Migrate")

AuthSafety ==
    /\ LastWriteAuthorized
    /\ LastQueryAuthorized
    /\ LastMigrateAuthorized

=============================================================================
