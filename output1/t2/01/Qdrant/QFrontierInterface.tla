------------------------------- MODULE QFrontierInterface -------------------------------

EXTENDS QSearch

\* Migrate safety: when a migrate is not in Stable state, source and destination must differ.
\* During Stable state, source and destination are allowed to coincide (initial or after finish).
MigrateSafety ==
    \A s \in Shards : (migrateState[s] = "Stable") \/ (migrateSrc[s] # migrateDst[s])

\* Write safety: no point is applied without having been WAL-logged first.
WriteSafety ==
    applied \subseteq wal

\* Search safety: if a search was executed, the result is exactly the eligible set
\* defined by the last search parameters.
SearchSafety ==
    \/ lastSearch.executed = FALSE
    \/ searchResult = SearchEligibleSet(lastSearch.principal,
                                       lastSearch.collection,
                                       lastSearch.level)

\* Shard data correctness: committed shard data is exactly the applied points of that shard.
DataSafety ==
    \A s \in Shards : shardData[s] = applied \cap PointsOfShard(s)

=============================================================================
