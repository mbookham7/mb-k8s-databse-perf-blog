# PostgreSQL on EKS: WEKA vs. Standard Block Storage — Measured Results

Real `pgbench` results from the Terraform-provisioned demo in this repo
(`make infra && make apps && make bench`). Run on **2026-06-09**.

## Environment

| Component | Detail |
| --- | --- |
| Region | eu-west-1 |
| Kubernetes | EKS 1.33 |
| PostgreSQL | 16 (`shared_buffers=4GB`, `wal_buffers=64MB`, `max_connections=200`, `checkpoint_completion_target=0.9`, `random_page_cost=1.1`) |
| Standard block | gp3 EBS via `ebs.csi.aws.com` — 3000 IOPS, 125 MB/s |
| WEKA | 6× i3en.2xlarge backend, mounted via `csi.weka.io` (`dir/v1`) |
| DB / client nodes | c6i.4xlarge (16 vCPU / 32 GiB), hyperthreading off |
| pgbench | `-j 4 -T 60 -P 10`, clients 4/16/32/64; both DBs on identical hardware |

Both PostgreSQL instances run on the same instance type with the **only
variable being the storage backend**.

## Headline result (storage-bound, scale factor 1000 ≈ 15 GB)

The working set (~15 GB) far exceeds `shared_buffers` (4 GB) and the pod memory
limit, so reads hit storage — this is the regime the blog describes.

### Transactions per second

| Concurrent clients | gp3 (TPS) | WEKA (TPS) | WEKA improvement |
| --- | --- | --- | --- |
| 4  | 1,159 | 2,307 | **+99%** |
| 16 | 1,216 | 5,328 | **+338%** |
| 32 | 1,588 | 6,491 | **+308%** |
| 64 | 1,811 | 7,211 | **+298%** |

### Average latency (ms)

| Concurrent clients | gp3 (ms) | WEKA (ms) | WEKA improvement |
| --- | --- | --- | --- |
| 4  | 3.44  | 1.73 | **−49%** |
| 16 | 13.06 | 2.95 | **−77%** |
| 32 | 19.94 | 4.76 | **−76%** |
| 64 | 34.95 | 8.39 | **−75%** |

**What the numbers show:** gp3 throughput plateaus around 1,200–1,800 TPS while
its latency climbs steeply (3 → 35 ms) as I/O queues behind the provisioned-IOPS
ceiling. WEKA keeps scaling with concurrency (to ~7,200 TPS) with latency
staying nearly flat (~8 ms at 64 clients). At 64 clients WEKA delivers ~4× the
TPS at ~1/4 the latency — matching the blog's I/O-saturation narrative.

## Important methodology note (a correction to the original post)

The blog states scale factor 100 (~1.5 GB) is "large enough to exceed
shared_buffers." **It is not** — with `shared_buffers=4GB`, a 1.5 GB dataset is
fully cached, so the workload becomes CPU/WAL-bound rather than storage-bound,
and the storage comparison is meaningless.

**Takeaway for the blog:** to demonstrate a storage bottleneck, the dataset must
exceed RAM. Either raise the scale factor so it exceeds `shared_buffers` + page
cache (this repo defaults to **scale 1000**, used above), or lower
`shared_buffers`. Otherwise the benchmark measures CPU and WAL group-commit, not
the storage layer.

## Reproduce

```bash
make infra && make apps          # ~40 min, needs get.weka.io token + Quay creds
make bench                       # scale 1000 by default
# raw per-run tables are written to results/results-<timestamp>.md
```
