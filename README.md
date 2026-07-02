# Benchmark 2026 rush

Benchmark suite for the `rush` [paper](https://arxiv.org/abs/2606.21430v1).
Experiments are designed to run at HPC scale (hundreds of workers) on a SLURM cluster via [HyperQueue](https://it4innovations.github.io/hyperqueue/).

The suite has two independent parts:

| Directory        | What it measures                                                                                     |
|------------------|------------------------------------------------------------------------------------------------------|
| [`rush/`](rush/) | Micro-benchmarks of rush's core Redis operations under varying load.                                 |
| [`mbo/`](mbo/)   | Comparison of three distributed model-based optimization (MBO) strategies for hyperparameter tuning. |

## Requirements

The full stack targets a Linux HPC login/compute environment:

- conda — provides `r-base` (4.6.0), `redis-server`, `libhiredis`, and supporting libraries.
- renv — pins the R package library.
- HyperQueue (`hq`, v0.26.2) — meta-scheduler that submits work to SLURM. 
Installed into the project root by `setup.sh`.
- SLURM — HPC job scheduler that HyperQueue submits to.
- Redis — shared key–value store that rush workers coordinate through.

## Setup

The setup depends on the HPC environment. 
The `setup.sh` script is a convenience wrapper that creates/activates a conda environment, installs R + system dependencies, downloads the HyperQueue binary, and initializes the renv library.

## Running the cluster backend

`hq_server.sh` starts the HyperQueue server and registers a SLURM automatic allocator.
`redis_server.sh` starts a Redis server.

Once the server is up and Redis is reachable, run the experiments below. 

## Benchmarks

### rush

Uses [batchtools](https://mlr-org.com/batchtools) with the HyperQueue cluster functions. 
Each job starts a private Redis instance (`rush/helper.R`), builds a `RushWorker`, and times a single rush operation with `microbenchmark` across a grid of payload shapes (`n_parameters`, `payload_size`, `n_tasks`).

| Experiment                                | Operation benchmarked                           |
|-------------------------------------------|-------------------------------------------------|
| `experiment_push_running_tasks.R`         | `push_running_tasks()` — create tasks.          |
| `experiment_finish_tasks.R`               | `finish_tasks()` — write back results.          |
| `experiment_fetch_finished_tasks.R`       | `fetch_finished_tasks()` — read finished tasks. |
| `experiment_fetch_finished_tasks_cache.R` | `fetch_finished_tasks()` with local cache.      |

Results are collected in `rush/results/`.

### mbo

Tunes a `LightGBM` classifier (9 hyperparameters) on four OpenML classification tasks:

| OpenML task id | Dataset            |
|----------------|--------------------|
| 31             | german-credit      |
| 3945           | KDDCup09-appetency |
| 7592           | adult              |
| 189354         | airlines           |

Each task is optimized under a fixed wall-clock budget of 10 minutes by three strategies, all sharing the same 100-point initial design (`mbo/initial_design.R`).

| Name in code  | Strategy                                                                                                                 |
|---------------|--------------------------------------------------------------------------------------------------------------------------|
| `cl_mbo`      | Synchronous multipoint constant-liar batch MBO `bayesopt_mpcl.R`.                                                        |
| `central_mbo` | Asynchronous centralized MBO — one process proposes, workers evaluate asynchronously `OptimizerAsyncMboCentral.R`.       |
| `async_mbo`   | Asynchronous decentralized MBO — every worker runs its own MBO loop against a shared rush archive `OptimizerAsyncMbo.R`. |

Results are collected in `mbo/results/results.R` and aggregated in `mbo/results/aggregated.csv`.