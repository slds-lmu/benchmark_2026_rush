# Benchmark 2026 rush

Benchmark suite for [rush](https://github.com/mlr-org/rush).
Experiments are designed to run at HPC scale (hundreds of workers) on a SLURM cluster via [HyperQueue](https://it4innovations.github.io/hyperqueue/).

The suite has two independent parts:

| Directory | What it measures |
|-----------|------------------|
| [`rush/`](rush/) | Micro-benchmarks of rush's core Redis operations under varying load. |
| [`mbo/`](mbo/)   | Comparison of three distributed model-based optimization (MBO) strategies for hyperparameter tuning. |

## Requirements

The full stack targets a Linux HPC login/compute environment:

- **conda** — provides `r-base` (4.6.0), `redis-server`, `libhiredis`, and supporting libraries.
- **[renv](https://rstudio.github.io/renv/)** — pins the R package library (mlr3, mlr3tuning, mlr3mbo, rush, mirai, batchtools, lightgbm, …). Restoring some packages needs a GitHub PAT.
- **[HyperQueue](https://it4innovations.github.io/hyperqueue/)** (`hq`, v0.26.2) — meta-scheduler that submits work to SLURM. 
Installed into the project root by `setup.sh`.
- **SLURM** — worker allocations are submitted to the `cm4` cluster (`cm4_tiny` partition/QoS).
- **Redis** — shared key–value store that rush workers coordinate through.

## Setup

The setup depends on the HPC environment. 
The `setup.sh` script is a convenience wrapper that creates/activates a conda environment, installs R + system dependencies, downloads the HyperQueue binary, and initialises the renv library.

## Running the cluster backend

[`hq_server.sh`](hq_server.sh) starts the HyperQueue server, registers a SLURM automatic allocator, and launches a Redis server. 
Once the server is up and Redis is reachable, run the experiments below. 

## Benchmarks

### rush

Uses [batchtools](https://mlr-org.com/batchtools) with the HyperQueue cluster functions. 
Each job starts a private Redis instance ([`rush/helper.R`](rush/helper.R)), builds a `RushWorker`, and times a single rush operation with [microbenchmark](https://cran.r-project.org/package=microbenchmark) across a grid of payload shapes (`n_parameters`, `payload_size`, `n_tasks`).

| Experiment | Operation benchmarked |
|------------|-----------------------|
| [`experiment_push_running_tasks.R`](rush/experiment_push_running_tasks.R) | `push_running_tasks()` — create tasks. |
| [`experiment_finish_tasks.R`](rush/experiment_finish_tasks.R) | `finish_tasks()` — write back results. |
| [`experiment_fetch_finished_tasks.R`](rush/experiment_fetch_finished_tasks.R) | `fetch_finished_tasks()` — read finished tasks. |
| [`experiment_fetch_finished_tasks_cache.R`](rush/experiment_fetch_finished_tasks_cache.R) | `fetch_finished_tasks()` with a warm local cache. |

### mbo

Tunes a [LightGBM](https://lightgbm.readthedocs.io) classifier (9 hyperparameters + internal `num_iterations`) on four OpenML classification tasks:

| OpenML task id | Dataset |
|----------------|---------|
| 31 | german-credit |
| 3945 | KDDCup09-appetency |
| 7592 | adult |
| 189354 | airlines |

Each task is optimized under a fixed wall-clock budget (`run_time`, 600 s) by three strategies, all sharing the same 100-point initial design (`mbo/initial_design.R`).

| Name in code | Label | Strategy |
|--------------|-------|----------|
| `cl_mbo` | **CLBO** | Synchronous multipoint **c**onstant-**l**iar batch MBO ([`bayesopt_mpcl.R`](mbo/source/bayesopt_mpcl.R)). |
| `central_mbo` | **ACBO** | **A**synchronous **c**entralized MBO — one process proposes, workers evaluate ([`OptimizerAsyncMboCentral.R`](mbo/source/OptimizerAsyncMboCentral.R)). |
| `async_mbo` | **ADBO** | **A**synchronous **d**ecentralized MBO — every worker runs its own MBO loop against a shared rush archive ([`OptimizerAsyncMbo.R`](mbo/source/OptimizerAsyncMbo.R)). |

## Results & analysis

## Layout

```
.
├── setup.sh              # conda + HyperQueue + renv bootstrap
├── hq_server.sh          # start HyperQueue server, SLURM allocator, Redis
├── hq_env.sh             # per-worker environment bootstrap
├── modules               # interactive shell env (PATH, aliases)
├── mbo/                  # distributed Bayesian optimization benchmark
│   ├── initial_design.R  # generate shared initial designs
│   ├── experiment.R      # CLBO vs ACBO vs ADBO driver
│   └── source/           # tuner / optimizer / loop-function implementations
├── rush/                 # rush core-operation micro-benchmarks
│   ├── run.R             # submit all four experiments
│   ├── helper.R          # per-job Redis bootstrap
│   └── results/          # reduced CSVs
├── renv/                 # pinned R library
└── attic/                # earlier / exploratory scripts
```
