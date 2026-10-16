----------------------------- MODULE QMigrate ------------------------------

EXTENDS QReplica

VARIABLES
    shardOwner,      \* [Shards -> Nodes]        current owner node
    shardLocation,   \* [Shards -> SUBSET Nodes] nodes that may hold data
    migrateState,   \* [Shards -> MigrateStates]
    migrateSrc,     \* [Shards -> Nodes]        source node during migrate
    migrateDst,     \* [Shards -> Nodes]        destination node
    copiedData,      \* [Shards -> SUBSET Points] data copied to destination
    lastMigrate     \* record of last migrate attempt

MigrateVars ==
    <<shardOwner, shardLocation, migrateState,
      migrateSrc, migrateDst, copiedData, lastMigrate>>

MigrateRecordT ==
    [ kind       : {"None", "Some"},
      principal  : Principals,
      shard      : Shards,
      srcNode    : Nodes,
      dstNode    : Nodes,
      phase      : {"Start", "Advance", "Activate", "Finish"},
      authorized : BOOLEAN ]

MigrateTypeOK ==
    /\ shardOwner \in [Shards -> Nodes]
    /\ shardLocation \in [Shards -> SUBSET Nodes]
    /\ migrateState \in [Shards -> MigrateStates]
    /\ migrateSrc \in [Shards -> Nodes]
    /\ migrateDst \in [Shards -> Nodes]
    /\ copiedData \in [Shards -> SUBSET Points]
    /\ lastMigrate \in MigrateRecordT

InitMigrate ==
    /\ shardOwner = [s \in Shards |-> CHOOSE n \in Nodes : TRUE]
    /\ shardLocation = [s \in Shards |-> {shardOwner[s]}]
    /\ migrateState = [s \in Shards |-> "Stable"]
    /\ migrateSrc = shardOwner
    /\ migrateDst = shardOwner
    /\ copiedData = [s \in Shards |-> {}]
    /\ lastMigrate = [ kind |-> "None",
                        principal |-> CHOOSE p \in Principals : TRUE,
                        shard |-> CHOOSE s \in Shards : TRUE,
                        srcNode |-> CHOOSE n \in Nodes : TRUE,
                        dstNode |-> CHOOSE n \in Nodes : TRUE,
                        phase |-> "Start",
                        authorized |-> FALSE ]

\* Start a shard migrate from src to dst
StartMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Stable"
    /\ src = shardOwner[s]
    /\ dst \in Nodes
    /\ dst # src
    /\ migrateState' = [migrateState EXCEPT ![s] = "Migratering"]
    /\ migrateSrc' = [migrateSrc EXCEPT ![s] = src]
    /\ migrateDst' = [migrateDst EXCEPT ![s] = dst]
    /\ shardLocation' = [shardLocation EXCEPT ![s] = @ \cup {dst}]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' = [ kind |-> "Some",
                         principal |-> p,
                         shard |-> s,
                         srcNode |-> src,
                         dstNode |-> dst,
                         phase |-> "Start",
                         authorized |-> TRUE ]
    /\ UNCHANGED <<shardOwner>>

\* Reject an unauthorized migrate attempt
RejectMigrate(p, s, src, dst) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ ~CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Stable"
    /\ src = shardOwner[s]
    /\ dst \in Nodes
    /\ dst # src
    /\ lastMigrate' = [ kind |-> "Some",
                         principal |-> p,
                         shard |-> s,
                         srcNode |-> src,
                         dstNode |-> dst,
                         phase |-> "Start",
                         authorized |-> FALSE ]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                  migrateSrc, migrateDst, copiedData>>

\* One-shot copy: destination catches up with all committed data
AdvanceMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ copiedData[s] = {}
    /\ copiedData' = [copiedData EXCEPT ![s] = shardData[s]]
    /\ lastMigrate' = [ kind |-> "Some",
                         principal |-> p,
                         shard |-> s,
                         srcNode |-> migrateSrc[s],
                         dstNode |-> migrateDst[s],
                         phase |-> "Advance",
                         authorized |-> TRUE ]
    /\ UNCHANGED <<shardOwner, shardLocation, migrateState,
                  migrateSrc, migrateDst>>

\* Activate destination as the new owner when all committed points are copied
ActivateMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Migratering"
    /\ (applied \cap PointsOfShard(s)) \subseteq copiedData[s]
    /\ shardOwner' = [shardOwner EXCEPT ![s] = migrateDst[s]]
    /\ shardData'  = [shardData EXCEPT ![s] = copiedData[s]]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Activated"]
    /\ lastMigrate' = [ kind |-> "Some",
                         principal |-> p,
                         shard |-> s,
                         srcNode |-> migrateSrc[s],
                         dstNode |-> migrateDst[s],
                         phase |-> "Activate",
                         authorized |-> TRUE ]
    /\ UNCHANGED <<shardLocation, migrateSrc, migrateDst, copiedData>>

\* Finalize migrate, cleaning up temporary state
FinishMigrate(p, s) ==
    /\ p \in Principals
    /\ s \in Shards
    /\ CanAccess(p, shardCollection[s], "Migrate")
    /\ migrateState[s] = "Activated"
    /\ shardLocation' = [shardLocation EXCEPT ![s] = {shardOwner[s]}]
    /\ migrateState' = [migrateState EXCEPT ![s] = "Stable"]
    /\ copiedData' = [copiedData EXCEPT ![s] = {}]
    /\ lastMigrate' = [ kind |-> "Some",
                         principal |-> p,
                         shard |-> s,
                         srcNode |-> migrateSrc[s],
                         dstNode |-> migrateDst[s],
                         phase |-> "Finish",
                         authorized |-> TRUE ]
    /\ UNCHANGED <<shardOwner, shardData, migrateSrc, migrateDst>>

\* Point is safe for reading after any migrate has been resolved
MigrationSafe(pt) ==
    pt \in shardData[pointShard[pt]]

NextMigrate ==
    \/ \E p \in Principals, s \in Shards, src \in Nodes, dst \in Nodes :
        StartMigrate(p, s, src, dst)
    \/ \E p \in Principals, s \in Shards, src \in Nodes, dst \in Nodes :
        RejectMigrate(p, s, src, dst)
    \/ \E p \in Principals, s \in Shards :
        AdvanceMigrate(p, s)
    \/ \E p \in Principals, s \in Shards :
        ActivateMigrate(p, s)
    \/ \E p \in Principals, s \in Shards :
        FinishMigrate(p, s)

=============================================================================
