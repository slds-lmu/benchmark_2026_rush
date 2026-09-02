#!/bin/bash
set -euo pipefail

# Local (single-machine) counterpart of setup.sh.
# Same R stack, but no HyperQueue binary and no SLURM: the benchmarks in
# rush_local/ run through batchtools' interactive cluster functions.

# r-base 4.6.0 and redis-server come from conda-forge; the `defaults` channel has
# neither. --override-channels also keeps `defaults` out of the solve, so
# Anaconda's Terms of Service (which conda-forge does not carry) never apply.
CONDA_CHANNEL_ARGS=(--override-channels --channel conda-forge)

conda create -y -n benchmark_2026_rush "${CONDA_CHANNEL_ARGS[@]}"
eval "$(conda shell.bash hook)"
conda activate benchmark_2026_rush
conda install -y "${CONDA_CHANNEL_ARGS[@]}" r-base=4.6.0 redis-server libhiredis zlib libuv icu

# redux cannot find libhiredis without this
export PKG_CONFIG_PATH=$CONDA_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

# install R packages / set up renv
Rscript - <<'EOF'
options("install.opts" = "--without-keep.source")
options("renv.config.pak.enabled" = TRUE)

install.packages("renv")

renv::init(bare = TRUE)
renv::load(".")
install.packages("pak")

# this steps needs a github PAT
renv::install(
  "rush",
  "microbenchmark",
  "mlr-org/batchtools",
  "mlr3mbo",
  "bbotk",
  "mlr3tuning",
  "mlr3oml",
  "ranger",
  "mlr3learners",
  "rgenoud",
  "DiceKriging",
  "mlr3",
  "rpart",
  "mlr3learners",
  "xgboost",
  "mlr-org/mlr3extralearners",
  "lightgbm",
  "qs2"
)
EOF
