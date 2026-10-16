# Cassandra Official Documentation Materials Snapshot

Acquisition time: 2026-08-03T22:31:56+08:00
Source restriction: Apache Cassandra official documentation.

## Architecture Overview

Source: https://cassandra.apache.org/doc/latest/cassandra/architecture/overview.html

Overview | Apache Cassandra Documentation
Cassandra Documentation
Version:
5.0
website
7.0
6.0
5.0.8
5.0
4.1
4.0
3.11
You are viewing the documentation for a prerelease version.
View Latest
Edit
Overview
Apache Cassandra is an open-source, distributed NoSQL database. It implements a partitioned wide-column storage model with eventually consistent semantics.
Cassandra was initially designed at
Facebook
using a staged event-driven architecture (
SEDA
). This initial design implemented a combination of Amazon’s
Dynamo
distributed storage and replication techniques and Google’s
Bigtable
data and storage engine model. Dynamo and Bigtable were both developed to meet emerging requirements for scalable, reliable and highly available storage systems, but each had areas that could be improved.
Apache Cassandra was designed as a best-in-class combination of both systems to meet emerging large scale, both in data footprint and query volume, storage requirements. As applications began to require full global replication and always available low-latency reads and writes, a new kind of database model was required to meet these new requirements. Relational database systems at that time struggled to meet the requirements.
Apache Cassandra was designed to meet these challenges with the following design objectives in mind:
Full multi-primary database replication
Global availability at low latency
Scaling out on commodity hardware
Linear throughput increase with each additional processor
Online load balancing and cluster growth
Partitioned key-oriented queries
Flexible schema
Features
Cassandra provides the Cassandra Query Language (
CQL
), an SQL-like language, to create, modify, and delete database schema, as well as access data. CQL allows users to organize data within a cluster of Cassandra nodes using:
Keyspace: Specifies the replication strategy for a dataset across different datacenters. Replication refers to the number of copies stored within a cluster. Keyspaces serve as containers for tables.
Table: Tables are composed of rows and columns. Columns define the typed schema for a single datum in a table. Tables are partitioned based on the columns provided in the partition key. Cassandra tables can flexibly add new columns to tables with zero downtime.
Partition: Defines the mandatory part of the primary key all rows in Cassandra must have to identify the node in a cluster where the row is stored. All performant queries supply the partition key in the query.
Row: Contains a collection of columns identified by a unique primary key made up of the partition key and optionally additional clustering keys.
Column: A single datum with a type which belongs to a row.
CQL supports numerous advanced features over a partitioned dataset such as:
Collection types including sets, maps, and lists
User-defined types, tuples, functions and aggregates
Storage-attached indexing (SAI) for secondary indexes
Local secondary indexes (2i)
User-defined types, functions and aggregates
Single-partition lightweight transactions with atomic compare and set semantics
(Experimental) materialized views
Cassandra explicitly chooses not to implement operations that require cross-partition coordination as they are typically slow and hard to provide highly available global semantics. For example, Cassandra does not support:
Cross-partition transactions
Distributed joins
Foreign keys or referential integrity.
Operating
Apache Cassandra configuration settings are configured in the
cassandra.yaml
file that can be edited by hand or with the aid of configuration management tools. Some settings can be manipulated live using an online interface, but others require a restart of the database to take effect.
Cassandra provides tools for managing a cluster. The
nodetool
command interacts with Cassandra’s live control interface, allowing runtime manipulation of many settings from
cassandra.yaml
. The
auditlogviewer
is used to view the audit logs. The
fqltool
is used to view, replay and compare full query logs.
In addition, Cassandra supports out of the box atomic snapshot functionality, which presents a point in time (PIT) snapshot of Cassandra’s data for easy integration with many backup tools. Cassandra also supports incremental backups where data can be backed up as it is written.
Foundation
Events
License
Thanks
Security
Privacy
Sponsorship
© 2009-
The Apache Software Foundation
under the terms of the Apache License 2.0. Apache, the Apache feather logo, Apache Cassandra, Cassandra, and the Cassandra logo, are either registered trademarks or trademarks of The Apache Software Foundation.

## Dynamo and Tunable Consistency

Source: https://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html

