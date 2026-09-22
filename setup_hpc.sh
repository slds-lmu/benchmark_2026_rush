#!/bin/bash
set -euo pipefail

# r-base 4.6.0 and redis-server come from conda-forge; the `defaults` channel has
# neither. --override-channels also keeps `defaults` out of the solve, so
# Anaconda's Terms of Service (which conda-forge does not carry) never apply.
CONDA_CHANNEL_ARGS=(--override-channels --channel conda-forge)
CONDA_ENV="benchmark_2026_rush"

# idempotent: re-running the script must not abort on an existing prefix
if ! conda env list | grep -qE "^${CONDA_ENV}[[:space:]]"; then
  conda create -y -n "${CONDA_ENV}" "${CONDA_CHANNEL_ARGS[@]}"
fi
eval "$(conda shell.bash hook)"
conda activate "${CONDA_ENV}"
conda install -y "${CONDA_CHANNEL_ARGS[@]}" \
  r-base=4.6.0 \
  redis-server=8.10.1 \
  libhiredis=1.3.0 \
  zlib=1.3.2 \
  libuv=1.52.1 \
  icu=78.3 \
  libcurl=8.22.0 \
  cmake=4.4.3

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
options("renv.config.pak.enabled" = FALSE)

if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")

# build the R package library using the renv-lock file.
# if no renv.lock exists, the else branch will create one from scratch.
if (file.exists("renv.lock")) {
  renv::load(".")
  renv::restore(prompt = FALSE)
} else {
  renv::init(bare = TRUE)
  renv::load(".")

  pinned = c(
    "rush@1.3.0",
    "microbenchmark@1.5.0",
    "mlr-org/batchtools@ee7080fc31de21a88cf6d9bba61dbb51857d09c9",
    "mlr3@1.8.0",
    "mlr3mbo@1.2.1",
    "mlr3tuning@1.7.0",
    "mlr3learners@0.15.1",
    "mlr3oml@0.12.0",
    "mlr-org/mlr3proba@327d0503b40b9373caa24d0326c1f8b2a5356415",
    "mlr-org/mlr3cmprsk@de51006a1e417469a34d365763b201110e2966cf",
    "bbotk@1.13.0",
    "mirai@2.7.2",
    "DiceKriging@1.6.1",
    "rgenoud@5.9-0.11",
    "ranger@0.18.0",
    "rpart@4.1.27",
    "xgboost@3.2.1.1",
    "lightgbm@4.7.0",
    "qs2@0.3.1",
    "ggplot2@4.0.3"
  )

  # this steps needs a github PAT
  renv::install(pinned)

  # renv cannot handle catboost in mlr3extralearners
  old = options(renv.config.install.remotes = FALSE)
  renv::install("mlr-org/mlr3extralearners@v1.6.0")
  options(old)

  renv::settings$snapshot.type("all")
  renv::snapshot(prompt = FALSE)
}
EOF
