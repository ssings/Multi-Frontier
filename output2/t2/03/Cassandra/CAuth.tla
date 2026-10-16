------------------------------- MODULE CAuth -------------------------------

EXTENDS CCore

Operations == {"Read", "Write", "Manage", "Migrate"}

VARIABLES
    permission,
    lastWrite,
    lastQuery,
    lastMigrate

WriteRecordT ==
    [authorized : BOOLEAN,
     principal  : Principals,
     keyspace   : Keyspaces,
     partition  : Partitions]

QueryRecordT ==
    [authorized : BOOLEAN,
     principal  : Principals,
     keyspace   : Keyspaces,
     level      : ReadConsistencyLevels,
     result     : SUBSET Partitions]

MigrateRecordT ==
    [authorized : BOOLEAN,
     principal  : Principals,
     shard      : Shards]

CanAccess(p, ks, op) ==
    op \in permission[p][ks] \/ "Manage" \in permission[p][ks]

GrantPermission(admin, target, ks, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, ks, "Manage")
    /\ op \notin permission[target][ks]
    /\ permission' = [permission EXCEPT ![target][ks] = @ \cup {op}]
    /\ UNCHANGED <<lastWrite, lastQuery, lastMigrate>>

RevokePermission(admin, target, ks, op) ==
    /\ admin \in Principals
    /\ target \in Principals
    /\ ks \in Keyspaces
    /\ op \in Operations
    /\ CanAccess(admin, ks, "Manage")
    /\ op \in permission[target][ks]
    /\ permission' = [permission EXCEPT ![target][ks] = @ \ {op}]
    /\ UNCHANGED <<lastWrite, lastQuery, lastMigrate>>

RejectWrite(p, pt) ==
    LET ks == partitionKeyspace[pt] IN
    /\ p \in Principals
    /\ pt \in Partitions
    /\ ~CanAccess(p, ks, "Write")
    /\ lastWrite' = [authorized |-> FALSE, principal |-> p, keyspace |-> ks, partition |-> pt]
    /\ UNCHANGED <<permission, lastQuery, lastMigrate>>

RejectQuery(p, ks, level) ==
    /\ p \in Principals
    /\ ks \in Keyspaces
    /\ level \in ReadConsistencyLevels
    /\ ~CanAccess(p, ks, "Read")
    /\ lastQuery' = [authorized |-> FALSE, principal |-> p, keyspace |-> ks, level |-> level, result |-> {}]
    /\ UNCHANGED <<permission, lastWrite, lastMigrate>>

RejectMigrate(p, sh) ==
    LET ks == shardKeyspace[sh] IN
    /\ p \in Principals
    /\ sh \in Shards
    /\ ~CanAccess(p, ks, "Migrate")
    /\ lastMigrate' = [authorized |-> FALSE, principal |-> p, shard |-> sh]
    /\ UNCHANGED <<permission, lastWrite, lastQuery>>

AuthTypeInvariant ==
    /\ permission \in [Principals -> [Keyspaces -> SUBSET Operations]]
    /\ lastWrite \in WriteRecordT
    /\ lastQuery \in QueryRecordT
    /\ lastMigrate \in MigrateRecordT

=============================================================================