Dynamo | Apache Cassandra Documentation
Cassandra Documentation
Version:
5.0
website
7.0
6.0
5.0.8
5.0
4.1
4.0
3.11
You are viewing the documentation for a prerelease version.
View Latest
Edit
Dynamo
Apache Cassandra relies on a number of techniques from Amazon’s
Dynamo
distributed storage key-value system. Each node in the Dynamo system has three main components:
Request coordination over a partitioned dataset
Ring membership and failure detection
A local persistence (storage) engine
Cassandra primarily draws from the first two clustering components, while using a storage engine based on a Log Structured Merge Tree (
LSM
). In particular, Cassandra relies on Dynamo style:
Dataset partitioning using consistent hashing
Multi-master replication using versioned data and tunable consistency
Distributed cluster membership and failure detection via a gossip protocol
Incremental scale-out on commodity hardware
Cassandra was designed this way to meet large-scale (PiB+) business-critical storage requirements. In particular, as applications demanded full global replication of petabyte-scale datasets along with always available low-latency reads and writes, it became imperative to design a new kind of database model as the relational database systems of the time struggled to meet the new requirements of global-scale applications.
Dataset Partitioning: Consistent Hashing
Cassandra achieves horizontal scalability by
partitioning
all data stored in the system using a hash function. Each partition is replicated to multiple physical nodes, often across failure domains such as racks and even datacenters. As every replica can independently accept mutations to every key that it owns, every key must be versioned. Unlike in the original Dynamo paper where deterministic versions and vector clocks were used to reconcile concurrent updates to a key, Cassandra uses a simpler last-write-wins model where every mutation is timestamped (including deletes) and then the latest version of data is the "winning" value. Formally speaking, Cassandra uses a Last-Write-Wins Element-Set conflict-free replicated data type for each CQL row, or
LWW-Element-Set CRDT
, to resolve conflicting mutations on replica sets.
Consistent Hashing using a Token Ring
Cassandra partitions data over storage nodes using a special form of hashing called
consistent hashing
. In naive data hashing, you typically allocate keys to buckets by taking a hash of the key modulo the number of buckets. For example, if you want to distribute data to 100 nodes using naive hashing you might assign every node to a bucket between 0 and 100, hash the input key modulo 100, and store the data on the associated bucket. In this naive scheme, however, adding a single node might invalidate almost all of the mappings.
Cassandra instead maps every node to one or more tokens on a continuous hash ring, and defines ownership by hashing a key onto the ring and then "walking" the ring in one direction, similar to the
Chord
algorithm. The main difference of consistent hashing to naive data hashing is that when the number of nodes (buckets) to hash into changes, consistent hashing only has to move a small fraction of the keys.
For example, if we have an eight node cluster with evenly spaced tokens, and a replication factor (RF) of 3, then to find the owning nodes for a key we first hash that key to generate a token (which is just the hash of the key), and then we "walk" the ring in a clockwise fashion until we encounter three distinct nodes, at which point we have found all the replicas of that key. This example of an eight node cluster with gRF=3 can be visualized as follows:
You can see that in a Dynamo-like system, ranges of keys, also known as
token ranges
, map to the same physical set of nodes. In this example, all keys that fall in the token range excluding token 1 and including token 2 (grange(t1, t2]) are stored on nodes 2, 3 and 4.
Multiple Tokens per Physical Node (vnodes)
Simple single-token consistent hashing works well if you have many physical nodes to spread data over, but with evenly spaced tokens and a small number of physical nodes, incremental scaling (adding just a few nodes of capacity) is difficult because there are no token selections for new nodes that can leave the ring balanced. Cassandra seeks to avoid token imbalance because uneven token ranges lead to uneven request load. For example, in the previous example there is no way to add a ninth token without causing imbalance; instead we would have to insert
8
tokens in the midpoints of the existing ranges.
The Dynamo paper advocates for the use of "virtual nodes" to solve this imbalance problem. Virtual nodes solve the problem by assigning multiple tokens in the token ring to each physical node. By allowing a single physical node to take multiple positions in the ring, we can make small clusters look larger and therefore even with a single physical node addition we can make it look like we added many more nodes, effectively taking many smaller pieces of data from more ring neighbors when we add even a single node.
Cassandra introduces some nomenclature to handle these concepts:
Token
: A single position on the Dynamo-style hash ring.
Endpoint
: A single physical IP and port on the network.
Host ID
: A unique identifier for a single "physical" node, usually present at one gEndpoint and containing one or more gTokens.
Virtual Node
(or
vnode
): A gToken on the hash ring owned by the same physical node, one with the same gHost ID.
The mapping of
Tokens
to
Endpoints
gives rise to the
Token Map
where Cassandra keeps track of what ring positions map to which physical endpoints. For example, in the following figure we can represent an eight node cluster using only four physical nodes by assigning two tokens to every node:
Multiple tokens per physical node provide the following benefits:
When a new node is added it accepts approximately equal amounts of data from other nodes in the ring, resulting in equal distribution of data across the cluster.
When a node is decommissioned, it loses data roughly equally to other members of the ring, again keeping equal distribution of data across the cluster.
If a node becomes unavailable, query load (especially token-aware query load), is evenly distributed across many other nodes.
Multiple tokens, however, can also have disadvantages:
Every token introduces up to
2 * (RF - 1)
additional neighbors on the token ring, which means that there are more combinations of node failures where we lose availability for a portion of the token ring. The more tokens you have,
the higher the probability of an outage
.
Cluster-wide maintenance operations are often slowed. For example, as the number of tokens per node is increased, the number of discrete repair operations the cluster must do also increases.
Performance of operations that span token ranges could be affected.
Note that in Cassandra
2.x
, the only token allocation algorithm available was picking random tokens, which meant that to keep balance the default number of tokens per node had to be quite high, at
256
. This had the effect of coupling many physical endpoints together, increasing the risk of unavailability. That is why in
3.x +
a new deterministic token allocator was added which intelligently picks tokens such that the ring is optimally balanced while requiring a much lower number of tokens per physical node.
Multi-master Replication: Versioned Data and Tunable Consistency
Cassandra replicates every partition of data to many nodes across the cluster to maintain high availability and durability. When a mutation occurs, the coordinator hashes the partition key to determine the token range the data belongs to and then replicates the mutation to the replicas of that data according to the
Replication Strategy
.
All replication strategies have the notion of a
replication factor
(
RF
), which indicates to Cassandra how many copies of the partition should exist. For example with a
RF=3
keyspace, the data will be written to three distinct
replicas
. Replicas are always chosen such that they are distinct physical nodes which is achieved by skipping virtual nodes if needed. Replication strategies may also choose to skip nodes present in the same failure domain such as racks or datacenters so that Cassandra clusters can tolerate failures of whole racks and even datacenters of nodes.
Replication Strategy
Cassandra supports pluggable
replication strategies
, which determine which physical nodes act as replicas for a given token range. Every keyspace of data has its own replication strategy. All production deployments should use the
NetworkTopologyStrategy
while the
SimpleStrategy
replication strategy is useful only for testing clusters where you do not yet know the datacenter layout of the cluster.
NetworkTopologyStrategy
NetworkTopologyStrategy
requires a specified replication factor for each datacenter in the cluster. Even if your cluster only uses a single datacenter,
NetworkTopologyStrategy
is recommended over
SimpleStrategy
to make it easier to add new physical or virtual datacenters to the cluster later, if required.
In addition to allowing the replication factor to be specified individually by datacenter,
NetworkTopologyStrategy
also attempts to choose replicas within a datacenter from different racks as specified by the
Snitch
. If the number of racks is greater than or equal to the replication factor for the datacenter, each replica is guaranteed to be chosen from a different rack. Otherwise, each rack will hold at least one replica, but some racks may hold more than one. Note that this rack-aware behavior has some potentially
surprising implications
. For example, if there are not an even number of nodes in each rack, the data load on the smallest rack may be much higher. Similarly, if a single node is bootstrapped into a brand new rack, it will be considered a replica for the entire ring. For this reason, many operators choose to configure all nodes in a single availability zone or similar failure domain as a single "rack".
SimpleStrategy
SimpleStrategy
allows a single integer
replication_factor
to be defined. This determines the number of nodes that should contain a copy of each row. For example, if
replication_factor
is 3, then three different nodes should store a copy of each row.
SimpleStrategy
treats all nodes identically, ignoring any configured datacenters or racks. To determine the replicas for a token range, Cassandra iterates through the tokens in the ring, starting with the token range of interest. For each token, it checks whether the owning node has been added to the set of replicas, and if it has not, it is added to the set. This process continues until
replication_factor
distinct nodes have been added to the set of replicas.
Transient Replication
Transient replication is an experimental feature in Cassandra 4.0 not present in the original Dynamo paper. This feature allows configuration of a subset of replicas to replicate only data that hasn’t been incrementally repaired. This configuration decouples data redundancy from availability. For instance, if you have a keyspace replicated at RF=3, and alter it to RF=5 with two transient replicas, you go from tolerating one failed replica to tolerating two, without corresponding increase in storage usage. Now, three nodes will replicate all the data for a given token range, and the other two will only replicate data that hasn’t been incrementally repaired.
To use transient replication, first enable the option in
cassandra.yaml
. Once enabled, both
SimpleStrategy
and
NetworkTopologyStrategy
can be configured to transiently replicate data. Configure it by specifying replication factor as
<total_replicas>/<transient_replicas
Both
SimpleStrategy
and
NetworkTopologyStrategy
support configuring transient replication.
Transiently replicated keyspaces only support tables created with
read_repair
set to
NONE
; monotonic reads are not currently supported. You also can’t use
LWT
, logged batches, or counters in 4.0. You will possibly never be able to use materialized views with transiently replicated keyspaces and probably never be able to use secondary indices with them.
Transient replication is an experimental feature that is not ready for production use. The expected audience is experienced users of Cassandra capable of fully validating a deployment of their particular application. That means you have the experience to check that operations like reads, writes, decommission, remove, rebuild, repair, and replace all work with your queries, data, configuration, operational practices, and availability requirements.
Anticipated additional features in
4.next
are support for monotonic reads with transient replication, as well as LWT, logged batches, and counters.
Data Versioning
Cassandra uses mutation timestamp versioning to guarantee eventual consistency of data. Specifically all mutations that enter the system do so with a timestamp provided either from a client clock or, absent a client-provided timestamp, from the coordinator node’s clock. Updates resolve according to the conflict resolution rule of last write wins. Cassandra’s correctness does depend on these clocks, so make sure a proper time synchronization process is running such as NTP.
Cassandra applies separate mutation timestamps to every column of every row within a CQL partition. Rows are guaranteed to be unique by primary key, and each column in a row resolves concurrent mutations according to last-write-wins conflict resolution. This means that updates to different primary keys within a partition can actually resolve without conflict! Furthermore the CQL collection types such as maps and sets use this same conflict-free mechanism, meaning that concurrent updates to maps and sets are guaranteed to resolve as well.
Replica Synchronization
As replicas in Cassandra can accept mutations independently, it is possible for some replicas to have newer data than others. Cassandra has many best-effort techniques to drive convergence of replicas including
Replica read repair <read-repair>
in the read path and
Hinted handoff <hints>
in the write path.
These techniques are only best-effort, however, and to guarantee eventual consistency Cassandra implements
anti-entropy repair <repair>
where replicas calculate hierarchical hash trees over their datasets called
Merkle trees
that can then be compared across replicas to identify mismatched data. Like the original Dynamo paper Cassandra supports full repairs where replicas hash their entire dataset, create Merkle trees, send them to each other and sync any ranges that don’t match.
Unlike the original Dynamo paper, Cassandra also implements sub-range repair and incremental repair. Sub-range repair allows Cassandra to increase the resolution of the hash trees (potentially down to the single partition level) by creating a larger number of trees that span only a portion of the data range. Incremental repair allows Cassandra to only repair the partitions that have changed since the last repair.
Tunable Consistency
Cassandra supports a per-operation tradeoff between consistency and availability through
Consistency Levels
. Cassandra’s consistency levels are a version of Dynamo’s
R + W > N
consistency mechanism where operators could configure the number of nodes that must participate in reads (
R
) and writes (
W
) to be larger than the replication factor (
N
). In Cassandra, you instead choose from a menu of common consistency levels which allow the operator to pick
R
and
W
behavior without knowing the replication factor. Generally writes will be visible to subsequent reads when the read consistency level contains enough nodes to guarantee a quorum intersection with the write consistency level.
The following consistency levels are available:
ONE
Only a single replica must respond.
TWO
Two replicas must respond.
THREE
Three replicas must respond.
QUORUM
A majority (n/2 + 1) of the replicas must respond.
ALL
All of the replicas must respond.
LOCAL_QUORUM
A majority of the replicas in the local datacenter (whichever datacenter the coordinator is in) must respond.
EACH_QUORUM
A majority of the replicas in each datacenter must respond.
LOCAL_ONE
Only a single replica must respond. In a multi-datacenter cluster, this also guarantees that read requests are not sent to replicas in a remote datacenter.
ANY
A single replica may respond, or the coordinator may store a hint. If a hint is stored, the coordinator will later attempt to replay the hint and deliver the mutation to the replicas. This consistency level is only accepted for write operations.
Write operations
are always sent to all replicas
, regardless of consistency level. The consistency level simply controls how many responses the coordinator waits for before responding to the client.
For read operations, the coordinator generally only issues read commands to enough replicas to satisfy the consistency level. The one exception to this is when speculative retry may issue a redundant read request to an extra replica if the original replicas have not responded within a specified time window.
Picking Consistency Levels
It is common to pick read and write consistency levels such that the replica sets overlap, resulting in all acknowledged writes being visible to subsequent reads. This is typically expressed in the same terms Dynamo does, in that
W + R > RF
, where
W
is the write consistency level,
R
is the read consistency level, and
RF
is the replication factor. For example, if
RF = 3
, a
QUORUM
request will require responses from at least
2/3
replicas. If
QUORUM
is used for both writes and reads, at least one of the replicas is guaranteed to participate in
both
the write and the read request, which in turn guarantees that the quorums will overlap and the write will be visible to the read.
In a multi-datacenter environment,
LOCAL_QUORUM
can be used to provide a weaker but still useful guarantee: reads are guaranteed to see the latest write from within the same datacenter. This is often sufficient as clients homed to a single datacenter will read their own writes.
If this type of strong consistency isn’t required, lower consistency levels like
LOCAL_ONE
or
ONE
may be used to improve throughput, latency, and availability. With replication spanning multiple datacenters,
LOCAL_ONE
is typically less available than
ONE
but is faster as a rule. Indeed
ONE
will succeed if a single replica is available in any datacenter.
Distributed Cluster Membership and Failure Detection
The replication protocols and dataset partitioning rely on knowing which nodes are alive and dead in the cluster so that write and read operations can be optimally routed. In Cassandra liveness information is shared in a distributed fashion through a failure detection mechanism based on a gossip protocol.
Gossip
Gossip is how Cassandra propagates basic cluster bootstrapping information such as endpoint membership and internode network protocol versions. In Cassandra’s gossip system, nodes exchange state information not only about themselves but also about other nodes they know about. This information is versioned with a vector clock of
(generation, version)
tuples, where the generation is a monotonic timestamp and version is a logical clock that increments roughly every second. These logical clocks allow Cassandra gossip to ignore old versions of cluster state just by inspecting the logical clocks presented with gossip messages.
Every node in the Cassandra cluster runs the gossip task independently and periodically. Every second, every node in the cluster:
Updates the local node’s heartbeat state (the version) and constructs the node’s local view of the cluster gossip endpoint state.
Picks a random other node in the cluster to exchange gossip endpoint state with.
Probabilistically attempts to gossip with any unreachable nodes (if one exists)
Gossips with a seed node if that didn’t happen in step 2.
When an operator first bootstraps a Cassandra cluster, they designate certain nodes as seed nodes. Any node can be a seed node, and the only difference between seed and non-seed nodes is that seed nodes are allowed to bootstrap into the ring without seeing any other seed nodes. Furthermore, once a cluster is bootstrapped, seed nodes become hotspots for gossip due to step 4 above.
As non-seed nodes must be able to contact at least one seed node in order to bootstrap into the cluster, it is common to include multiple seed nodes, often one for each rack or datacenter. Seed nodes are often chosen using existing off-the-shelf service discovery mechanisms.
Nodes do not have to agree on the seed nodes, and indeed once a cluster is bootstrapped, newly launched nodes can be configured to use any existing nodes as seeds. The only advantage to picking the same nodes as seeds is that it increases their usefulness as gossip hotspots.
Currently, gossip also propagates token metadata and schema
version
information. This information forms the control plane for scheduling data movements and schema pulls. For example, if a node sees a mismatch in schema version in gossip state, it will schedule a schema sync task with the other nodes. As token information propagates via gossip it is also the control plane for teaching nodes which endpoints own what data.
Ring Membership and Failure Detection
Gossip forms the basis of ring membership, but the
failure detector
ultimately makes decisions about if nodes are
UP
or
DOWN
. Every node in Cassandra runs a variant of the
Phi Accrual Failure Detector
, in which every node is constantly making an independent decision of if their peer nodes are available or not. This decision is primarily based on received heartbeat state. For example, if a node does not see an increasing heartbeat from a node for a certain amount of time, the failure detector "convicts" that node, at which point Cassandra will stop routing reads to it (writes will typically be written to hints). If/when the node starts heartbeating again, Cassandra will try to reach out and connect, and if it can open communication channels it will mark that node as available.
UP
and
DOWN
state are local node decisions and are not propagated with gossip. Heartbeat state is propagated with gossip, but nodes will not consider each other as
UP
until they can successfully message each other over an actual network channel.
Cassandra will never remove a node from gossip state without explicit instruction from an operator via a decommission operation or a new node bootstrapping with a
replace_address_first_boot
option. This choice is intentional to allow Cassandra nodes to temporarily fail without causing data to needlessly re-balance. This also helps to prevent simultaneous range movements, where multiple replicas of a token range are moving at the same time, which can violate monotonic consistency and can even cause data loss.
Incremental Scale-out on Commodity Hardware
Cassandra scales-out to meet the requirements of growth in data size and request rates. Scaling-out means adding additional nodes to the ring, and every additional node brings linear improvements in compute and storage. In contrast, scaling-up implies adding more capacity to the existing database nodes. Cassandra is also capable of scale-up, and in certain environments it may be preferable depending on the deployment. Cassandra gives operators the flexibility to choose either scale-out or scale-up.
One key aspect of Dynamo that Cassandra follows is to attempt to run on commodity hardware, and many engineering choices are made under this assumption. For example, Cassandra assumes nodes can fail at any time, auto-tunes to make the best use of CPU and memory resources available and makes heavy use of advanced compression and caching techniques to get the most storage out of limited memory and storage capabilities.
Simple Query Model
Cassandra, like Dynamo, chooses not to provide cross-partition transactions that are common in SQL Relational Database Management Systems (RDBMS). This both gives the programmer a simpler read and write API, and allows Cassandra to more easily scale horizontally since multi-partition transactions spanning multiple nodes are notoriously difficult to implement and typically very latent.
Instead, Cassandra chooses to offer fast, consistent, latency at any scale for single partition operations, allowing retrieval of entire partitions or only subsets of partitions based on primary key filters. Furthermore, Cassandra does support single partition compare and swap functionality via the lightweight transaction CQL API.
Simple Interface for Storing Records
Cassandra, in a slight departure from Dynamo, chooses a storage interface that is more sophisticated than "simple key-value" stores but significantly less complex than SQL relational data models. Cassandra presents a wide-column store interface, where partitions of data contain multiple rows, each of which contains a flexible set of individually typed columns. Every row is uniquely identified by the partition key and one or more clustering keys, and every row can have as many columns as needed.
This allows users to flexibly add new columns to existing datasets as new requirements surface. Schema changes involve only metadata changes and run fully concurrently with live workloads. Therefore, users can safely add columns to existing Cassandra databases while remaining confident that query performance will not degrade.
Foundation
Events
License
Thanks
Security
Privacy
Sponsorship
© 2009-
The Apache Software Foundation
under the terms of the Apache License 2.0. Apache, the Apache feather logo, Apache Cassandra, Cassandra, and the Cassandra logo, are either registered trademarks or trademarks of The Apache Software Foundation.

## Storage Engine and Write Path

Source: https://cassandra.apache.org/doc/latest/cassandra/architecture/storage-engine.html

