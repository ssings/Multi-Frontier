------------------------------- MODULE MWrite -------------------------------

EXTENDS MAuth

VARIABLES
    tsoVector, versionVector, sessionWriteTs,
    pendingWrites, lastWrite

WriteVars ==
    <<tsoVector, versionVector, sessionWriteTs,
      pendingWrites, lastWrite>>

PendingWriteT ==
    [ active     : BOOLEAN,
      user       : Users,
      collection : Collections,
      tso        : VersionT ]


WriteRecordT ==
    [ kind       : {"None", "Some"},
      phase      : {"None", "AssignTSO", "WALCommit"},
      user       : Users,
      collection : Collections,
      shard      : Shards,
      version    : VersionT,
      authorized : BOOLEAN ]


WriteTypeInvariant ==
    /\ tsoVector \in [Shards -> VersionT]
    /\ versionVector \in [Shards -> VersionT]
    /\ sessionWriteTs
        \in [Users -> [Collections -> VersionT]]
    /\ pendingWrites
        \in [Shards -> PendingWriteT]
    /\ lastWrite \in WriteRecordT
    \* WAL committed version can never exceed assigned TSO.
    /\ \A s \in Shards :
        versionVector[s] <= tsoVector[s]


InitWrite ==
    /\ tsoVector =
        [s \in Shards |-> 0]
    /\ versionVector =
        [s \in Shards |-> 0]
    /\ sessionWriteTs =
        [u \in Users |->
            [c \in Collections |-> 0]]
    /\ pendingWrites =
        [s \in Shards |->
            [ active     |-> FALSE,
              user       |-> CHOOSE u \in Users : TRUE,
              collection |-> CHOOSE c \in Collections : TRUE,
              tso        |-> 0 ]]
    /\ lastWrite =
        [ kind       |-> "None",
          phase      |-> "None",
          user       |-> CHOOSE u \in Users : TRUE,
          collection |-> CHOOSE c \in Collections : TRUE,
          shard      |-> CHOOSE s \in Shards : TRUE,
          version    |-> 0,
          authorized |-> FALSE ]

AssignWriteTSO(user, c) ==
    LET s == VChannelFor(c) IN
    LET newTs == tsoVector[s] + 1 IN
    /\ user \in Users
    /\ c \in Collections
    /\ CanWrite(user, c)
    /\ ~pendingWrites[s].active
    /\ tsoVector[s] = versionVector[s]
    /\ tsoVector[s] < MaxVersion
    /\ tsoVector' =
        [tsoVector EXCEPT
            ![s] = newTs]
    /\ pendingWrites' =
        [pendingWrites EXCEPT
            ![s] =
                [ active     |-> TRUE,
                  user       |-> user,
                  collection |-> c,
                  tso        |-> newTs ]]
    /\ UNCHANGED
        <<versionVector,
          sessionWriteTs>>
    /\ lastWrite' =
        [ kind       |-> "Some",
          phase      |-> "AssignTSO",
          user       |-> user,
          collection |-> c,
          shard      |-> s,
          version    |-> newTs,
          authorized |-> TRUE ]

CommitWAL(s) ==
    LET pw == pendingWrites[s] IN
    /\ s \in Shards
    /\ pw.active
    /\ pw.tso = tsoVector[s]
    /\ versionVector[s] < pw.tso
    /\ versionVector' =
        [versionVector EXCEPT
            ![s] = pw.tso]
    /\ sessionWriteTs' =
        [sessionWriteTs EXCEPT
            ![pw.user][pw.collection] = pw.tso]
    /\ pendingWrites' =
        [pendingWrites EXCEPT
            ![s] =
                [ active     |-> FALSE,
                  user       |-> pw.user,
                  collection |-> pw.collection,
                  tso        |-> pw.tso ]]
    /\ UNCHANGED tsoVector
    /\ lastWrite' =
        [ kind       |-> "Some",
          phase      |-> "WALCommit",
          user       |-> pw.user,
          collection |-> pw.collection,
          shard      |-> s,
          version    |-> pw.tso,
          authorized |-> TRUE ]

NextWrite ==
    \/ \E u \in Users, c \in Collections :
        AssignWriteTSO(u, c)

    \/ \E s \in Shards :
        CommitWAL(s)

WriteSpec ==
    /\ CoreAssumption
    /\ AuthAssumption
    /\ InitAuth
    /\ InitWrite
    /\ [][NextWrite]_WriteVars

LastWriteAuthorized ==
    lastWrite.kind = "None"
    \/
    /\ lastWrite.authorized = TRUE
    /\ CanWrite(
        lastWrite.user,
        lastWrite.collection)


WALNotAheadOfTSO ==
    \A s \in Shards :
        versionVector[s] <= tsoVector[s]


IdleWriteFullyCommitted ==
    \A s \in Shards :
        ~pendingWrites[s].active
        =>
        versionVector[s] = tsoVector[s]


PendingWriteValid ==
    \A s \in Shards :
        pendingWrites[s].active
        =>
        /\ versionVector[s] < pendingWrites[s].tso
        /\ pendingWrites[s].tso = tsoVector[s]

=============================================================================
