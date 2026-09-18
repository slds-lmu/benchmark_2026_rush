library(mlr3)
library(mlr3tuning)
library(mlr3oml)
library(mlr3mbo)
library(mirai)
library(rush)
library(mlr3extralearners)
library(mlr3misc)
library(R6)
library(checkmate)
library(data.table)
library(bbotk)
library(batchtools)

source("mbo/helper.R")

walk(list.files("mbo/source", full.names = TRUE), source)
dir.create("mbo/results", recursive = TRUE, showWarnings = FALSE)
dir.create("registries", showWarnings = FALSE)

n_workers = 448L
runtime = 600
n_repls = 5L
registry = "registries/mbo"

large_objects_path = Sys.getenv(
  "BENCHMARK_2026_RUSH_LARGE_OBJECTS",
  file.path(getwd(), "mbo", "rush_objects")
)
dir.create(large_objects_path, recursive = TRUE, showWarnings = FALSE)

mirai::daemons(0)
mirai::daemons(0, .compute = "mlr3_parallelization")

config = redux::redis_config(
  host = Sys.getenv("BENCHMARK_2026_RUSH_REDIS_HOST", Sys.info()[["nodename"]]),
  port = Sys.getenv("BENCHMARK_2026_RUSH_REDIS_PORT", "6379")
)

if (!redux::redis_available(config)) {
  stop("Redis is not available")
}

cl_mbo = function(task, learner, resampling, measure, terminator, initial_design, n_workers, ...) {
  instance = ti(
    task = task,
    learner = learner,
    resampling = resampling,
    measures = measure,
    terminator = terminator,
    store_benchmark_result = FALSE
  )

  xdt = initial_design[, instance$archive$cols_x, with = FALSE]
  ydt = initial_design[, instance$archive$cols_y, with = FALSE]
  instance$archive$add_evals(
    xdt         = xdt,
    xss_trafoed = transform_xdt_to_xss(xdt, instance$archive$search_space),
    ydt         = ydt
  )

  tuner = tnr(
    "mbo",
    loop_function = bayesopt_mpcl_rush,
    args = list(q = max(2, floor(n_workers / 10)))
  )

  tuner$optimize(instance)

  instance$archive$data
}


central_mbo = function(task, learner, resampling, measure, terminator, initial_design, n_workers, config, large_objects_path, ...) {
  rush::rush_plan(n_workers = n_workers, config = config, large_objects_path = large_objects_path)

  instance = ti_async(
    task = task,
    learner = learner,
    resampling = resampling,
    measures = measure,
    terminator = terminator,
    store_benchmark_result = FALSE
  )

  tuner = TunerAsyncMboCentral$new()

  xss = transpose_list(initial_design[, instance$archive$cols_x, with = FALSE])
  yss = transpose_list(initial_design[, instance$archive$cols_y, with = FALSE])
  instance$archive$push_finished_points(xss, yss)

  tuner$optimize(instance)


  instance$archive$data
}

async_mbo = function(task, learner, resampling, measure, terminator, initial_design, n_workers, config, large_objects_path, ...) {
  rush::rush_plan(n_workers = n_workers, config = config, large_objects_path = large_objects_path)

  instance = ti_async(
    task = task,
    learner = learner,
    resampling = resampling,
    measures = measure,
    terminator = terminator,
    store_benchmark_result = FALSE
  )

  tuner = TunerAsyncMbo_rush$new()

  xss = transpose_list(initial_design[, instance$archive$cols_x, with = FALSE])
  yss = transpose_list(initial_design[, instance$archive$cols_y, with = FALSE])
  instance$archive$push_finished_points(xss, yss)

  tuner$optimize(instance)

  instance$archive$data
}

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

  cells = as.data.table(expand.grid(
    algorithm = c("cl_mbo", "central_mbo", "async_mbo"),
    otask_id = otask_ids,
    repl = seq_len(n_repls),
    stringsAsFactors = FALSE
  ))

  batchMap(
    function(algorithm, otask_id, repl, n_workers, runtime, config, algorithms, large_objects_path) {
      renv::load(".")
      library(mlr3)
      library(mlr3tuning)
      library(mlr3oml)
      library(mlr3mbo)
      library(mirai)
      library(rush)
      library(mlr3extralearners)
      library(mlr3misc)
      library(R6)
      library(checkmate)
      library(data.table)
      library(bbotk)

      walk(list.files("mbo/source", full.names = TRUE), source)

      options(rush.max_object_size = 1)
      unlink(list.files(large_objects_path, pattern = "\\.rds$", full.names = TRUE))

      initial_design = as.data.table(readRDS(initial_design_file(otask_id, repl)))
      initial_design[, batch_nr := 1]

      # tuning instance
      otask = otsk(id = otask_id)
      task = as_task(otask)
      resampling = as_resampling(otask)
      measure = msr("classif.ce")
      terminator = trm("run_time", secs = runtime)

      learner = mbo_learner()

      profile = if (algorithm == "cl_mbo") "mlr3_parallelization" else NULL

      on.exit(stop_daemons(profile))

      start_daemons(n_workers, profile)

      mlr3misc::invoke(
        algorithms[[algorithm]],
        task = task,
        learner = learner,
        resampling = resampling,
        measure = measure,
        terminator = terminator,
        initial_design = initial_design,
        n_workers = n_workers,
        config = config,
        large_objects_path = large_objects_path
      )
    },
    args = cells,
    more.args = list(
      n_workers = n_workers,
      runtime = runtime,
      config = config,
      algorithms = list("cl_mbo" = cl_mbo, "central_mbo" = central_mbo, "async_mbo" = async_mbo),
      large_objects_path = large_objects_path
    ),
    reg = reg
  )

  reg
}

reg$cluster.functions = makeClusterFunctionsInteractive(external = TRUE)

# runs the cells one by one, each in its own R process
submitJobs(findNotDone(reg = reg), reg = reg)

# export the results
export_results(reg, function(cell) {
  sprintf("mbo/results/%s_%i_%i.rds", cell$algorithm, cell$otask_id, cell$repl)
})
