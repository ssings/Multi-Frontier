------------------------------- MODULE CAuth -------------------------------

EXTENDS CCore

VARIABLES
    permission,
    lastWrite,
    lastQuery,
    lastMigrate

AuthVars == <<permission, lastWrite, lastQuery, lastMigrate>>

AuthRecordT ==
    [ kind       : {"None", "Write", "Query", "Migrate"},
      principal  : Principals,
      keyspace   : Keyspaces,
      op         : Operations \cup {"None"},
      level      : ReadConsistencyLevels \cup {"None"},
      authorized : BOOLEAN ]

AuthTypeOK ==
    /\ permission \in [Principals -> [Keyspaces -> SUBSET Operations]]
    /\ lastWrite \in AuthRecordT
    /\ lastQuery \in AuthRecordT
    /\ lastMigrate \in AuthRecordT

InitAuth ==
    /\ permission = [p \in Principals |-> [ks \in Keyspaces |-> {}]]
    /\ lastWrite = [ kind |-> "None", principal |-> CHOOSE p \in Principals : TRUE, keyspace |-> CHOOSE ks \in Keyspaces : TRUE, op |-> "None", level |-> "None", authorized |-> FALSE ]
    /\ lastQuery = [ kind |-> "None", principal |-> CHOOSE p \in Principals : TRUE, keyspace |-> CHOOSE ks \in Keyspaces : TRUE, op |-> "None", level |-> "None", authorized |-> FALSE ]
    /\ lastMigrate = [ kind |-> "None", principal |-> CHOOSE p \in Principals : TRUE, keyspace |-> CHOOSE ks \in Keyspaces : TRUE, op |-> "None", level |-> "None", authorized |-> FALSE ]

CanAccess(p, ks, op) ==
    op \in permission[p][ks] \/ "Manage" \in permission[p][ks]

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
    /\ lastWrite' = [ kind |-> "Write", principal |-> p, keyspace |-> partitionKeyspace[pt], op |-> "Write", level |-> "None", authorized |-> FALSE ]
    /\ UNCHANGED <<permission, lastQuery, lastMigrate>>

RejectMigrate(p, sh) ==
    /\ p \in Principals
    /\ sh \in Shards
    /\ ~CanAccess(p, shardKeyspace[sh], "Migrate")
    /\ lastMigrate' = [ kind |-> "Migrate", principal |-> p, keyspace |-> shardKeyspace[sh], op |-> "Migrate", level |-> "None", authorized |-> FALSE ]
    /\ UNCHANGED <<permission, lastWrite, lastQuery>>

NextAuth ==
    \/ \E admin \in Principals :
        \E target \in Principals :
            \E ks \in Keyspaces :
                \E op \in Operations :
                    GrantPermission(admin, target, ks, op)
    \/ \E admin \in Principals :
        \E target \in Principals :
            \E ks \in Keyspaces :
                \E op \in Operations :
                    RevokePermission(admin, target, ks, op)
    \/ \E p \in Principals :
        \E pt \in Partitions :
            RejectWrite(p, pt)
    \/ \E p \in Principals :
        \E sh \in Shards :
            RejectMigrate(p, sh)

=============================================================================
