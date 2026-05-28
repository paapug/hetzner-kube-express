# Persistent Volumes

The cluster includes Hetzner Cloud's Kubernetes storage integration for persistent data. In practice, Kubernetes `PersistentVolumeClaim` objects that use the Hetzner storage class are backed by Hetzner SSD block storage.

The storage class is `hcloud-volumes`.

## Access mode

Use `ReadWriteOnce` for Hetzner-backed persistent volumes.

Hetzner volumes are block storage attached to cloud servers. A volume can be attached to one server at a time, so it should be treated as single-node writable storage. Do not design workloads around several nodes writing to the same volume at once.

## Size and scaling limits

The minimum volume size is 10 GB.

Volumes can be scaled up to 10 TB at any time. Treat this as grow-only capacity, shrinking a volume is not supported.

Up to 16 volumes can be attached to a single cloud server. This limit matters when several stateful pods land on the same node.

## Operational caveats

Hetzner does not provide performance guarantees for this storage. For serious database, queue, or observability workloads, benchmark the actual workload and monitor disk latency, throughput, and I/O pressure.

As a rough order of magnitude, a single volume on a `cx23` agent in `fsn1` benchmarked with `fio` (random 50/50 read/write, `iodepth=64`, `numjobs=2`, `--direct=1`) lands around:

| Block size | Total throughput | Total IOPS |
|---|---|---|
| 4k   | ~60 MB/s    | ~15,000 |
| 64k  | ~640 MB/s   | ~9,700  |
| 512k | ~620 MB/s   | ~1,200  |
| 1m   | ~620 MB/s   | ~590    |

Persistent volumes are not backups. If a chart or namespace is destroyed, the related Kubernetes objects and volumes may be deleted depending on reclaim policy and chart behavior. Back up important data separately.

Storage is tied to node scheduling. If a pod using a `ReadWriteOnce` volume cannot be scheduled on a node that can attach the volume, it may remain pending until Kubernetes can place it correctly.

For Hetzner's product-level details and current limits, see [Hetzner Block Storage](https://www.hetzner.com/cloud/block-storage/).