Storage Engine | Apache Cassandra Documentation
Cassandra Documentation
Version:
5.0
website
7.0
6.0
5.0.8
5.0
4.1
4.0
3.11
You are viewing the documentation for a prerelease version.
View Latest
Edit
Storage Engine
The Cassandra storage engine is optimized for high performance, write-oriented workloads. The architecture is based on Log Structured Merge (LSM) trees, which utilize an append-only approach instead of the traditional relational database design with B-trees. This creates a write path free of read lookups and bottlenecks.
While the write path is highly optimized, it comes with tradeoffs in terms of read performance and write amplification. To enhance read operations, Cassandra uses Bloom filters when accessing data from stables. Bloom filters are remarkably efficient, leading to generally well-balanced performance for both reads and writes.
Compaction is a necessary background activity required by the ‘merge’ phase of Log Structured Merge trees. Compaction creates write amplification when several small SSTables on disk are read, merged, updates and deletes processed, and a new SSTable is re-written. Every write of data in Cassandra is re-written multiple times, known as write amplification, and this adds background I/O to the database workload.
The core storage engine consists of memtables for in-memory data and immutable SSTables (Sorted String Tables) on disk. Data in SSTables is stored sorted to enable efficient merge sort during compaction. Additionally, a write-ahead log (WAL), referred to as the commit log, ensures resiliency for crash and transaction recovery.
The sequence of the steps in the write path:
Logging data in the commit log
Writing data to the memtable
Flushing data from the memtable
Storing data on disk in SSTables
Logging writes to commit logs
When a write operation takes place, Cassandra records the data in a local append-only
cassandra.apache.org/
/glossary.html#commit-log[commit log] on disk. This action provides
configurable durability
by logging every write made to a Cassandra node. If an unexpected shutdown occurs, the commit log provides permanent durable writes of the data. On startup, any mutations in the commit log will be applied to
cassandra.apache.org/
/glossary.html#memtable[memtables]. The commit log is shared among tables.
All mutations are write-optimized on storage in commit log segments, reducing the number of seeks needed to write to disk. Commit log segments are limited by the
commitlog_segment_size
option. Once the defined size is reached, a new commit log segment is created. Commit log segments can be archived, deleted, or recycled once all the data is flushed to
SSTables
. Commit log segments are truncated when Cassandra has written data older than a certain point to the SSTables. Running
nodetool drain
before stopping Cassandra will write everything in the memtables to SSTables and remove the need to sync with the commit logs on startup.
commitlog_segment_size
: The default size is 32MiB, which is almost always fine, but if you are archiving commitlog segments (see commitlog_archiving.properties), then you probably want a finer granularity of archiving; 8 or 16 MiB is reasonable.
commitlog_segment_size
also determines the default value of
max_mutation_size
in
cassandra.yaml
. By default,
max_mutation_size
is a half the size of
commitlog_segment_size
.
If
max_mutation_size
is set explicitly then
commitlog_segment_size
must be set to at least twice the size of
max_mutation_size
.
commitlog_sync
: may be either
periodic
or
batch
.
batch
: In batch mode, Cassandra won’t acknowledge writes until the commit log has been fsynced to disk.
periodic
: In periodic mode, writes are immediately acknowledged, and the commit log is simply synced every "commitlog_sync_period" milliseconds.
commitlog_sync_period
: Time to wait between "periodic" fsyncs
Default Value:
10000ms
Default Value:
periodic
In the event of an unexpected shutdown, Cassandra can lose up to the sync period or more if the sync is delayed. If using
batch
mode, it is recommended to store commit logs in a separate, dedicated device.
commitlog_directory
: This option is commented out by default. When running on magnetic HDD, this should be a separate spindle than the data directories. If not set, the default directory is
$CASSANDRA_HOME/data/commitlog
.
Default Value:
/var/lib/cassandra/commitlog
commitlog_compression
: Compression to apply to the commitlog. If omitted, the commit log will be written uncompressed. LZ4, Snappy,Deflate and Zstd compressors are supported.
Default Value:
# - class_name: LZ4Compressor # parameters:
commitlog_total_space
: Total space to use for commit logs on disk. This option is commented out by default. If space gets above this value, Cassandra will flush every dirty table in the oldest segment and remove it. So a small total commit log space will tend to cause more flush activity on less-active tables. The default value is the smallest between 8192 and 1/4 of the total space of the commitlog volume.
Default Value:
8192MiB
Memtables
When Cassandra accepts new write requests, it saves the data in two places: an in-memory write-back cache called a memtable and the CommitLog. The memtable buffers writes and allows serving reads without accessing the disk, while the CommitLog ensures durability by appending new mutations. Typically, there is one active memtable per table, acting as a cache for data partitions that Cassandra accesses by key.
Depending on the
memtable_allocation_type
, memtables can be stored entirely on-heap or partially off-heap. If Cassandra crashes before flushing the memtable, it can restore acknowledged writes by replaying the commitLog.
The memtable stores writes in sorted order until reaching a configurable limit. When the limit is reached, memtables are flushed onto disk and become immutable
SSTables
. Flushing can be triggered in several ways:
The memory usage of the memtables exceeds the configured threshold (see
memtable_cleanup_threshold
)
The
commit log
approaches its maximum size, and forces memtable flushes in order to allow commit log segments to be freed.
When a triggering event occurs, the memtable is put in a queue that is flushed to disk. Flushing writes the data to disk, in the memtable-sorted order. A partition index is also created on the disk that maps the tokens to a location on disk.
The queue can be configured with either the
memtable_heap_space
or
memtable_offheap_space
setting in the
cassandra.yaml
file. If the data to be flushed exceeds the
memtable_cleanup_threshold
, Cassandra blocks writes until the next flush succeeds. You can manually flush a table using
nodetool flush
or
nodetool drain
(flushes memtables without listening for connections to other nodes). To reduce the commit log replay time, the recommended best practice is to flush the memtable before you restart the nodes. If a node stops working, replaying the commit log restores writes to the memtable that were there before it stopped.
Data in the commit log is purged after its corresponding data in the memtable is flushed to an SSTable on disk.
SSTables
SSTables
are the immutable data files that Cassandra uses for persisting data on disk. SSTables are maintained per table. SSTables are immutable, and never written to again after the memtable is flushed. Thus, a partition is typically stored across multiple SSTable files, as data is added or modified.
Each SSTable consists of multiple components stored in separate files:
Data.db
The actual data, i.e. the contents of rows.
Partitions.db
The partition index file maps unique prefixes of decorated partition keys to data file locations, or, in the case of wide partitions indexed in the row index file, to locations in the row index file.
Rows.db
The row index file only contains entries for partitions that contain more than one row and are bigger than one index block. For all such partitions, it stores a copy of the partition key, a partition header, and an index of row block separators, which map each row key into the first block where any content with equal or higher row key can be found.
Index.db
An index from partition keys to positions in the
Data.db
file. For wide partitions, this may also include an index to rows within a partition.
Summary.db
A sampling of (by default) every 128th entry in the
Index.db
file.
Filter.db
A Bloom Filter of the partition keys in the SSTable.
CompressionInfo.db
Metadata about the offsets and lengths of compression chunks in the
Data.db
file.
Statistics.db
Stores metadata about the SSTable, including information about timestamps, tombstones, clustering keys, compaction, repair, compression, TTLs, and more.
Digest.crc32
A CRC-32 digest of the
Data.db
file.
TOC.txt
A plain text list of the component files for the SSTable.
SAI*.db
Index information for Storage-Attached indexes. Only present if SAI is enabled for the table.
Note that the
Index.db
file type is replaced by
Partitions.db
and
Rows.db
. This change is a consequence of the inclusion of Big Trie indexes in Cassandra
CEP-25
.
Within the
Data.db
file, rows are organized by partition. These partitions are sorted in token order (i.e. by a hash of the partition key when the default partitioner,
Murmur3Partition
, is used). Within a partition, rows are stored in the order of their clustering keys.
SSTables can be optionally compressed using block-based compression.
As SSTables are flushed to disk from
memtables
or are streamed from other nodes, Cassandra triggers compactions which combine multiple SSTables into one. Once the new SSTable has been written, the old SSTables can be removed.
SSTable Versions
From
BigFormat#BigVersion
.
The version numbers, to date are:
Version 0
b (0.7.0): added version to SSTable filenames
c (0.7.0): bloom filter component computes hashes over raw key bytes instead of strings
d (0.7.0): row size in data component becomes a long instead of int
e (0.7.0): stores undecorated keys in data and index components
f (0.7.0): switched bloom filter implementations in data component
g (0.8): tracks flushed-at context in metadata component
Version 1
h (1.0): tracks max client timestamp in metadata component
hb (1.0.3): records compression ration in metadata component
hc (1.0.4): records partitioner in metadata component
hd (1.0.10): includes row tombstones in maxtimestamp
he (1.1.3): includes ancestors generation in metadata component
hf (1.1.6): marker that replay position corresponds to 1.1.5+ millis-based id (see CASSANDRA-4782)
ia (1.2.0):
column indexes are promoted to the index file
records estimated histogram of deletion times in tombstones
bloom filter (keys and columns) upgraded to Murmur3
ib (1.2.1): tracks min client timestamp in metadata component
ic (1.2.5): omits per-row bloom filter of column names
Version 2
ja (2.0.0):
super columns are serialized as composites (note that there is no real format change, this is mostly a marker to know if we should expect super columns or not. We do need a major version bump however, because we should not allow streaming of super columns into this new format)
tracks max local deletiontime in SSTable metadata
records bloom_filter_fp_chance in metadata component
remove data size and column count from data file (CASSANDRA-4180)
tracks max/min column values (according to comparator)
jb (2.0.1):
switch from crc32 to adler32 for compression checksums
checksum the compressed data
ka (2.1.0):
new Statistics.db file format
index summaries can be down sampled and the sampling level is persisted
switch uncompressed checksums to adler32
tracks presence of legacy (local and remote) counter shards
la (2.2.0): new file name format
lb (2.2.7): commit log lower bound included
Version 3
ma (3.0.0):
swap bf hash order
store rows natively
mb (3.0.7, 3.7): commit log lower bound included
mc (3.0.8, 3.9): commit log intervals included
md (3.0.18, 3.11.4): corrected SSTable min/max clustering
me (3.0.25, 3.11.11): added hostId of the node from which the SSTable originated
Version 4
na (4.0-rc1): uncompressed chunks, pending repair session, isTransient, checksummed SSTable metadata file, new Bloom filter format
nb (4.0.0): originating host id
Version 5
oa (5.0): improved min/max, partition level deletion presence marker, key range (CASSANDRA-18134)
Long deletionTime to prevent TTL overflow
token space coverage
Trie-indexed Based SSTable Versions (BTI)
Cassandra 5.0 introduced new SSTable formats BTI for Trie-indexed SSTables. To use the BTI formats configure it
cassandra.yaml
like
sstable: selected_format: bti
Versions come from
BtiFormat#BtiVersion
.
For implementation docs see
BtiFormat.md
.
Version 5
da (5.0): initial version of the BTI format
Example Code
The following example is useful for finding all SSTables that do not match the "ib" SSTable version
find /var/lib/cassandra/data/ -type f | grep -v -- -ib- | grep -v "/snapshots"
Foundation
Events
License
Thanks
Security
Privacy
Sponsorship
© 2009-
The Apache Software Foundation
under the terms of the Apache License 2.0. Apache, the Apache feather logo, Apache Cassandra, Cassandra, and the Cassandra logo, are either registered trademarks or trademarks of The Apache Software Foundation.

## Guarantees and Eventual Consistency

Source: https://cassandra.apache.org/doc/latest/cassandra/architecture/guarantees.html

