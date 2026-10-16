------------------------- MODULE MFrontierInterface -------------------------

EXTENDS MMigrate


WriteFrontier(s) ==
    versionVector[s]

SyncFrontier(n, s) ==
    syncedVersions[n][s]

QueryFrontier(n, c) ==
    consistencyVector[n][c]

MigrationFrontier(s) ==
    migrationCopiedVersion[s]

MigrationTargetFrontier(s) ==
    syncedVersions[migrationTarget[s]][s]

FrontierInterfaceInvariant ==
    /\ \A n \in Nodes, s \in Shards :
        SyncFrontier(n, s) <= WriteFrontier(s)

    /\ \A n \in Nodes, c \in Collections :
        QueryFrontier(n, c) <= SyncFrontier(n, ShardFor(c))

    /\ \A s \in Shards :
        MigrationFrontier(s) <= WriteFrontier(s)

    /\ WALNotAheadOfTSO


MigrationRouteFrontierSafe ==
    \A s \in Shards :
        migrationState[s] = "Stable" =>
            SyncFrontier(shardNode[s], s) >= MigrationFrontier(s)

MigrationTargetFrontierSafe ==
    \A s \in Shards :
        migrationState[s] = "Migrating" =>
            MigrationTargetFrontier(s) >= MigrationFrontier(s)

=============================================================================
