------------------------------- MODULE MCore -------------------------------

EXTENDS Naturals

CONSTANTS
    Nodes,
    Collections,
    Shards,
    Users,
    Roles,
    ConsistencyLevels,
    MaxVersion,
    MaxCatchUpLag,
    ShardMap

VersionT == 0..MaxVersion

PermissionT == {"Read", "Write", "Migrate", "Admin"}

MigrationStateT == {"Stable", "Migrating"}

SyncStateT == {"Idle", "Syncing"}

ShardFor(c) == ShardMap[c]

CoreAssumption ==
    /\ Nodes # {}
    /\ Collections # {}
    /\ Shards # {}
    /\ Users # {}
    /\ Roles # {}
    /\ ConsistencyLevels = {"Strong", "Bounded", "Session", "Eventually"}
    /\ MaxVersion \in Nat
    /\ MaxVersion > 0
    /\ MaxCatchUpLag \in Nat
    /\ MaxCatchUpLag > 0
    /\ DOMAIN ShardMap = Collections
    /\ \A c \in Collections : ShardMap[c] \in Shards
    
=============================================================================