Guarantees | Apache Cassandra Documentation
Cassandra Documentation
Version:
5.0
website
7.0
6.0
5.0.8
5.0
4.1
4.0
3.11
You are viewing the documentation for a prerelease version.
View Latest
Edit
Guarantees
Apache Cassandra is a highly scalable and reliable database. Cassandra is used in web-based applications that serve large number of clients and the quantity of data processed is web-scale (Petabyte) large. Cassandra makes some guarantees about its scalability, availability and reliability. To fully understand the inherent limitations of a storage system in an environment in which a certain level of network partition failure is to be expected and taken into account when designing the system, it is important to first briefly introduce the CAP theorem.
What is CAP?
According to the CAP theorem, it is not possible for a distributed data store to provide more than two of the following guarantees simultaneously.
Consistency: Consistency implies that every read receives the most recent write or errors out
Availability: Availability implies that every request receives a response. It is not guaranteed that the response contains the most recent write or data.
Partition tolerance: Partition tolerance refers to the tolerance of a storage system to failure of a network partition. Even if some of the messages are dropped or delayed the system continues to operate.
The CAP theorem implies that when using a network partition, with the inherent risk of partition failure, one has to choose between consistency and availability and both cannot be guaranteed at the same time. CAP theorem is illustrated in Figure 1.
Figure 1. CAP Theorem
High availability is a priority in web-based applications and to this objective Cassandra chooses Availability and Partition Tolerance from the CAP guarantees, compromising on data Consistency to some extent.
Cassandra makes the following guarantees.
High Scalability
High Availability
Durability
Eventual Consistency of writes to a single table
Lightweight transactions with linearizable consistency
Batched writes across multiple tables are guaranteed to succeed completely or not at all
Secondary indexes are guaranteed to be consistent with their local replicas' data
High Scalability
Cassandra is a highly scalable storage system in which nodes may be added/removed as needed. Using gossip-based protocol, a unified and consistent membership list is kept at each node.
High Availability
Cassandra guarantees high availability of data by implementing a fault-tolerant storage system. Failure of a node is detected using a gossip-based protocol.
Durability
Cassandra guarantees data durability by using replicas. Replicas are multiple copies of a data stored on different nodes in a cluster. In a multi-datacenter environment the replicas may be stored on different datacenters. If one replica is lost due to unrecoverable node/datacenter failure, the data is not completely lost, as replicas are still available.
Eventual Consistency
Meeting the requirements of performance, reliability, scalability and high availability in production, Cassandra is an eventually consistent storage system. Eventually consistency implies that all updates reach all replicas eventually. Divergent versions of the same data may exist temporarily, but they are eventually reconciled to a consistent state. Eventual consistency is a tradeoff to achieve high availability, and it involves some read and write latencies.
Lightweight transactions with linearizable consistency
Data must be read and written in a sequential order. The Paxos consensus protocol is used to implement lightweight transactions. The Paxos protocol implements lightweight transactions that are able to handle concurrent operations using linearizable consistency. Linearizable consistency is sequential consistency with real-time constraints, and it ensures transaction isolation with compare-and-set (CAS) transactions. With CAS replica data is compared and data that is found to be out of date is set to the most consistent value. Reads with linearizable consistency allow reading the current state of the data, which may possibly be uncommitted, without making a new addition or update.
Batched Writes
The guarantee for batched writes across multiple tables is that they will eventually succeed, or none will. Batch data is first written to batchlog system data, and when the batch data has been successfully stored in the cluster, the batchlog data is removed. The batch is replicated to another node to ensure that the full batch completes in the event if coordinator node fails.
Secondary Indexes
A secondary index is an index on a column, and it’s used to query a table that is normally not queryable. Secondary indexes, when built, are guaranteed to be consistent with their local replicas.
Foundation
Events
License
Thanks
Security
Privacy
Sponsorship
© 2009-
The Apache Software Foundation
under the terms of the Apache License 2.0. Apache, the Apache feather logo, Apache Cassandra, Cassandra, and the Cassandra logo, are either registered trademarks or trademarks of The Apache Software Foundation.

## Authentication and Authorization

Source: https://cassandra.apache.org/doc/latest/cassandra/managing/operating/security.html

