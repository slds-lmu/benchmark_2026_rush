# Benchmark 2026 rush

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21135663.svg)](https://doi.org/10.5281/zenodo.21135663)

Benchmark suite for the `rush` [paper](https://arxiv.org/abs/2606.21430).
Experiments are designed to run at HPC scale (hundreds of workers) on a SLURM cluster via [HyperQueue](https://it4innovations.github.io/hyperqueue/).

The suite has two independent parts:

| Directory        | What it measures                                                                                     |
|------------------|------------------------------------------------------------------------------------------------------|
| [`rush/`](rush/) | Micro-benchmarks of rush's core Redis operations under varying load.                                 |
| [`mbo/`](mbo/)   | Comparison of three distributed model-based optimization (MBO) strategies for hyperparameter tuning. |
| [`rush_local/`](rush_local/) | The `rush/` micro-benchmarks, run locally instead of on a cluster (see [Running locally](#running-locally)). |

## Requirements

The full stack targets a Linux HPC login/compute environment:

- conda — provides `r-base` (4.6.0), `redis-server`, `libhiredis`, and supporting libraries.
- renv — pins the R package library.
- HyperQueue (`hq`, v0.26.2) — meta-scheduler that submits work to SLURM. 
  Installed into the project root by `setup_hpc.sh`.
- SLURM — HPC job scheduler that HyperQueue submits to.
- Redis — shared key–value store that rush workers coordinate through.

## Runbook

How to reproduce a full HPC run from a fresh clone.
Run all commands from the repository root on a login node, using Bash.
The project directory must be accessible at the same path on every compute node.
The sections below explain each step.

```sh
# 0. Make conda available on LRZ systems.
#    On other systems e.g. `module load conda`.
source ~/.conda_init

# 1. Setup conda environment, `hq` binary, R library from renv.lock.
./setup_hpc.sh

# 2. Activate the conda environment and add hq to the PATH.
conda activate benchmark_2026_rush
export PATH="$PWD:$PATH"

# 3. Adapt hq_workers.sh and hq_env.sh to the site.

# 4. Bring up the backend.
#    Use separate tmux panes.
./hq_server.sh
./hq_workers.sh
./redis_server.sh

# 5. Run the benchmarks.
#    Keep this in tmux as well.
Rscript run_all.R

# 6. Wait for all four rush registries to finish before aggregation.
#    Then aggregate into the CSV files.
Rscript -e 'source("rush/results.R")'
Rscript -e 'source("mbo/results.R")'

# 7. Tear the backend down.
./hq_clean.sh
```

### Site-specific settings

What to check when moving the suite to another cluster. 
The MBO scripts request 448 workers regardless of the SLURM allocation; provide at least that many CPUs.

| Where                          | Setting                                   | Value here                                 | What to check                                                                                                |
|--------------------------------|-------------------------------------------|--------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| `hq_env.sh`                    | Slurm + conda init on the *compute* nodes | `module load slurm_setup`, `~/.conda_init` |                                                                                                              |
| `hq_workers.sh`, `hq_clean.sh` | `SLURM_CLUSTERS`                          | `cm4`                                      | Only needed where the login node's default cluster is the wrong one. Drop the line on a single-cluster site. |
| `hq_workers.sh`                | `--partition`, `--qos`                    | `cm4_std`                                  | Must permit a multi-node job. A tiny or single-node partition cannot run this.                               |
| `hq_workers.sh`                | `N_NODES`, `CPUS_PER_NODE`                | 4 × 112                                    | The product must be at least 448.                                                                            |
| `hq_workers.sh`                | `--time`                                  | `24:00:00`                                 | The worker `--time-limit` inside `WORKER_CMD`.                                                               |

### Configuration

Paths and hosts that depend on the site are read from the environment, with defaults that work in a fresh clone:

| Variable                            | Default                      | Meaning                                                                                                                                                     |
|-------------------------------------|------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `BENCHMARK_2026_RUSH_REDIS_HOST`    | this node's hostname         | Host of the shared Redis used by `mbo/`. Defaulting to `Sys.info()[["nodename"]]` is correct as long as R and `redis_server.sh` run on the same login node. |
| `BENCHMARK_2026_RUSH_REDIS_PORT`    | `6379`                       | Port of that Redis. Set the matching `--port` in `redis_server.sh`.                                                                                         |
| `BENCHMARK_2026_RUSH_LARGE_OBJECTS` | `<project>/mbo/rush_objects` | Shared directory for large rush objects. All compute nodes must be able to read and write it at the same absolute path.                                     |

## Benchmarks

### rush

Each job starts a private Redis instance (`rush/helper.R`), builds a `RushWorker`, and times a single rush operation with `microbenchmark` across a grid of payload shapes (`n_parameters`, `payload_size`, `n_tasks`).

| Experiment                                | Operation benchmarked                           |
|-------------------------------------------|-------------------------------------------------|
| `experiment_push_running_tasks.R`         | `push_running_tasks()` — create tasks.          |
| `experiment_finish_tasks.R`               | `finish_tasks()` — write back results.          |
| `experiment_fetch_finished_tasks.R`       | `fetch_finished_tasks()` — read finished tasks. |
| `experiment_fetch_finished_tasks_cache.R` | `fetch_finished_tasks()` with local cache.      |

Results are collected in `rush/results/`.

### mbo

Tunes a `LightGBM` classifier (8 search-space hyperparameters plus internally tuned boosting iterations) on four OpenML classification tasks:

| OpenML task id | Dataset            |
|----------------|--------------------|
| 31             | german-credit      |
| 3945           | KDDCup09-appetency |
| 7592           | adult              |
| 189354         | airlines           |

Each task is optimized with a wall-clock termination budget of 10 minutes by three strategies, all sharing the same 100-point initial design (`mbo/initial_design.R`).
The whole grid is replicated 5 times.

| Name in code  | Strategy                                                                                                                 |
|---------------|--------------------------------------------------------------------------------------------------------------------------|
| `cl_mbo`      | Synchronous multipoint constant-liar batch MBO `bayesopt_mpcl.R`.                                                        |
| `central_mbo` | Asynchronous centralized MBO — one process proposes, workers evaluate asynchronously `OptimizerAsyncMboCentral.R`.       |
| `async_mbo`   | Asynchronous decentralized MBO — every worker runs its own MBO loop against a shared rush archive `OptimizerAsyncMbo.R`. |

`mbo/experiment.R` runs all task/strategy combinations. 
Results are collected in `mbo/results/`.

## Reproducibility

`renv.lock` pins R packages and the setup scripts pin direct conda dependencies.
All batchtools registries use `seed = 7832`, seeding payloads and initial designs.
MBO results vary with worker randomness and asynchronous execution.
Compare the five replications using `aggregated_mean.csv` and see `aggregated.csv` for individual runs.

## Running locally

`setup_local.sh` is the single-machine counterpart of `setup_hpc.sh`.

[`rush_local/`](rush_local/) mirrors [`rush/`](rush/) with batchtools'.
The jobs of the parameter grid run sequentially, each in its own R process on the local machine.
Registries are written to `registries/rush_local/` and results to `rush_local/results/`.

```sh
./setup_local.sh
conda activate benchmark_2026_rush
Rscript rush_local/run_all.R
Rscript rush_local/results.R
```
