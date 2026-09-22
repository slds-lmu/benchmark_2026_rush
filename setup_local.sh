#!/bin/bash
set -euo pipefail

# Local (single-machine) counterpart of setup_hpc.sh.
# Same R stack, but no HyperQueue binary and no SLURM: the benchmarks in
# rush_local/ run through batchtools' interactive cluster functions.

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

# install R packages / set up renv
Rscript - <<'EOF'
options("install.opts" = "--without-keep.source")
# pak is deliberately left off. Its parallel downloader is unreliable behind the
# outbound proxy on the login node -- it aborts the whole install after failing
# ~100 downloads that plain curl fetches without trouble. renv's own installer
# is sequential and slower, but it understands the same pkg@version and
# user/repo@ref syntax and it completes.
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

  # Every dependency is pinned so that renv.lock is reproducible. CRAN packages by
  # version, GitHub packages by tag or commit. Identical list to setup_hpc.sh, so
  # both entry points produce the same renv.lock.
  #
  # batchtools comes from the main branch rather than a release: the
  # makeClusterFunctionsHyperQueue() used by rush/ is not part of any tag yet
  # (latest is v0.9.18 / CRAN 0.9.18), so the pin has to be a commit sha.
  pinned = c(
    "rush@1.3.0",
    "microbenchmark@1.5.0",
    "mlr-org/batchtools@ee7080fc31de21a88cf6d9bba61dbb51857d09c9",
    "mlr3@1.8.0",
    "mlr3mbo@1.2.1",
    "mlr3tuning@1.7.0",
    "mlr3learners@0.15.1",
    "mlr3oml@0.12.0",
    # The two hard dependencies of mlr3extralearners (it Imports both). mlr-org
    # ships them from GitHub rather than CRAN, so they are pinned to commits here
    # instead of being left to float; installing them up front keeps the
    # mlr3extralearners install below from having to resolve them.
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

  # mlr3extralearners' DESCRIPTION lists catboost under Remotes:
  # (catboost/catboost/catboost/R-package -- the R package buried inside the
  # 400 MB CatBoost monorepo). renv resolves every Remotes: entry, that one fails
  # to stage, and renv installs transactionally, so the single failure rolls back
  # every other package in the same call. catboost is only a Suggests and nothing
  # here touches it -- the sole extralearner the benchmark uses is
  # lrn("classif.lightgbm") -- so Remotes: is switched off for this one install.
  # Both hard dependencies (mlr3proba, mlr3cmprsk) are pinned above, and renv
  # still records the package as a pinned GitHub remote, so renv::restore()
  # reinstalls it from the sha.
  old = options(renv.config.install.remotes = FALSE)
  renv::install("mlr-org/mlr3extralearners@v1.6.0")
  options(old)
  stopifnot(requireNamespace("mlr3extralearners", quietly = TRUE))

  # Snapshot the pinned set explicitly instead of letting renv scan the sources:
  # DiceKriging, rgenoud, ranger, rpart, xgboost, lightgbm and qs2 are never
  # library()'d, they are reached through mlr3 string ids such as
  # lrn("classif.lightgbm"), so an implicit snapshot would leave them out of the
  # lockfile and renv::restore() would produce a library the benchmarks cannot run
  # on.
  # renv is added explicitly too: passing `packages` overrides renv's usual habit
  # of recording itself, and renv::restore() should reproduce the same renv.
  #
  # renv::status() will afterwards report the string-id packages as "recorded but
  # not used". That is the intended state, not a problem to clean up.
  packages = c(sub(".*/", "", sub("@.*", "", pinned)), "mlr3extralearners", "renv")
  renv::snapshot(packages = packages, prompt = FALSE)
}
EOF