Security | Apache Cassandra Documentation
Cassandra Documentation
Version:
5.0
website
7.0
6.0
5.0.8
5.0
4.1
4.0
3.11
You are viewing the documentation for a prerelease version.
View Latest
Edit
Security
There are three main components to the security features provided by Cassandra:
TLS/SSL encryption for client and inter-node communication
Client authentication
Authorization
By default, these features are disabled as Cassandra is configured to easily find and be found by other members of a cluster. In other words, an out-of-the-box Cassandra installation presents a large attack surface for a bad actor. Enabling authentication for clients using the binary protocol is not sufficient to protect a cluster. Malicious users able to access internode communication and JMX ports can still:
Craft internode messages to insert users into authentication schema
Craft internode messages to truncate or drop schema
Use tools such as
sstableloader
to overwrite
system_auth
tables
Attach to the cluster directly to capture write traffic
Correct configuration of all three security components should negate theses vectors. Therefore, understanding Cassandra’s security features is crucial to configuring your cluster to meet your security needs.
TLS/SSL Encryption
Cassandra provides secure communication between a client machine and a database cluster and between nodes within a cluster. Enabling encryption ensures that data in flight is not compromised and is migratered securely. The options for client-to-node and node-to-node encryption are managed separately and may be configured independently.
In both cases, the JVM defaults for supported protocols and cipher suites are used when encryption is enabled. These can be overidden using the settings in
cassandra.yaml
, but this is not recommended unless there are policies in place which dictate certain settings or a need to disable vulnerable ciphers or protocols in cases where the JVM cannot be updated.
FIPS compliant settings can be configured at the JVM level and should not involve changing encryption settings in cassandra.yaml. See
the java document on FIPS
for more details.
Cassandra provides flexibility of using Java based key material or completely customizing the SSL context. You can choose any keystore format supported by Java (JKS, PKCS12 etc) as well as other standards like PEM. You can even customize the SSL context creation to use Cloud Native technologies like Kuberenetes Secrets for storing the key material or to integrate with your in-house Key Management System.
For information on generating the keystore and truststore files required with the Java supported keystores used in SSL communications, see the
java documentation on creating keystores
.
For customizing the SSL context creation you can implement
ISslContextCreationFactory
interface or extend one of its public subclasses appropriately. You can then use the
ssl_context_factory
setting for
server_encryption_options
or
client_encryption_options
sections appropriately. See
ssl-factory examples
for details. Refer to the below class diagram to understand the class hierarchy.
Using PEM based key material
You can use the in-built class
PEMBasedSSLContextFactory
as the
ssl_context_factory
setting for the PEM based key material.
You can configure this factory with either inline PEM data or with the files having the required PEM data as shown below,
Configuration: PEM keys/certs defined in-line (mind the spaces in the YAML!)
client/server_encryption_options: ssl_context_factory: class_name: org.apache.cassandra.security.PEMBasedSslContextFactory parameters: private_key: | -----BEGIN ENCRYPTED PRIVATE KEY----- OR -----BEGIN PRIVATE KEY----- <your base64 encoded private key> -----END ENCRYPTED PRIVATE KEY----- OR -----END PRIVATE KEY----- -----BEGIN CERTIFICATE----- <your base64 encoded certificate chain> -----END CERTIFICATE----- private_key_password: "<your password if the private key is encrypted with a password>" trusted_certificates: | -----BEGIN CERTIFICATE----- <your base64 encoded certificate> -----END CERTIFICATE-----
Configuration: PEM keys/certs defined in files
client/server_encryption_options: ssl_context_factory: class_name: org.apache.cassandra.security.PEMBasedSslContextFactory keystore: <file path to the keystore file in the PEM format with the private key and the certificate chain> keystore_password: "<your password if the private key is encrypted with a password>" truststore: <file path to the truststore file in the PEM format>
SSL Certificate Hot Reloading
Beginning with Cassandra 4, Cassandra supports hot reloading of SSL Certificates. If SSL/TLS support is enabled in Cassandra and you are using default file based key material, the node periodically (every 10 minutes) polls the Trust and Key Stores specified in cassandra.yaml. When the files are updated, Cassandra will reload them and use them for subsequent connections. Please note that the Trust & Key Store passwords are part of the yaml so the updated files should also use the same passwords.
If you are customizing the SSL configuration via
ssl_context_factory
setting, Cassandra polls (at the same periodic interval mentioned above) your implementation to check if the SSL certificates need to be reloaded. See the
ISslContextFactory
documentation for more details. If you are using one of the Cassandra’s in-built SSL context factory class (example: PEMBasedSslContextFactory) with file based key material, it supports the hot reloading of the SSL certificates like mentioned above.
Certificate Hot reloading may also be triggered using the
nodetool reloadssl
command. Use this if you want to Cassandra to immediately notice the changed certificates.
Inter-node Encryption
The settings for managing inter-node encryption are found in
cassandra.yaml
in the
server_encryption_options
section. To enable inter-node encryption, change the
internode_encryption
setting from its default value of
none
to one value from:
rack
,
dc
or
all
.
Client to Node Encryption
The settings for managing client to node encryption are found in
cassandra.yaml
in the
client_encryption_options
section. There are two primary toggles here for enabling encryption,
enabled
and
optional
.
If neither is set to
true
, client connections are entirely unencrypted.
If
enabled
is set to
true
and
optional
is set to
false
, all client connections must be secured.
If both options are set to
true
, both encrypted and unencrypted connections are supported using the same port. Client connections using encryption with this configuration will be automatically detected and handled by the server.
As an alternative to the
optional
setting, separate ports can also be configured for secure and unsecure connections where operational requirements demand it. To do so, set
optional
to false and use the
native_transport_port_ssl
setting in
cassandra.yaml
to specify the port to be used for secure client communication.
Roles
Cassandra uses database roles, which may represent either a single user or a group of users, in both authentication and permissions management. Role management is an extension point in Cassandra and may be configured using the
role_manager
setting in
cassandra.yaml
. The default setting uses
CassandraRoleManager
, an implementation which stores role information in the tables of the
system_auth
keyspace.
See also the
CQL documentation on roles
.
Authentication
Authentication is pluggable in Cassandra and is configured using the
authenticator
setting in
cassandra.yaml
. Cassandra ships with two options included in the default distribution.
By default, Cassandra is configured with
AllowAllAuthenticator
which performs no authentication checks and therefore requires no credentials. It is used to disable authentication completely. Note that authentication is a necessary condition of Cassandra’s permissions subsystem, so if authentication is disabled, effectively so are permissions.
The default distribution also includes
PasswordAuthenticator
, which stores encrypted credentials in a system table. This can be used to enable simple username/password authentication.
Enabling Password Authentication
Before enabling client authentication on the cluster, client applications should be pre-configured with their intended credentials. When a connection is initiated, the server will only ask for credentials once authentication is enabled, so setting up the client side config in advance is safe. In contrast, as soon as a server has authentication enabled, any connection attempt without proper credentials will be rejected which may cause availability problems for client applications. Once clients are setup and ready for authentication to be enabled, follow this procedure to enable it on the cluster.
Pick a single node in the cluster on which to perform the initial configuration. Ideally, no clients should connect to this node during the setup process, so you may want to remove it from client config, block it at the network level or possibly add a new temporary node to the cluster for this purpose. On that node, perform the following steps:
Open a
cqlsh
session and change the replication factor of the
system_auth
keyspace. By default, this keyspace uses
SimpleReplicationStrategy
and a
replication_factor
of 1. It is recommended to change this for any non-trivial deployment to ensure that should nodes become unavailable, login is still possible. Best practice is to configure a replication factor of 3 to 5 per-DC.
ALTER KEYSPACE system_auth WITH replication = {'class': 'NetworkTopologyStrategy', 'DC1': 3, 'DC2': 3};
Edit
cassandra.yaml
to change the
authenticator
option like so:
authenticator: PasswordAuthenticator
Restart the node.
Open a new
cqlsh
session using the credentials of the default superuser:
$ cqlsh -u cassandra -p cassandra
During login, the credentials for the default superuser are read with a consistency level of
QUORUM
, whereas those for all other users (including superusers) are read at
LOCAL_ONE
. In the interests of performance and availability, as well as security, operators should create another superuser and disable the default one. This step is optional, but highly recommended. While logged in as the default superuser, create another superuser role which can be used to bootstrap further configuration.
# create a new superuser CREATE ROLE dba WITH SUPERUSER = true AND LOGIN = true AND PASSWORD = 'super';
Start a new cqlsh session, this time logging in as the new_superuser and disable the default superuser.
ALTER ROLE cassandra WITH SUPERUSER = false AND LOGIN = false;
Finally, set up the roles and credentials for your application users with
CREATE ROLE
statements.
At the end of these steps, the one node is configured to use password authentication. To roll that out across the cluster, repeat steps 2 and 3 on each node in the cluster. Once all nodes have been restarted, authentication will be fully enabled throughout the cluster.
Note that using
PasswordAuthenticator
also requires the use of
CassandraRoleManager
.
See also:
setting-credentials-for-internal-authentication
,
CREATE ROLE
,
ALTER ROLE
,
ALTER KEYSPACE
and
GRANT PERMISSION
.
Authorization
Authorization is pluggable in Cassandra and is configured using the
authorizer
setting in
cassandra.yaml
. Cassandra ships with two options included in the default distribution.
By default, Cassandra is configured with
AllowAllAuthorizer
which performs no checking and so effectively grants all permissions to all roles. This must be used if
AllowAllAuthenticator
is the configured authenticator.
The default distribution also includes
CassandraAuthorizer
, which does implement full permissions management functionality and stores its data in Cassandra system tables.
Enabling Internal Authorization
Permissions are modelled as a whitelist, with the default assumption that a given role has no access to any database resources. The implication of this is that once authorization is enabled on a node, all requests will be rejected until the required permissions have been granted. For this reason, it is strongly recommended to perform the initial setup on a node which is not processing client requests.
The following assumes that authentication has already been enabled via the process outlined in
password-authentication
. Perform these steps to enable internal authorization across the cluster:
On the selected node, edit
cassandra.yaml
to change the
authorizer
option like so:
authorizer: CassandraAuthorizer
Restart the node.
Open a new
cqlsh
session using the credentials of a role with superuser credentials:
$ cqlsh -u dba -p super
Configure the appropriate access privileges for your clients using
GRANT PERMISSION
statements. On the other nodes, until configuration is updated and the node restarted, this will have no effect so disruption to clients is avoided.
GRANT SELECT ON ks.t1 TO db_user;
Once all the necessary permissions have been granted, repeat steps 1 and 2 for each node in turn. As each node restarts and clients reconnect, the enforcement of the granted permissions will begin.
See also:
GRANT PERMISSION
,
GRANT ALL
and
REVOKE PERMISSION
.
Caching
Enabling authentication and authorization places additional load on the cluster by frequently reading from the
system_auth
tables. Furthermore, these reads are in the critical paths of many client operations, and so has the potential to severely impact quality of service. To mitigate this, auth data such as credentials, permissions and role details are cached for a configurable period. The caching can be configured (and even disabled) from
cassandra.yaml
or using a JMX client. The JMX interface also supports invalidation of the various caches, but any changes made via JMX are not persistent and will be re-read from
cassandra.yaml
when the node is restarted.
Each cache has 3 options which can be set:
Validity Period
Controls the expiration of cache entries. After this period, entries are invalidated and removed from the cache.
Refresh Rate
Controls the rate at which background reads are performed to pick up any changes to the underlying data. While these async refreshes are performed, caches will continue to serve (possibly) stale data. Typically, this will be set to a shorter time than the validity period.
Max Entries
Controls the upper bound on cache size.
The naming for these options in
cassandra.yaml
follows the convention:
<type>_validity_in_ms
<type>_update_interval_in_ms
<type>_cache_max_entries
Where
<type>
is one of
credentials
,
permissions
, or
roles
.
As mentioned, these are also exposed via JMX in the mbeans under the
org.apache.cassandra.auth
domain.
JMX access
Access control for JMX clients is configured separately to that for CQL. For both authentication and authorization, two providers are available; the first based on standard JMX security and the second which integrates more closely with Cassandra’s own auth subsystem.
The default settings for Cassandra make JMX accessible only from localhost. To enable remote JMX connections, edit
cassandra-env.sh
to change the
LOCAL_JMX
setting to
no
. Under the standard configuration, when remote JMX connections are enabled,
standard JMX authentication <standard-jmx-auth>
is also switched on.
Note that by default, local-only connections are not subject to authentication, but this can be enabled.
If enabling remote connections, it is recommended to also use
SSL
connections.
Finally, after enabling auth and/or SSL, ensure that tools which use JMX, such as
nodetool
are correctly configured and working as expected.
Standard JMX Auth
Users permitted to connect to the JMX server are specified in a simple text file. The location of this file is set in
cassandra-env.sh
by the line:
JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.password.file=/etc/cassandra/jmxremote.password"
Edit the password file to add username/password pairs:
jmx_user jmx_password
Secure the credentials file so that only the user running the Cassandra process can read it :
$ chown cassandra:cassandra /etc/cassandra/jmxremote.password $ chmod 400 /etc/cassandra/jmxremote.password
Optionally, enable access control to limit the scope of what defined users can do via JMX. Note that this is a fairly blunt instrument in this context as most operational tools in Cassandra require full read/write access. To configure a simple access file, uncomment this line in
cassandra-env.sh
:
#JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.access.file=/etc/cassandra/jmxremote.access"
Then edit the access file to grant your JMX user readwrite permission:
jmx_user readwrite
Cassandra must be restarted to pick up the new settings.
See also :
Using File-Based Password Authentication In JMX
Cassandra Integrated Auth
An alternative to the out-of-the-box JMX auth is to useeCassandra’s own authentication and/or authorization providers for JMX clients. This is potentially more flexible and secure but it come with one major caveat. Namely that it is not available until
after
a node has joined the ring, because the auth subsystem is not fully configured until that point However, it is often critical for monitoring purposes to have JMX access particularly during bootstrap. So it is recommended, where possible, to use local only JMX auth during bootstrap and then, if remote connectivity is required, to switch to integrated auth once the node has joined the ring and initial setup is complete.
With this option, the same database roles used for CQL authentication can be used to control access to JMX, so updates can be managed centrally using just
cqlsh
. Furthermore, fine grained control over exactly which operations are permitted on particular MBeans can be acheived via
GRANT PERMISSION
.
To enable integrated authentication, edit
cassandra-env.sh
to uncomment these lines:
#JVM_OPTS="$JVM_OPTS -Dcassandra.jmx.remote.login.config=CassandraLogin" #JVM_OPTS="$JVM_OPTS -Djava.security.auth.login.config=$CASSANDRA_HOME/conf/cassandra-jaas.config"
And disable the JMX standard auth by commenting this line:
JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.password.file=/etc/cassandra/jmxremote.password"
To enable integrated authorization, uncomment this line:
#JVM_OPTS="$JVM_OPTS -Dcassandra.jmx.authorizer=org.apache.cassandra.auth.jmx.AuthorizationProxy"
Check standard access control is off by ensuring this line is commented out:
#JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.access.file=/etc/cassandra/jmxremote.access"
With integrated authentication and authorization enabled, operators can define specific roles and grant them access to the particular JMX resources that they need. For example, a role with the necessary permissions to use tools such as jconsole or jmc in read-only mode would be defined as:
CREATE ROLE jmx WITH LOGIN = false; GRANT SELECT ON ALL MBEANS TO jmx; GRANT DESCRIBE ON ALL MBEANS TO jmx; GRANT EXECUTE ON MBEAN 'java.lang:type=Threading' TO jmx; GRANT EXECUTE ON MBEAN 'com.sun.management:type=HotSpotDiagnostic' TO jmx; # Grant the role with necessary permissions to use nodetool commands (including nodetool status) in read-only mode GRANT EXECUTE ON MBEAN 'org.apache.cassandra.db:type=EndpointSnitchInfo' TO jmx; GRANT EXECUTE ON MBEAN 'org.apache.cassandra.db:type=StorageService' TO jmx; # Grant the jmx role to one with login permissions so that it can access the JMX tooling CREATE ROLE ks_user WITH PASSWORD = 'password' AND LOGIN = true AND SUPERUSER = false; GRANT jmx TO ks_user;
Fine grained access control to individual MBeans is also supported:
GRANT EXECUTE ON MBEAN 'org.apache.cassandra.db:type=Tables,keyspace=test_keyspace,table=t1' TO ks_user; GRANT EXECUTE ON MBEAN 'org.apache.cassandra.db:type=Tables,keyspace=test_keyspace,table=*' TO ks_owner;
This permits the
ks_user
role to invoke methods on the MBean representing a single table in
test_keyspace
, while granting the same permission for all table level MBeans in that keyspace to the
ks_owner
role.
Adding/removing roles and granting/revoking of permissions is handled dynamically once the initial setup is complete, so no further restarts are required if permissions are altered.
See also:
Permissions
.
JMX With SSL
JMX SSL configuration is controlled by a number of system properties, some of which are optional. To turn on SSL, edit the relevant lines in
cassandra-env.sh
to uncomment and set the values of these properties as required:
com.sun.management.jmxremote.ssl
set to true to enable SSL
com.sun.management.jmxremote.ssl.need.client.auth
set to true to enable validation of client certificates
com.sun.management.jmxremote.registry.ssl
enables SSL sockets for the RMI registry from which clients obtain the JMX connector stub
com.sun.management.jmxremote.ssl.enabled.protocols
by default, the protocols supported by the JVM will be used, override with a comma-separated list. Note that this is not usually necessary and using the defaults is the preferred option.
com.sun.management.jmxremote.ssl.enabled.cipher.suites
by default, the cipher suites supported by the JVM will be used, override with a comma-separated list. Note that this is not usually necessary and using the defaults is the preferred option.
javax.net.ssl.keyStore
set the path on the local filesystem of the keystore containing server private keys and public certificates
javax.net.ssl.keyStorePassword
set the password of the keystore file
javax.net.ssl.trustStore
if validation of client certificates is required, use this property to specify the path of the truststore containing the public certificates of trusted clients
javax.net.ssl.trustStorePassword
set the password of the truststore file
See also:
Oracle Java7 Docs
,
Monitor Java with JMX
Crypto providers
The ability to specify a custom Java Crypto Provider was done as part of
CASSANDRA-18624
The default configuration of
crypto_provider
in
cassandra.yaml
looks like this:
# Configures Java crypto provider. By default, it will use # DefaultCryptoProvider which will install Amazon Correto # Crypto Provider. # # Amazon Correto Crypto Provider works currently for # x86_64 and aarch_64 platforms. If this provider fails it will # fall back to the default crypto provider in the JRE. # # To force failure when the provider was not installed properly, # set the property "fail_on_missing_provider" to "true". # # To bypass the installation of a crypto provider use # class 'org.apache.cassandra.security.JREProvider' # crypto_provider: - class_name: org.apache.cassandra.security.DefaultCryptoProvider parameters: - fail_on_missing_provider: "false"
For older nodes, when they upgrade to Cassandra 5.0 with the same
cassandra.yaml
where
crypto_provider
section is not set yet, they will default to
JREProvider
which does not install any provider, and it will use the one which is in a JRE Cassandra runs with.
As the above snippet shows,
DefaultCryptoProvider
is installing
Amazon Corretto Crypto provider
which is proven to be way more performant than default crypto providers in a JRE installation.
If you want to use other crypto provider, you have two options.
The first one is to configure your JRE, specifically
java.security
file, to instruct JRE what crypto provider to use. You would need to put respective implementation of such crypto provider to the class path of JRE as well.
The second option is to implement your own crypto provider by extending
org.apache.cassandra.security.AbstractCryptoProvider
and implementing four methods:
getProviderName
Returns name of your provider
getProviderClassAsString
Returns FQCN of your actual crypto provider which extends
java.security.Provider
.
installator
Returns
Runnable
which installs your
java.security.Provider
in runtime.
isHealthyInstallation
Returns
true
if the installation is
healthy
, false otherwise. This serves as a way to check if the installation of your provider was successful or not.
Upon installation of a crypto provider,
AbstractCryptoProvider
checks whether the provider you want to install is already installed or not. If it is installed and its installation position is
1
(as providers are installed in an order), a message will be logged about this fact. This case may happen if you configured your JRE directly via
java.security
and you try to install same provider by Cassandra itself as well.
If it is installed already but not on the first position, if
fail_on_missing_provider
is set to
true
, an exception will be thrown and a node will fail to start. Same happens if the installation of a provider is not successful as such.
Platform-specific libraries are added to Cassandra’s class path automatically by
cassandra.in.sh
script. Currently, there are
lib/aarch64
and
lib/x86_64
directories with JAR files for each respective architecture. A platform is determined by the output of
uname -m
command.
Foundation
Events
License
Thanks
Security
Privacy
Sponsorship
© 2009-
The Apache Software Foundation
under the terms of the Apache License 2.0. Apache, the Apache feather logo, Apache Cassandra, Cassandra, and the Cassandra logo, are either registered trademarks or trademarks of The Apache Software Foundation.

