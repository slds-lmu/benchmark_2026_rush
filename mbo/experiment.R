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

lg = lgr::get_logger("mlr3/mlr3mbo")

walk(list.files("mbo/source", full.names = TRUE), source)

unlink("mbo/logs", recursive = TRUE)
dir.create("mbo/logs")

n_workers = 448L
local = TRUE
runtime = 600

initial_designs = readRDS("mbo/initial_designs.rds")

mirai::daemons(0)
mirai::daemons(0, .compute = "mlr3_parallelization")

config = if (local) {
  config = redux::redis_config()
  n_workers = 2
  runtime = 30
} else {
  config = redux::redis_config(
    host = "cm4login1",
    port = 6379
  )
}

if (!redux::redis_available(config)) {
  stop("Redis is not available")
}

otask_id = 31L
initial_design = initial_designs[[1]]
r = redux::hiredis(config)
r$FLUSHDB()


cl_mbo = function(task, learner, resampling, measure, terminator, initial_design, n_workers, ...) {
  instance = ti(
    task = task,
    learner = learner,
    resampling = resampling,
    measures = measure,
    terminator = terminator,
    store_benchmark_result = FALSE
  )

  tuner = tnr(
    "mbo",
    loop_function = bayesopt_mpcl_rush,
    initial_design = initial_design,
    args = list(q = max(2, floor(n_workers / 10)))
  )

  tuner$optimize(instance)

  instance$archive$data
}


central_mbo = function(task, learner, resampling, measure, terminator, initial_design, n_workers, config, ...) {
  rush::rush_plan(n_workers = n_workers, config = config)

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

async_mbo = function(task, learner, resampling, measure, terminator, initial_design, n_workers, config, ...) {
  rush::rush_plan(n_workers = n_workers, config = config)

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

results = pmap(
  list(otask_id = c(31L, 3945L, 7592L, 189354L), initial_design = initial_designs),
  function(otask_id, initial_design) {
    data.table::setDT(initial_design)
    initial_design[, batch_nr := 1]

    # tuning instance
    otask = otsk(id = otask_id)
    task = as_task(otask)
    resampling = as_resampling(otask)
    measure = msr("classif.ce")
    terminator = trm("run_time", secs = runtime)

    learner = set_validate(
      lrn(
        "classif.lightgbm",
        early_stopping_rounds = 100,
        learning_rate = to_tune(1e-3, 1, logscale = TRUE),
        feature_fraction = to_tune(0.1, 1),
        min_data_in_leaf = to_tune(1, 200),
        num_leaves = to_tune(10, 255),
        extra_trees = to_tune(),
        #bagging_fraction  = to_tune(0, 1),
        #bagging_freq      = to_tune(0, 10),
        lambda_l1 = to_tune(1e-3, 1e3, logscale = TRUE),
        lambda_l2 = to_tune(1e-3, 1e3, logscale = TRUE),
        min_gain_to_split = to_tune(1e-3, 0.1, logscale = TRUE),
        num_iterations = to_tune(1, 5000, internal = TRUE),
        eval = "binary_error"
      ),
      "test"
    )

    mlr3misc::imap(
      list("cl_mbo" = cl_mbo, "central_mbo" = central_mbo, "async_mbo" = async_mbo),
      function(algorithm, name) {
        profile = if (name %in% c("cl_mbo", "batch_mbo")) "mlr3_parallelization" else NULL
        daemons(0, .compute = profile)

        file = file(sprintf("logs/%s_%i.log", name, otask_id), open = "wt")
        sink(file)
        sink(file, type = "message")

        log_dir = "mbo/logs"
        if (local) {
          daemons(n_workers, .compute = profile)
        } else {
          daemons(
            n = n_workers,
            url = host_url(port = 5554),
            .compute = profile,
            remote = remote_config(
              command = "hq",
              args = c(
                "submit",
                "--cpus",
                "1",
                # "--stdout", file.path(log_dir, "stdout-%{JOB_ID}-%{TASK_ID}.txt"),
                # "--stderr ", file.path(log_dir, "stderr-%{JOB_ID}-%{TASK_ID}.txt"),
                "--stdout=none",
                "--stderr=none",
                "--",
                "."
              ),
              quote = FALSE
            )
          )
        }

        Sys.sleep(2)

        while (mirai::status(.compute = profile)$connections < n_workers) {
          Sys.sleep(10)
          mlr3misc::messagef(
            "Waiting for workers to connect... %i/%i",
            mirai::status(.compute = profile)$connections,
            n_workers
          )
        }

        archive = mlr3misc::invoke(
          algorithm,
          task = task,
          learner = learner,
          resampling = resampling,
          measure = measure,
          terminator = terminator,
          initial_design = initial_design,
          n_workers = n_workers,
          config = config
        )

        mirai::daemons(0, .compute = profile)
        sink(NULL)
        sink(NULL, type = "message")

        archive
      }
    )
  }
)

saveRDS(results, "results.rds")
