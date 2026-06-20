#!/bin/bash
set -euo pipefail

# conda create -y -n benchmark_2026_rush
conda activate benchmark_2026_rush
# conda install -y r-base=4.6.0 redis-server libhiredis zlib libuv icu

#  libpng r-igraph

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

#install.packages("renv")

renv::init(bare = TRUE)
renv::load(".")
#install.packages("pak")

# this steps needs a github PAT
renv::install(
  "mlr-org/rush",
  "microbenchmark",
  "mlr-org/batchtools"
  # "mlr-org/mlr3mbo@cmbo",
  # "mlr-org/bbotk",
  # "mlr-org/mlr3tuning",
  # "mlr3oml",
  # "ranger",
  # "mlr3learners",
  # "rgenoud",
  # "DiceKriging",
  # "mlr3",
  # "rpart",
  # "mlr3learners",
  # "xgboost",
  # "mlr-org/mlr3extralearners",
  # "lightgbm",
  # "qs2"
)
EOF