## Roles and Permissions

Source: https://cassandra.apache.org/doc/latest/cassandra/developing/cql/security.html

Database Roles | Apache Cassandra Documentation
Cassandra Documentation
Version:
5.0
website
7.0
6.0
5.0.8
5.0
4.1
4.0
3.11
You are viewing the documentation for a prerelease version.
View Latest
Edit
Database Roles
CQL uses database roles to represent users and group of users. Syntactically, a role is defined by:
role_name ::= identifier | string
CREATE ROLE
Creating a role uses the
CREATE ROLE
statement:
create_role_statement ::= CREATE ROLE [ IF NOT EXISTS ] role_name [ WITH role_options# ] role_options ::= role_option ( AND role_option)* role_option ::= PASSWORD '=' string | HASHED PASSWORD '=' string | LOGIN '=' boolean | SUPERUSER '=' boolean | OPTIONS '=' map_literal | ACCESS TO DATACENTERS set_literal | ACCESS TO ALL DATACENTERS | ACCESS FROM CIDRS set_literal | ACCESS FROM ALL CIDRS
For instance:
CREATE ROLE new_role; CREATE ROLE alice WITH PASSWORD = 'password_a' AND LOGIN = true; CREATE ROLE alice WITH HASHED PASSWORD = '$2a$10$JSJEMFm6GeaW9XxT5JIheuEtPvat6i7uKbnTcxX3c1wshIIsGyUtG' AND LOGIN = true; CREATE ROLE bob WITH PASSWORD = 'password_b' AND LOGIN = true AND SUPERUSER = true; CREATE ROLE carlos WITH OPTIONS = { 'custom_option1' : 'option1_value', 'custom_option2' : 99 }; CREATE ROLE alice WITH PASSWORD = 'password_a' AND LOGIN = true AND ACCESS TO DATACENTERS {'DC1', 'DC3'}; CREATE ROLE alice WITH PASSWORD = 'password_a' AND LOGIN = true AND ACCESS TO ALL DATACENTERS; CREATE ROLE bob WITH LOGIN = true and PASSWORD = 'password_d' AND ACCESS FROM CIDRS { 'region1', 'region2' }; CREATE ROLE hob WITH LOGIN = true and PASSWORD = 'password_c' AND ACCESS FROM ALL CIDRS;
By default roles do not possess
LOGIN
privileges or
SUPERUSER
status.
Permissions
on database resources are granted to roles; types of resources include keyspaces, tables, functions and roles themselves. Roles may be granted to other roles to create hierarchical permissions structures; in these hierarchies, permissions and
SUPERUSER
status are inherited, but the
LOGIN
privilege is not.
If a role has the
LOGIN
privilege, clients may identify as that role when connecting. For the duration of that connection, the client will acquire any roles and privileges granted to that role.
Only a client with with the
CREATE
permission on the database roles resource may issue
CREATE ROLE
requests (see the
relevant section
), unless the client is a
SUPERUSER
. Role management in Cassandra is pluggable and custom implementations may support only a subset of the listed options.
Role names should be quoted if they contain non-alphanumeric characters.
Setting credentials for internal authentication
Use the
WITH PASSWORD
clause to set a password for internal authentication, enclosing the password in single quotation marks.
If internal authentication has not been set up or the role does not have
LOGIN
privileges, the
WITH PASSWORD
clause is not necessary.
USE
WITH HASHED PASSWORD
to provide the jBcrypt hashed password directly. See the
hash_password
tool.
Restricting connections to specific datacenters
If a
network_authorizer
has been configured, you can restrict login roles to specific datacenters with the
ACCESS TO DATACENTERS
clause followed by a set literal of datacenters the user can access. Not specifiying datacenters implicitly grants access to all datacenters. The clause
ACCESS TO ALL DATACENTERS
can be used for explicitness, but there’s no functional difference.
Restricting connections from specific CIDR groups
If a
cidr_authorizer
has been configured, you can restrict roles to login only from specific regions, aka CIDR groups, with the
ACCESS FROM CIDRS
clause followed by a set literal of CIDR groups the user can access from. Not specifying CIDR groups implicitly grants access from all CIDR groups. The clause
ACCESS FROM ALL CIDRS
can be used for explicitness, but there’s no functional difference. This clause can be also be used to remove any CIDR groups restrictions. Valid CIDR groups should be used with
ACCESS FROM CIDRS
clause.
nodetool list-cidrgroups
command can be used to see available CIDR groups in the Cluster.
Creating a role conditionally
Attempting to create an existing role results in an invalid query condition unless the
IF NOT EXISTS
option is used. If the option is used and the role exists, the statement is a no-op:
CREATE ROLE other_role; CREATE ROLE IF NOT EXISTS other_role;
ALTER ROLE
Altering a role options uses the
ALTER ROLE
statement:
alter_role_statement ::= ALTER ROLE [ IF EXISTS ] role_name WITH role_options
For example:
ALTER ROLE bob WITH PASSWORD = 'PASSWORD_B' AND SUPERUSER = false; ALTER ROLE bob WITH HASHED PASSWORD = '$2a$10$JSJEMFm6GeaW9XxT5JIheuEtPvat6i7uKbnTcxX3c1wshIIsGyUtG' AND SUPERUSER = false; ALTER ROLE rob WITH LOGIN = true and PASSWORD = 'password_c' AND ACCESS FROM ALL CIDRS; ALTER ROLE hob WITH LOGIN = true and PASSWORD = 'password_d' AND ACCESS FROM CIDRS { 'region1' };
If the role does not exist, the statement will return an error, unless
IF EXISTS
is used in which case the operation is a no-op.
USE
WITH HASHED PASSWORD
to provide the jBcrypt hashed password directly. See the
hash_password
tool.
Restricting connections to specific datacenters
If a
network_authorizer
has been configured, you can restrict login roles to specific datacenters with the
ACCESS TO DATACENTERS
clause followed by a set literal of datacenters the user can access. To remove any data center restrictions, use the
ACCESS TO ALL DATACENTERS
clause.
Restricting connections from specific CIDR groups
If a
cidr_authorizer
has been configured, you can restrict roles to login only from specific regions, aka CIDR groups, with the
ACCESS FROM CIDRS
clause followed by a set literal of CIDR groups the user can access from. Not specifying CIDR groups implicitly grants access from all CIDR groups. The clause
ACCESS FROM ALL CIDRS
can be used for explicitness, but there’s no functional difference. This clause can be also be used to remove any CIDR groups restrictions. Valid CIDR groups should be used with
ACCESS FROM CIDRS
clause.
nodetool list-cidrgroups
command can be used to see available CIDR groups in the Cluster.
Conditions on executing
ALTER ROLE
statements:
a client must have
SUPERUSER
status to alter the
SUPERUSER
status of another role
a client cannot alter the
SUPERUSER
status of any role it currently holds
a client can only modify certain properties of the role with which it identified at login (e.g.
PASSWORD
)
to modify properties of a role, the client must be granted
ALTER
permission <cql-permissions>
on that role
DROP ROLE
Dropping a role uses the
DROP ROLE
statement:
drop_role_statement ::= DROP ROLE [ IF EXISTS ] role_name
DROP ROLE
requires the client to have
DROP
permission <cql-permissions>
on the role in question. In addition, client may not
DROP
the role with which it identified at login. Finally, only a client with
SUPERUSER
status may
DROP
another
SUPERUSER
role.
Attempting to drop a role which does not exist results in an invalid query condition unless the
IF EXISTS
option is used. If the option is used and the role does not exist the statement is a no-op.
DROP ROLE intentionally does not terminate any open user sessions. Currently connected sessions will remain connected and will retain the ability to perform any database actions which do not require
authorization
. However, if authorization is enabled,
permissions
of the dropped role are also revoked, subject to the
caching options
configured in
cassandra-yaml
file. Should a dropped role be subsequently recreated and have new
permissions
or
roles
granted to it, any client sessions still connected will acquire the newly granted permissions and roles.
GRANT ROLE
Granting a role to another uses the
GRANT ROLE
statement:
grant_role_statement ::= GRANT role_name TO role_name
For example:
GRANT report_writer TO alice;
This statement grants the
report_writer
role to
alice
. Any permissions granted to
report_writer
are also acquired by
alice
.
Roles are modelled as a directed acyclic graph, so circular grants are not permitted. The following examples result in error conditions:
GRANT role_a TO role_b; GRANT role_b TO role_a; GRANT role_a TO role_b; GRANT role_b TO role_c; GRANT role_c TO role_a;
REVOKE ROLE
Revoking a role uses the
REVOKE ROLE
statement:
revoke_role_statement ::= REVOKE role_name FROM role_name
For example:
REVOKE report_writer FROM alice;
This statement revokes the
report_writer
role from
alice
. Any permissions that
alice
has acquired via the
report_writer
role are also revoked.
LIST ROLES
All the known roles (in the system or granted to specific role) can be listed using the
LIST ROLES
statement:
list_roles_statement ::= LIST ROLES [ OF role_name] [ NORECURSIVE ]
For instance:
LIST ROLES;
returns all known roles in the system, this requires
DESCRIBE
permission on the database roles resource.
This example enumerates all roles granted to
alice
, including those transitively acquired:
LIST ROLES OF alice;
This example lists all roles directly granted to
bob
without including any of the transitively acquired ones:
LIST ROLES OF bob NORECURSIVE;
Users
Prior to the introduction of roles in Cassandra 2.2, authentication and authorization were based around the concept of a
USER
. For backward compatibility, the legacy syntax has been preserved with
USER
centric statements becoming synonyms for the
ROLE
based equivalents. In other words, creating/updating a user is just a different syntax for creating/updating a role.
CREATE USER
Creating a user uses the
CREATE USER
statement:
create_user_statement ::= CREATE USER [ IF NOT EXISTS ] role_name [ WITH [ HASHED ] PASSWORD string ] [ user_option ] user_option: SUPERUSER | NOSUPERUSER
For example:
CREATE USER alice WITH PASSWORD 'password_a' SUPERUSER; CREATE USER bob WITH PASSWORD 'password_b' NOSUPERUSER; CREATE USER bob WITH HASHED PASSWORD '$2a$10$JSJEMFm6GeaW9XxT5JIheuEtPvat6i7uKbnTcxX3c1wshIIsGyUtG' NOSUPERUSER;
The
CREATE USER
command is equivalent to
CREATE ROLE
where the
LOGIN
option is
true
. So, the following pairs of statements are equivalent:
CREATE USER alice WITH PASSWORD 'password_a' SUPERUSER; CREATE ROLE alice WITH PASSWORD = 'password_a' AND LOGIN = true AND SUPERUSER = true; CREATE USER IF NOT EXISTS alice WITH PASSWORD 'password_a' SUPERUSER; CREATE ROLE IF NOT EXISTS alice WITH PASSWORD = 'password_a' AND LOGIN = true AND SUPERUSER = true; CREATE USER alice WITH PASSWORD 'password_a' NOSUPERUSER; CREATE ROLE alice WITH PASSWORD = 'password_a' AND LOGIN = true AND SUPERUSER = false; CREATE USER alice WITH PASSWORD 'password_a' NOSUPERUSER; CREATE ROLE alice WITH PASSWORD = 'password_a' AND LOGIN = true; CREATE USER alice WITH PASSWORD 'password_a'; CREATE ROLE alice WITH PASSWORD = 'password_a' AND LOGIN = true; CREATE ROLE rob WITH LOGIN = true and PASSWORD = 'password_c' AND ACCESS FROM ALL CIDRS; CREATE ROLE hob WITH LOGIN = true and PASSWORD = 'password_d' AND ACCESS FROM CIDRS { 'region1' };
ALTER USER
Altering the options of a user uses the
ALTER USER
statement:
alter_user_statement ::= ALTER USER [ IF EXISTS ] role_name [ WITH [ HASHED ] PASSWORD string] [ user_option]
If the role does not exist, the statement will return an error, unless
IF EXISTS
is used in which case the operation is a no-op. For example:
ALTER USER alice WITH PASSWORD 'PASSWORD_A'; ALTER USER alice WITH HASHED PASSWORD '$2a$10$JSJEMFm6GeaW9XxT5JIheuEtPvat6i7uKbnTcxX3c1wshIIsGyUtG'; ALTER USER bob SUPERUSER;
DROP USER
Dropping a user uses the
DROP USER
statement:
drop_user_statement ::= DROP USER [ IF EXISTS ] role_name
LIST USERS
Existing users can be listed using the
LIST USERS
statement:
list_users_statement::= LIST USERS
Note that this statement is equivalent to
LIST ROLES
, but only roles with the
LOGIN
privilege are included in the output.
Data Control
Permissions
Permissions on resources are granted to roles; there are several different types of resources in Cassandra and each type is modelled hierarchically:
The hierarchy of Data resources, Keyspaces and Tables has the structure
ALL KEYSPACES
→
KEYSPACE
→
TABLE
.
Function resources have the structure
ALL FUNCTIONS
→
KEYSPACE
→
FUNCTION
Resources representing roles have the structure
ALL ROLES
→
ROLE
Resources representing JMX ObjectNames, which map to sets of MBeans/MXBeans, have the structure
ALL MBEANS
→
MBEAN
Permissions can be granted at any level of these hierarchies and they flow downwards. So granting a permission on a resource higher up the chain automatically grants that same permission on all resources lower down. For example, granting
SELECT
on a
KEYSPACE
automatically grants it on all
TABLES
in that
KEYSPACE
. Likewise, granting a permission on
ALL FUNCTIONS
grants it on every defined function, regardless of which keyspace it is scoped in. It is also possible to grant permissions on all functions scoped to a particular keyspace.
Modifications to permissions are visible to existing client sessions; that is, connections need not be re-established following permissions changes.
The full set of available permissions is:
CREATE
ALTER
DROP
SELECT
MODIFY
AUTHORIZE
DESCRIBE
EXECUTE
UNMASK
SELECT_MASKED
Not all permissions are applicable to every type of resource. For instance,
EXECUTE
is only relevant in the context of functions or mbeans; granting
EXECUTE
on a resource representing a table is nonsensical. Attempting to
GRANT
a permission on resource to which it cannot be applied results in an error response. The following illustrates which permissions can be granted on which types of resource, and which statements are enabled by that permission.
Permission
Resource
Operations
CREATE
ALL KEYSPACES
CREATE KEYSPACE
and
CREATE TABLE
in any keyspace
CREATE
KEYSPACE
CREATE TABLE
in specified keyspace
CREATE
ALL FUNCTIONS
CREATE FUNCTION
in any keyspace and
CREATE AGGREGATE
in any keyspace
CREATE
ALL FUNCTIONS IN KEYSPACE
CREATE FUNCTION
and
CREATE AGGREGATE
in specified keyspace
CREATE
ALL ROLES
CREATE ROLE
ALTER
ALL KEYSPACES
ALTER KEYSPACE
and
ALTER TABLE
in any keyspace
ALTER
KEYSPACE
ALTER KEYSPACE
and
ALTER TABLE
in specified keyspace
ALTER
TABLE
ALTER TABLE
ALTER
ALL FUNCTIONS
CREATE FUNCTION
and
CREATE AGGREGATE
: replacing any existing
ALTER
ALL FUNCTIONS IN KEYSPACE
CREATE FUNCTION
and
CREATE AGGREGATE
: replacing existing in specified keyspace
ALTER
FUNCTION
CREATE FUNCTION
and
CREATE AGGREGATE
: replacing existing
ALTER
ALL ROLES
ALTER ROLE
on any role
ALTER
ROLE
ALTER ROLE
DROP
ALL KEYSPACES
DROP KEYSPACE
and
DROP TABLE
in any keyspace
DROP
KEYSPACE
DROP TABLE
in specified keyspace
DROP
TABLE
DROP TABLE
DROP
ALL FUNCTIONS
DROP FUNCTION
and
DROP AGGREGATE
in any keyspace
DROP
ALL FUNCTIONS IN KEYSPACE
DROP FUNCTION
and
DROP AGGREGATE
in specified keyspace
DROP
FUNCTION
DROP FUNCTION
DROP
ALL ROLES
DROP ROLE
on any role
DROP
ROLE
DROP ROLE
SELECT
ALL KEYSPACES
SELECT
on any table
SELECT
KEYSPACE
SELECT
on any table in specified keyspace
SELECT
TABLE
SELECT
on specified table
SELECT
ALL MBEANS
Call getter methods on any mbean
SELECT
MBEANS
Call getter methods on any mbean matching a wildcard pattern
SELECT
MBEAN
Call getter methods on named mbean
MODIFY
ALL KEYSPACES
INSERT
,
UPDATE
,
DELETE
and
TRUNCATE
on any table
MODIFY
KEYSPACE
INSERT
,
UPDATE
,
DELETE
and
TRUNCATE
on any table in specified keyspace
MODIFY
TABLE
INSERT
,
UPDATE
,
DELETE
and
TRUNCATE
on specified table
MODIFY
ALL MBEANS
Call setter methods on any mbean
MODIFY
MBEANS
Call setter methods on any mbean matching a wildcard pattern
MODIFY
MBEAN
Call setter methods on named mbean
AUTHORIZE
ALL KEYSPACES
GRANT PERMISSION
and
REVOKE PERMISSION
on any table
AUTHORIZE
KEYSPACE
GRANT PERMISSION
and
REVOKE PERMISSION
on any table in specified keyspace
AUTHORIZE
TABLE
GRANT PERMISSION
and
REVOKE PERMISSION
on specified table
AUTHORIZE
ALL FUNCTIONS
GRANT PERMISSION
and
REVOKE PERMISSION
on any function
AUTHORIZE
ALL FUNCTIONS IN KEYSPACE
GRANT PERMISSION
and
REVOKE PERMISSION
in specified keyspace
AUTHORIZE
FUNCTION
GRANT PERMISSION
and
REVOKE PERMISSION
on specified function
AUTHORIZE
ALL MBEANS
GRANT PERMISSION
and
REVOKE PERMISSION
on any mbean
AUTHORIZE
MBEANS
GRANT PERMISSION
and
REVOKE PERMISSION
on any mbean matching a wildcard pattern
AUTHORIZE
MBEAN
GRANT PERMISSION
and
REVOKE PERMISSION
on named mbean
AUTHORIZE
ALL ROLES
GRANT ROLE
and
REVOKE ROLE
on any role
AUTHORIZE
ROLES
GRANT ROLE
and
REVOKE ROLE
on specified roles
DESCRIBE
ALL ROLES
LIST ROLES
on all roles or only roles granted to another, specified role
DESCRIBE
ALL MBEANS
Retrieve metadata about any mbean from the platform’s MBeanServer
DESCRIBE
MBEANS
Retrieve metadata about any mbean matching a wildcard patter from the platform’s MBeanServer
DESCRIBE
MBEAN
Retrieve metadata about a named mbean from the platform’s MBeanServer
EXECUTE
ALL FUNCTIONS
SELECT
,
INSERT
and
UPDATE
using any function, and use of any function in
CREATE AGGREGATE
EXECUTE
ALL FUNCTIONS IN KEYSPACE
SELECT
,
INSERT
and
UPDATE
using any function in specified keyspace and use of any function in keyspace in
CREATE AGGREGATE
EXECUTE
FUNCTION
SELECT
,
INSERT
and
UPDATE
using specified function and use of the function in
CREATE AGGREGATE
EXECUTE
ALL MBEANS
Execute operations on any mbean
EXECUTE
MBEANS
Execute operations on any mbean matching a wildcard pattern
EXECUTE
MBEAN
Execute operations on named mbean
UNMASK
ALL KEYSPACES
See the clear contents of masked columns on any table
UNMASK
KEYSPACE
See the clear contents of masked columns on any table in keyspace
UNMASK
TABLE
See the clear contents of masked columns on the specified table
SELECT_MASKED
ALL KEYSPACES
SELECT
restricting masked columns on any table
SELECT_MASKED
KEYSPACE
SELECT
restricting masked columns on any table in specified keyspace
SELECT_MASKED
TABLE
SELECT
restricting masked columns on the specified table
GRANT PERMISSION
Granting a permission uses the
GRANT PERMISSION
statement:
grant_permission_statement ::= GRANT permissions ON resource TO role_name permissions ::= ALL [ PERMISSIONS ] | permission [ PERMISSION ] permission ::= CREATE | ALTER | DROP | SELECT | MODIFY | AUTHORIZE | DESCRIBE | EXECUTE | UNMASK | SELECT_MASKED resource ::= ALL KEYSPACES | KEYSPACE keyspace_name | [ TABLE ] table_name | ALL ROLES | ROLE role_name | ALL FUNCTIONS [ IN KEYSPACE keyspace_name ] | FUNCTION function_name '(' [ cql_type( ',' cql_type )* ] ')' | ALL MBEANS | ( MBEAN | MBEANS ) string
For example:
GRANT SELECT ON ALL KEYSPACES TO data_reader;
This example gives any user with the role
data_reader
permission to execute
SELECT
statements on any table across all keyspaces:
GRANT MODIFY ON KEYSPACE keyspace1 TO data_writer;
To give any user with the role
data_writer
permission to perform
UPDATE
,
INSERT
,
UPDATE
,
DELETE
and
TRUNCATE
queries on all tables in the
keyspace1
keyspace:
GRANT DROP ON keyspace1.table1 TO schema_owner;
To give any user with the
schema_owner
role permissions to
DROP
a specific
keyspace1.table1
:
GRANT EXECUTE ON FUNCTION keyspace1.user_function( int ) TO report_writer;
This command grants any user with the
report_writer
role permission to execute
SELECT
,
INSERT
and
UPDATE
queries which use the function
keyspace1.user_function( int )
:
GRANT DESCRIBE ON ALL ROLES TO role_admin;
This grants any user with the
role_admin
role permission to view any and all roles in the system with a
LIST ROLES
statement.
GRANT ALL
When the
GRANT ALL
form is used, the appropriate set of permissions is determined automatically based on the target resource.
Automatic Granting
When a resource is created, via a
CREATE KEYSPACE
,
CREATE TABLE
,
CREATE FUNCTION
,
CREATE AGGREGATE
or
CREATE ROLE
statement, the creator (the role the database user who issues the statement is identified as), is automatically granted all applicable permissions on the new resource.
REVOKE PERMISSION
Revoking a permission from a role uses the
REVOKE PERMISSION
statement:
revoke_permission_statement ::= REVOKE permissions ON resource FROM role_name
For example:
REVOKE SELECT ON ALL KEYSPACES FROM data_reader; REVOKE MODIFY ON KEYSPACE keyspace1 FROM data_writer; REVOKE DROP ON keyspace1.table1 FROM schema_owner; REVOKE EXECUTE ON FUNCTION keyspace1.user_function( int ) FROM report_writer; REVOKE DESCRIBE ON ALL ROLES FROM role_admin;
Because of their function in normal driver operations, certain tables cannot have their
SELECT
permissions revoked. The following tables will be available to all authorized users regardless of their assigned role:
* system_schema.keyspaces * system_schema.columns * system_schema.tables * system.local * system.peers
LIST PERMISSIONS
Listing granted permissions uses the
LIST PERMISSIONS
statement:
list_permissions_statement ::= LIST permissions [ ON resource] [ OF role_name[ NORECURSIVE ] ]
For example:
LIST ALL PERMISSIONS OF alice;
Show all permissions granted to
alice
, including those acquired transitively from any other roles:
LIST ALL PERMISSIONS ON keyspace1.table1 OF bob;
Show all permissions on
keyspace1.table1
granted to
bob
, including those acquired transitively from any other roles. This also includes any permissions higher up the resource hierarchy which can be applied to
keyspace1.table1
. For example, should
bob
have
ALTER
permission on
keyspace1
, that would be included in the results of this query. Adding the
NORECURSIVE
switch restricts the results to only those permissions which were directly granted to
bob
or one of `bob’s roles:
LIST SELECT PERMISSIONS OF carlos;
Show any permissions granted to
carlos
or any roles assigned to
carlos
, limited to
SELECT
permissions on any resource.
Foundation
Events
License
Thanks
Security
Privacy
Sponsorship
© 2009-
The Apache Software Foundation
under the terms of the Apache License 2.0. Apache, the Apache feather logo, Apache Cassandra, Cassandra, and the Cassandra logo, are either registered trademarks or trademarks of The Apache Software Foundation.

## Topology Changes

Source: https://cassandra.apache.org/doc/latest/cassandra/managing/operating/topo_changes.html

Adding, replacing, moving and removing nodes | Apache Cassandra Documentation
Cassandra Documentation
Version:
5.0
website
7.0
6.0
5.0.8
5.0
4.1
4.0
3.11
You are viewing the documentation for a prerelease version.
View Latest
Edit
Adding, replacing, moving and removing nodes
Bootstrap
Adding new nodes is called "bootstrapping". The
num_tokens
parameter will define the amount of virtual nodes (tokens) the joining node will be assigned during bootstrap. The tokens define the sections of the ring (token ranges) the node will become responsible for.
Token allocation
With the default token allocation algorithm the new node will pick
num_tokens
random tokens to become responsible for. Since tokens are distributed randomly, load distribution improves with a higher amount of virtual nodes, but it also increases token management overhead. The default of 256 virtual nodes should provide a reasonable load balance with acceptable overhead.
On 3.0+ a new token allocation algorithm was introduced to allocate tokens based on the load of existing virtual nodes for a given keyspace, and thus yield an improved load distribution with a lower number of tokens. To use this approach, the new node must be started with the JVM option
-Dcassandra.allocate_tokens_for_keyspace=<keyspace>
, where
<keyspace>
is the keyspace from which the algorithm can find the load information to optimize token assignment for.
Manual token assignment
You may specify a comma-separated list of tokens manually with the
initial_token
cassandra.yaml
parameter, and if that is specified Cassandra will skip the token allocation process. This may be useful when doing token assignment with an external tool or when restoring a node with its previous tokens.
Range streaming
After the tokens are allocated, the joining node will pick current replicas of the token ranges it will become responsible for to stream data from. By default it will stream from the primary replica of each token range in order to guarantee data in the new node will be consistent with the current state.
In the case of any unavailable replica, the consistent bootstrap process will fail. To override this behavior and potentially miss data from an unavailable replica, set the JVM flag
-Dcassandra.consistent.rangemovement=false
.
Resuming failed/hanged bootstrap
On 2.2+, if the bootstrap process fails, it’s possible to resume bootstrap from the previous saved state by calling
nodetool bootstrap resume
. If for some reason the bootstrap hangs or stalls, it may also be resumed by simply restarting the node. In order to cleanup bootstrap state and start fresh, you may set the JVM startup flag
-Dcassandra.reset_bootstrap_progress=true
.
On lower versions, when the bootstrap proces fails it is recommended to wipe the node (remove all the data), and restart the bootstrap process again.
Manual bootstrapping
It’s possible to skip the bootstrapping process entirely and join the ring straight away by setting the hidden parameter
auto_bootstrap: false
. This may be useful when restoring a node from a backup or creating a new data-center.
Removing nodes
You can take a node out of the cluster with
nodetool decommission
to a live node, or
nodetool removenode
(to any other machine) to remove a dead one. This will assign the ranges the old node was responsible for to other nodes, and replicate the appropriate data there. If decommission is used, the data will stream from the decommissioned node. If removenode is used, the data will stream from the remaining replicas.
No data is removed automatically from the node being decommissioned, so if you want to put the node back into service at a different token on the ring, it should be removed manually.
Moving nodes
When
num_tokens: 1
it’s possible to move the node position in the ring with
nodetool move
. Moving is both a convenience over and more efficient than decommission + bootstrap. After moving a node,
nodetool cleanup
should be run to remove any unnecessary data.
Replacing a dead node
In order to replace a dead node, start cassandra with the JVM startup flag
-Dcassandra.replace_address_first_boot=<dead_node_ip>
. Once this property is enabled the node starts in a hibernate state, during which all the other nodes will see this node to be DOWN (DN), however this node will see itself as UP (UN). Accurate replacement state can be found in
nodetool netstats
.
The replacing node will now start to bootstrap the data from the rest of the nodes in the cluster. A replacing node will only receive writes during the bootstrapping phase if it has a different ip address to the node that is being replaced. ( See
CASSANDRA-8523
and
CASSANDRA-12344
)
Once the bootstrapping is complete the node will be marked "UP".
If any of the following cases apply, you
MUST
run repair to make the replaced node consistent again, since it missed ongoing writes during/prior to bootstrapping. The
replacement
timeframe refers to the period from when the node initially dies to when a new node completes the replacement process.
The node is down for longer than
max_hint_window
before being replaced.
You are replacing using the same IP address as the dead node
and
replacement takes longer than
max_hint_window
.
Monitoring progress
Bootstrap, replace, move and remove progress can be monitored using
nodetool netstats
which will show the progress of the streaming operations.
Cleanup data after range movements
As a safety measure, Cassandra does not automatically remove data from nodes that "lose" part of their token range due to a range movement operation (bootstrap, move, replace). Run
nodetool cleanup
on the nodes that lost ranges to the joining node when you are satisfied the new node is up and working. If you do not do this the old data will still be counted against the load on that node.
Foundation
Events
License
Thanks
Security
Privacy
Sponsorship
© 2009-
The Apache Software Foundation
under the terms of the Apache License 2.0. Apache, the Apache feather logo, Apache Cassandra, Cassandra, and the Cassandra logo, are either registered trademarks or trademarks of The Apache Software Foundation.

## Streaming

Source: https://cassandra.apache.org/doc/latest/cassandra/architecture/streaming.html

Improved Streaming | Apache Cassandra Documentation
Cassandra Documentation
Version:
5.0
website
7.0
6.0
5.0.8
5.0
4.1
4.0
3.11
You are viewing the documentation for a prerelease version.
View Latest
Edit
Improved Streaming
Apache Cassandra 4.0 has made several improvements to streaming. Streaming is the process used by nodes of a cluster to exchange data in the form of SSTables. Streaming of SSTables is performed for several operations, such as:
SSTable Repair
Host Replacement
Range movements
Bootstrapping
Rebuild
Cluster expansion
Streaming based on Netty
Streaming in Cassandra 4.0 is based on Non-blocking Input/Output (NIO) with Netty (
CASSANDRA-12229
). It replaces the single-threaded (or sequential), synchronous, blocking model of streaming messages and migrate of files. Netty supports non-blocking, asynchronous, multi-threaded streaming with which multiple connections are opened simultaneously. Non-blocking implies that threads are not blocked as they don’t wait for a response for a sent request. A response could be returned in a different thread. With asynchronous, connections and threads are decoupled and do not have a 1:1 relation. Several more connections than threads may be opened.
Zero Copy Streaming
Pre-4.0, during streaming Cassandra reifies the SSTables into objects. This creates unnecessary garbage and slows down the whole streaming process as some SSTables can be migratered as a whole file rather than individual partitions. Cassandra 4.0 has added support for streaming entire SSTables when possible (
CASSANDRA-14556
) for faster Streaming using ZeroCopy APIs. If enabled, Cassandra will use ZeroCopy for eligible SSTables significantly speeding up migrates and increasing throughput. A zero-copy path avoids bringing data into user-space on both sending and receiving side. Any streaming related operations will notice corresponding improvement. Zero copy streaming is hardware bound; only limited by the hardware limitations (Network and Disk IO ).
High Availability
In benchmark tests Zero Copy Streaming is 5x faster than partitions based streaming. Faster streaming provides the benefit of improved availability. A cluster’s recovery mainly depends on the streaming speed, Cassandra clusters with failed nodes will be able to recover much more quickly (5x faster). If a node fails, SSTables need to be streamed to a replacement node. During the replacement operation, the new Cassandra node streams SSTables from the neighboring nodes that hold copies of the data belonging to this new node’s token range. Depending on the amount of data stored, this process can require substantial network bandwidth, taking some time to complete. The longer these range movement operations take, the more the cluster availability is lost. Failure of multiple nodes would reduce high availability greatly. The faster the new node completes streaming its data, the faster it can serve traffic, increasing the availability of the cluster.
Enabling Zero Copy Streaming
Zero copy streaming is enabled by setting the following setting in
cassandra.yaml
.
stream_entire_sstables: true
Zero copy streaming is enabled by default. === SSTables Eligible for Zero Copy Streaming
Zero copy streaming is used if all partitions within the SSTable need to be transmitted. This is common when using
LeveledCompactionStrategy
or when partitioning SSTables by token range has been enabled. All partition keys in the SSTables are iterated over to determine the eligibility for Zero Copy streaming.
Benefits of Zero Copy Streaming
When enabled, it permits Cassandra to zero-copy stream entire eligible SSTables between nodes, including every component. This speeds up the network migrate significantly subject to throttling specified by
stream_throughput_outbound
.
Enabling this will reduce the GC pressure on sending and receiving node. While this feature tries to keep the disks balanced, it cannot guarantee it. This feature will be automatically disabled if internode encryption is enabled. Currently, this can be used with Leveled Compaction.
Configuring for Zero Copy Streaming
Throttling would reduce the streaming speed. The
stream_throughput_outbound
throttles all outbound streaming file migrates on a node to the given total throughput in Mbps. When unset, the default is 200 Mbps or 24 MiB/s.
stream_throughput_outbound: 24MiB/s
To run any Zero Copy streaming benchmark the
stream_throughput_outbound
must be set to a really high value otherwise, throttling will be significant and the benchmark results will not be meaningful.
The
inter_dc_stream_throughput_outbound
throttles all streaming file migrate between the datacenters, this setting allows users to throttle inter dc stream throughput in addition to throttling all network stream traffic as configured with
stream_throughput_outbound
. When unset, the default is 200 Mbps or 25 MB/s.
inter_dc_stream_throughput_outbound: 24MiB/s
SSTable Components Streamed with Zero Copy Streaming
Zero Copy Streaming streams entire SSTables. SSTables are made up of multiple components in separate files. SSTable components streamed are listed in Table 1.
Table 1. SSTable Components
SSTable Component
Description
Data.db
The base data for an SSTable: the remaining components can be regenerated based on the data component.
Index.db
Index of the row keys with pointers to their positions in the data file.
Filter.db
Serialized bloom filter for the row keys in the SSTable.
CompressionInfo.db
File to hold information about uncompressed data length, chunk offsets etc.
Statistics.db
Statistical metadata about the content of the SSTable.
Digest.crc32
Holds CRC32 checksum of the data file size_bytes.
CRC.db
Holds the CRC32 for chunks in an uncompressed file.
Summary.db
Holds SSTable Index Summary (sampling of Index component)
TOC.txt
Table of contents, stores the list of all components for the SSTable.
Custom component, used by e.g. custom compaction strategy may also be included.
Repair Streaming Preview
Repair with
nodetool repair
involves streaming of repaired SSTables and a repair preview has been added to provide an estimate of the amount of repair streaming that would need to be performed. Repair preview (
CASSANDRA-13257
) is invoked with
nodetool repair --preview
using option:
-prv, --preview
It determines ranges and amount of data to be streamed, but doesn’t actually perform repair.
Parallelizing of Streaming of Keyspaces
The streaming of the different keyspaces for bootstrap and rebuild has been parallelized in Cassandra 4.0 (
CASSANDRA-4663
).
Unique nodes for Streaming in Multi-DC deployment
Range Streamer picks unique nodes to stream data from when number of replicas in each DC is three or more (
CASSANDRA-4650
). What the optimization does is to even out the streaming load across the cluster. Without the optimization, some node can be picked up to stream more data than others. This patch allows to select dedicated node to stream only one range.
This will increase the performance of bootstrapping a node and will also put less pressure on nodes serving the data. This does not affect if N < 3 in each DC as then it streams data from only 2 nodes.
Stream Operation Types
It is important to know the type or purpose of a certain stream. Version 4.0 (
CASSANDRA-13064
) adds an
enum
to distinguish between the different types of streams. Stream types are available both in a stream request and a stream task. The different stream types are:
Restore replica count
Unbootstrap
Relocation
Bootstrap
Rebuild
Bulk Load
Repair
Disallow Decommission when number of Replicas will drop below configured RF
CASSANDRA-12510
guards against decommission that will drop # of replicas below configured replication factor (RF), and adds the
--force
option that allows decommission to continue if intentional; force decommission of this node even when it reduces the number of replicas to below configured RF.
Foundation
Events
License
Thanks
Security
Privacy
Sponsorship
© 2009-
The Apache Software Foundation
under the terms of the Apache License 2.0. Apache, the Apache feather logo, Apache Cassandra, Cassandra, and the Cassandra logo, are either registered trademarks or trademarks of The Apache Software Foundation.
