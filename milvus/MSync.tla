------------------------------- MODULE MSync -------------------------------

EXTENDS MWrite

VARIABLES
    syncedVersions, syncState, lastSync

SyncVars ==
    <<syncedVersions, syncState, lastSync>>

SyncRecordT ==
    [ kind   : {"None", "Some"},
      node   : Nodes,
      shard  : Shards,
      fromV  : VersionT,
      toV    : VersionT,
      phase  : {"Start", "Pull", "Finish"} ]

SyncTypeInvariant ==
    /\ syncedVersions \in [Nodes -> [Shards -> VersionT]]
    /\ syncState \in [Nodes -> [Shards -> SyncStateT]]
    /\ lastSync \in SyncRecordT

InitSync ==
    /\ syncedVersions = [n \in Nodes |-> [s \in Shards |-> 0]]
    /\ syncState = [n \in Nodes |-> [s \in Shards |-> "Idle"]]
    /\ lastSync =
        [ kind  |-> "None",
          node  |-> CHOOSE n \in Nodes : TRUE,
          shard |-> CHOOSE s \in Shards : TRUE,
          fromV |-> 0,
          toV   |-> 0,
          phase |-> "Start" ]

StartSync(node, s) ==
    /\ node \in Nodes
    /\ s \in Shards
    /\ syncState[node][s] = "Idle"
    /\ syncedVersions[node][s] < versionVector[s]
    /\ syncState' =
        [syncState EXCEPT ![node][s] = "Syncing"]
    /\ syncedVersions' = syncedVersions
    /\ lastSync' =
        [ kind  |-> "Some",
          node  |-> node,
          shard |-> s,
          fromV |-> syncedVersions[node][s],
          toV   |-> syncedVersions[node][s],
          phase |-> "Start" ]

PullSync(node, s) ==
    LET oldV == syncedVersions[node][s] IN
    LET newV == oldV + 1 IN
    /\ node \in Nodes
    /\ s \in Shards
    /\ syncState[node][s] = "Syncing"
    /\ oldV < versionVector[s]
    /\ syncedVersions' =
        [syncedVersions EXCEPT ![node][s] = newV]
    /\ syncState' = syncState
    /\ lastSync' =
        [ kind  |-> "Some",
          node  |-> node,
          shard |-> s,
          fromV |-> oldV,
          toV   |-> newV,
          phase |-> "Pull" ]

FinishSync(node, s) ==
    /\ node \in Nodes
    /\ s \in Shards
    /\ syncState[node][s] = "Syncing"
    /\ syncedVersions[node][s] = versionVector[s]
    /\ syncState' =
        [syncState EXCEPT ![node][s] = "Idle"]
    /\ syncedVersions' = syncedVersions
    /\ lastSync' =
        [ kind  |-> "Some",
          node  |-> node,
          shard |-> s,
          fromV |-> syncedVersions[node][s],
          toV   |-> syncedVersions[node][s],
          phase |-> "Finish" ]

NextSyncOnly ==
    \/ \E n \in Nodes, s \in Shards :
        StartSync(n, s)
    \/ \E n \in Nodes, s \in Shards :
        PullSync(n, s)
    \/ \E n \in Nodes, s \in Shards :
        FinishSync(n, s)

NextSync ==
    \/ /\ NextWrite
       /\ UNCHANGED SyncVars
    \/ /\ NextSyncOnly
       /\ UNCHANGED WriteVars

SyncSpec ==
    /\ CoreAssumption
    /\ AuthAssumption
    /\ InitAuth
    /\ InitWrite
    /\ InitSync
    /\ [][NextSync]_<<tsoVector, versionVector, sessionWriteTs,
                      lastWrite, pendingWrites, syncedVersions,
                      syncState, lastSync>>

SyncNotAheadOfWrite ==
    \A n \in Nodes, s \in Shards :
        syncedVersions[n][s] <= versionVector[s]

LastSyncValid ==
    lastSync.kind = "None"
    \/
    lastSync.toV <= versionVector[lastSync.shard]
        
=============================================================================
