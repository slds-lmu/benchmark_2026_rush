library(batchtools)
library(data.table)
library(mlr3misc)

source("mbo/helper.R")

n_workers = 448L
n_repls = 5L
registry = "registries/initial_design"

dir.create("mbo/results", recursive = TRUE, showWarnings = FALSE)
dir.create("registries", showWarnings = FALSE)


reg = if (dir.exists(registry)) {
  loadRegistry(registry, writeable = TRUE)
} else {
  reg = makeRegistry(
    file.dir = registry,
    conf.file = NA,
    seed = 7832,
    packages = "renv",
    source = "mbo/helper.R"
  )

  batchMap(
    function(otask_id, repl, n_workers) {
      renv::load(".")
      library(mlr3)
      library(mlr3tuning)
      library(mlr3oml)
      library(mlr3mbo)
      library(mirai)
      library(rush)
      library(mlr3extralearners)
      library(mlr3misc)

      # tuning instance
      otask = otsk(id = otask_id)
      task = as_task(otask)
      resampling = as_resampling(otask)
      measure = msr("classif.ce")
      terminator = trm("evals", n_evals = 100)

      learner = mbo_learner()

      on.exit(stop_daemons("mlr3_parallelization"))

      start_daemons(n_workers, "mlr3_parallelization")

      instance = ti(
        task = task,
        learner = learner,
        resampling = resampling,
        measures = measure,
        terminator = terminator,
        store_benchmark_result = FALSE
      )

      tuner = tnr("random_search", batch_size = 100L)

      tuner$optimize(instance)

      instance$archive$data[, c(instance$archive$cols_x, instance$archive$cols_y), with = FALSE]
    },
    args = as.data.table(expand.grid(otask_id = otask_ids, repl = seq_len(n_repls))),
    more.args = list(n_workers = n_workers),
    reg = reg
  )

  reg
}

reg$cluster.functions = makeClusterFunctionsInteractive(external = TRUE)

# runs the cells one by one, each in its own R process
submitJobs(findNotDone(reg = reg), reg = reg)

# export the designs
export_results(reg, function(cell) initial_design_file(cell$otask_id, cell$repl))
