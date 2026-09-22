# Benchmark 2026 rush

[![DOI](https://zenodo.org/badge/1155470781.svg)](https://doi.org/10.5281/zenodo.21135663)

Benchmark suite for the `rush` [paper](https://arxiv.org/abs/2606.21430).
Experiments are designed to run at HPC scale (hundreds of workers) on a SLURM cluster via [HyperQueue](https://it4innovations.github.io/hyperqueue/).

The suite has two independent parts:

| Directory        | What it measures                                                                                     |
|------------------|------------------------------------------------------------------------------------------------------|
| [`rush/`](rush/) | Micro-benchmarks of rush's core Redis operations under varying load.                                 |
| [`mbo/`](mbo/)   | Comparison of three distributed model-based optimization (MBO) strategies for hyperparameter tuning. |
| [`rush_local/`](rush_local/) | The `rush/` micro-benchmarks, run locally instead of on a cluster (see [Running locally](#running-locally)). |

## Runbook

How to reproduce a full HPC run from a fresh clone. 
Work through it top to bottom on a login node. 
The sections below explain each step.

```sh
# 0. Make conda available on LRZ systems.
#    On other systems e.g. `module load conda`.
source ~/.conda_init

# 1. Setup conda environment, `hq` binary, R library from renv.lock.
./setup_hpc.sh

# 2. Activate the conda environment and add hq to the PATH.
conda activate benchmark_2026_rush
export PATH="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd):$PATH"

# 3. Adapt hq_workers.sh and hq_env.sh to the site.

# 4. Bring up the backend. 
#    Keep this in tmux. 
./hq_server.sh
./hq_workers.sh
./redis_server.sh

# 5. Run the benchmarks.
#    Keep this in tmux as well.
Rscript run_all.R

# 6. Aggregate into the csv files.
Rscript -e 'source("rush/results.R")'
Rscript -e 'source("mbo/results.R")'

# 7. Tear the backend down.
./hq_clean.sh
```

### Site-specific settings

What to check when moving the suite to another cluster. Only
`N_NODES` × `CPUS_PER_NODE` changes the benchmark itself, the rest is plumbing.

| Where                          | Setting                                   | Value here                                 | What to check                                                                                                |
|--------------------------------|-------------------------------------------|--------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| `hq_env.sh`                    | Slurm + conda init on the *compute* nodes | `module load slurm_setup`, `~/.conda_init` |                                                                                                              |
| `hq_workers.sh`, `hq_clean.sh` | `SLURM_CLUSTERS`                          | `cm4`                                      | Only needed where the login node's default cluster is the wrong one. Drop the line on a single-cluster site. |
| `hq_workers.sh`                | `--partition`, `--qos`                    | `cm4_std`                                  | Must permit a multi-node job. A tiny or single-node partition cannot run this.                               |
| `hq_workers.sh`                | `N_NODES`, `CPUS_PER_NODE`                | 4 × 112                                    | The product must be at least 448.                                                                            |
| `hq_workers.sh`                | `--time`                                  | `24:00:00`                                 | The worker `--time-limit` inside `WORKER_CMD`.                                                               |

## Requirements

The full stack targets a Linux HPC login/compute environment:

- conda — provides `r-base` (4.6.0), `redis-server`, `libhiredis`, and supporting libraries.
- renv — pins the R package library.
- HyperQueue (`hq`, v0.26.2) — meta-scheduler that submits work to SLURM. 
Installed into the project root by `setup_hpc.sh`.
- SLURM — HPC job scheduler that HyperQueue submits to.
- Redis — shared key–value store that rush workers coordinate through.

## Setup

The setup depends on the HPC environment. 
The `setup_hpc.sh` script is a convenience wrapper that creates/activates a conda environment, installs R + system dependencies, downloads the HyperQueue binary, and initializes the renv library.
Re-running it on an existing conda environment is safe.

Every dependency is pinned: conda packages to an exact version, CRAN packages to an exact version, and the two GitHub packages to a tag (`mlr3extralearners`) or a commit (`batchtools`, whose `makeClusterFunctionsHyperQueue()` is not in a release yet).
`renv.lock` records the resulting library, and a clone installs from that lockfile. When `renv.lock` exists, both setup scripts run

```r
renv::restore()
```

Needs a `GITHUB_PAT` in `~/.Renviron` for the GitHub packages.

`renv::status()` reports `DiceKriging`, `lightgbm`, `mlr3learners`, `qs2`, `rgenoud` and `xgboost` as "recorded but not used". That is deliberate: they are never `library()`-ed, only reached through mlr3 string ids such as `lrn("classif.lightgbm")`, so renv's dependency scan cannot see them and the setup scripts snapshot them by name instead. Removing them from `renv.lock` would break the benchmarks.

### Configuration

Paths and hosts that depend on the site are read from the environment, with defaults that work in a fresh clone:

| Variable | Default | Meaning |
|----------|---------|---------|
| `BENCHMARK_2026_RUSH_REDIS_HOST` | this node's hostname | Host of the shared Redis used by `mbo/`. The rush workers on the compute nodes resolve it, so it must be the login node running `redis_server.sh` — never a loopback address. Defaulting to `Sys.info()[["nodename"]]` is correct as long as R and `redis_server.sh` run on the same login node. |
| `BENCHMARK_2026_RUSH_REDIS_PORT` | `6379` | Port of that Redis. |

## Running the cluster backend

`hq_server.sh` starts the HyperQueue server, `hq_workers.sh` submits its workers, and `redis_server.sh` starts a Redis server.
`hq_clean.sh` tears all of it down again.

The workers are submitted as a *single* multi-node SLURM job rather than through HyperQueue's automatic allocator.
`mbo/initial_design.R` blocks until all 448 of its mirai daemons have connected, and SLURM allocates a job atomically, so one 4-node job brings every worker up at the same moment; four 1-node jobs would be scheduled independently and trickle in.
`hq_workers.sh` documents the two ways the allocator actively breaks here.

This also means the workers run in the `cm4_std` partition (`MinNodes=2`, `MaxNodes=4`) instead of `cm4_tiny`, which caps a job at a single node.

Once the server is up, the workers are queued and Redis is reachable, run the experiments below.

## Running locally

`setup_local.sh` is the single-machine counterpart of `setup_hpc.sh`: same conda environment and renv library, but no HyperQueue binary and no SLURM.

[`rush_local/`](rush_local/) mirrors [`rush/`](rush/) with batchtools' `makeClusterFunctionsInteractive(external = TRUE)`, so the jobs of the parameter grid run sequentially, each in its own R process on the local machine.
Registries are written to `registries/rush_local/` and results to `rush_local/results/`.

```r
source("rush_local/run_all.R")      # runs all four experiments
source("rush_local/results.R")  # writes the csv files
```

`redis-server` must be on the `PATH`; each job starts its own instance on a unix socket (`rush_local/helper.R`).
The parameter grid and the `microbenchmark` repetition counts are identical to the HPC version, so a full local run takes considerably longer than the distributed one.

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
The whole grid is replicated 5 times (`n_repls` in both scripts): `mbo/initial_design.R` draws one initial design per replication and task (20 designs), and each of the twelve task/strategy combinations is run once per replication (60 runs).

| Name in code  | Strategy                                                                                                                 |
|---------------|--------------------------------------------------------------------------------------------------------------------------|
| `cl_mbo`      | Synchronous multipoint constant-liar batch MBO `bayesopt_mpcl.R`.                                                        |
| `central_mbo` | Asynchronous centralized MBO — one process proposes, workers evaluate asynchronously `OptimizerAsyncMboCentral.R`.       |
| `async_mbo`   | Asynchronous decentralized MBO — every worker runs its own MBO loop against a shared rush archive `OptimizerAsyncMbo.R`. |

`mbo/experiment.R` runs all twelve task/strategy combinations per replication and writes the raw archive of every single run to its own file, `mbo/results/<strategy>_<task_id>_<repl>.rds` (60 files for 5 replications); `mbo/results.R` reads whichever of those files exist, recovering strategy, task and replication from the filename, and aggregates them into `mbo/results/aggregated.csv` (one row per replication/task/strategy) and `mbo/results/aggregated_mean.csv` (the same measures averaged over replications, with a `repls` column counting how many went into each mean). Because the aggregation works off whatever is on disk, it can be run while the benchmark is still going.
Both scripts drive their cells through a batchtools registry — `registries/initial_design` (20 jobs, one per task/replication) and `registries/mbo` (60 jobs, one per strategy/task/replication) — with `makeClusterFunctionsInteractive(external = TRUE)`, so every cell runs one at a time in its own R process. The registry is the job ledger: status, a per-job log, and a recorded result. The job function returns the archive, and at the end of each script `export_results()` writes every *finished* job to the `.rds` files above, which is what makes a crash cost at most the cell that was in flight.

A cell runs in a fresh process, so leaked mirai daemons or a 2 GB surrogate cannot reach the next cell. It also means the job function has to bring its own world: `renv::load(".")`, its `library()` calls, and `walk(list.files("mbo/source"), source)` for the optimizer classes. `mbo/helper.R` carries what both registries share (`otask_ids`, `mbo_learner()`, `cell_seed()`, `initial_design_file()`, `start_daemons()`/`stop_daemons()`, `export_results()`, and the global `lg` that `OptimizerAsyncMboCentral.R` and `bayesopt_mpcl.R` log through); batchtools `sys.source()`s it into the `.GlobalEnv` of every job process via `makeRegistry(source = ...)`.

Logging is batchtools': each job's process writes stdout, `message()` and the lgr output of `mlr3`/`bbotk` to its own file under `registries/<name>/logs/`, so the scripts no longer `sink()` into `mbo/logs/`. Read a finished cell with `getLog(id)`. While a cell is still running the submitting session is blocked inside `submitJobs()`, so watch it from the shell instead:

```sh
tail -f $(ls -t registries/mbo/logs/*.log | head -1)
```

Both registries are created only if missing, so re-sourcing either script resumes rather than wipes. To operate a run:

```r
submitJobs(findNotDone())   # what both scripts end with; resumes after a crash
getStatus(); getJobTable()  # progress
getErrorMessages()          # why a cell failed
getLog(id)                  # that cell's output
resetJobs(id); submitJobs(id)   # rerun one cell
```

`submitJobs()` blocks for the whole run, so keep it in tmux. Changing `n_repls` does not add jobs to an existing registry — delete the registry directory to rebuild the job table.
At 60 runs of 10 minutes plus daemon start-up, budget upwards of 12 h for `mbo/experiment.R` alone — more than the 24 h worker walltime leaves room for once the initial designs are counted too, so expect to resubmit `hq_workers.sh` partway through and pick up with `submitJobs(findNotDone())`. The `--idle-timeout 2h` of `hq_workers.sh` is what keeps the workers alive between runs.

Note that `start_daemons()` waits for all 448 daemons without a timeout, because HyperQueue start-up time is not predictable. A cell that can never reach 448 — a lost HQ worker, cpus still held by orphaned daemons — therefore blocks the queue rather than failing: interrupt it, `hq job cancel all`, then `submitJobs(findNotDone())`.

Both scripts run against the *same* HyperQueue workers, so only one SLURM queue wait is paid for the whole `mbo/` run:

```r
source("mbo/initial_design.R")   # 20 jobs, exports mbo/results/initial_design_<task_id>_<repl>.rds
source("mbo/experiment.R")       # 60 jobs, same workers, no new SLURM job
```

The workers belong to the SLURM job submitted by `hq_workers.sh`, not to the R session, and they outlive both scripts.
What does not outlive them are the 448 mirai daemons: each is a HyperQueue *task* holding one worker cpu, so a script that exits without calling `daemons(0)` leaves all 448 cpus occupied and the next script waits forever for its own daemons to be scheduled.
Both scripts therefore shut their daemons down via the `on.exit()` in their job function, on the error path as well as the normal one.

Do not run `hq_clean.sh` between the two — it cancels the worker job.
Mind the two limits in `hq_workers.sh` as well: the workers stop after `--idle-timeout 2h` of no work, and the job ends at its 24 h walltime.

## Reproducibility

The R library is pinned by `renv.lock` (see [Setup](#setup)); the conda layer (`r-base`, `redis-server` and the libraries `redux`/`lightgbm` link against) is pinned to exact versions in the setup scripts.

Seeding:

- Seeding is batchtools' throughout: every registry is created with `seed = 7832`, and batchtools sets each job's seed to `reg$seed + job.id` before the job function runs. No script calls `set.seed()` itself.
- `rush/` and `rush_local/` are therefore fully seeded. Both variants build the same job table from the same `CJ()`, so a given `job.id` draws the same seed in both, and the benchmarked `xss`/`yss` stay byte-identical across runs, across a rerun of a single job, and across the HPC and local variants. Only the measured timings vary.
- `mbo/initial_design.R` gets one seed per job, i.e. per (task, replication) cell, which fixes the 100-point random-search design shared by all three strategies in that cell. Because the seed follows `job.id` rather than the clock, `submitJobs()` on a single cell regenerates exactly that design without re-running the others. It writes one `mbo/results/initial_design_<task_id>_<repl>.rds` per cell (20 files for 5 replications), the input to `mbo/experiment.R`, which refuses to start unless all of them are present and names the missing ones. Note that the committed `mbo/initial_designs.rds` predates the seeding *and* the replications, so it holds a single un-replicated design in the old combined format; re-running `mbo/initial_design.R` produces a *different* (but from then on reproducible) set of designs.
- `mbo/experiment.R` is seeded the same way, per (strategy, task, replication) job, but **the MBO runs are not bit-reproducible**, and cannot be made so. All three strategies terminate on a 10-minute wall-clock budget, so the number of evaluations depends on how fast the machine is; `rush_plan()` has no seed argument, so the RNG streams of the rush workers in `central_mbo` and `async_mbo` are not controlled; and asynchronous proposals depend on the order in which workers report back. The seed fixes the controller-side draws (surrogate fits, acquisition-optimizer starts, random interleaving), which is what makes `cl_mbo` repeatable up to the time budget.

Expect the `mbo/` numbers to reproduce as a trend, not to the digit — which is what the 5 replications are for: read `aggregated_mean.csv` for the comparison and `aggregated.csv` for the spread across replications.
