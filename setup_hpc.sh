#!/bin/bash
set -euo pipefail

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

# install HyperQueue (hq) binary into the project
HQ_VERSION="0.26.2"
HQ_TARBALL="hq-v${HQ_VERSION}-linux-x64.tar.gz"
HQ_URL="https://github.com/It4innovations/hyperqueue/releases/download/v${HQ_VERSION}/${HQ_TARBALL}"
curl -fsSL -o "${HQ_TARBALL}" "${HQ_URL}"
tar -xzf "${HQ_TARBALL}"
rm -f "${HQ_TARBALL}"

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
  "rush@1.2.0",
  "microbenchmark",
  "mlr-org/batchtools",
  "mlr3mbo@1.2.1",
  "bbotk@1.12.0",
  "mlr3tuning@1.6.1",
  "mlr3oml",
  "ranger@0.18.0",
  "mlr3learners@0.15.0",
  "rgenoud",
  "DiceKriging",
  "mlr3@1.8.0",
  "rpart@4.1.27",
  "xgboost@3.2.1.1",
  "mlr-org/mlr3extralearners@v1.6.0",
  "lightgbm@4.6.0",
  "qs2"
)
EOF
