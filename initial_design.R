library(mlr3)
library(mlr3tuning)
library(mlr3oml)
library(mlr3mbo)
library(mirai)
library(rush)
library(mlr3extralearners)
library(mlr3misc)

n_workers = 448L
local = FALSE

#  31L credit g
#  3945L KDDCup09_appetency
#  7592L Adult
#  189354L Airlines

initial_designs = set_names(map(c(31L, 3945L, 7592L, 189354L), function(otask_id) { # 3L, 7592L, 189354L  # 31L, 3945L, 7592L, 189354L

  # tuning instance
  otask = otsk(id = otask_id)
  task = as_task(otask)
  resampling = as_resampling(otask)
  measure = msr("classif.ce")
  terminator = trm("evals", n_evals = 100)

  learner = set_validate(lrn("classif.lightgbm",
    early_stopping_rounds = 100,
    learning_rate     = to_tune(1e-3, 1, logscale = TRUE),
    feature_fraction  = to_tune(0.1, 1),
    min_data_in_leaf  = to_tune(1, 200),
    num_leaves        = to_tune(10, 255),
    extra_trees       = to_tune(),
    #bagging_fraction  = to_tune(0, 1),
    #bagging_freq      = to_tune(0, 10),
    lambda_l1         = to_tune(1e-3, 1e3, logscale = TRUE),
    lambda_l2         = to_tune(1e-3, 1e3, logscale = TRUE),
    min_gain_to_split = to_tune(1e-3, 0.1, logscale = TRUE),
    num_iterations    = to_tune(1, 5000, internal = TRUE),
    eval       = "binary_error"
  ), "test")

  daemons(0, .compute =  "mlr3_parallelization")

  file = file(sprintf("logs/initial_design_%i.log", otask_id), open = "wt")
  sink(file)
  sink(file, type = "message")

  log_dir = "logs"
  if (local) {
    daemons(n_workers, .compute = "mlr3_parallelization")
  } else {
    daemons(
      n = n_workers,
      url = host_url(port = 5554),
      .compute = "mlr3_parallelization",
      remote = remote_config(
        command = "hq",
        args = c(
        "submit",
        "--cpus", "1",
        "--stdout=none",#, file.path(log_dir, "stdout-%{JOB_ID}-%{TASK_ID}.txt"),
        "--stderr=none",#, file.path(log_dir, "stderr-%{JOB_ID}-%{TASK_ID}.txt"),
        "--", "."),
        quote = FALSE
      )
    )
  }

  Sys.sleep(2)

  while (mirai::status(.compute = "mlr3_parallelization")$connections < n_workers) {
    Sys.sleep(10)
    mlr3misc::messagef("Waiting for workers to connect... %i/%i", mirai::status(.compute = "mlr3_parallelization")$connections, n_workers)
  }

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

  archive = instance$archive$data[, c(instance$archive$cols_x, instance$archive$cols_y), with = FALSE]

  mirai::daemons(0, .compute = "mlr3_parallelization")
  sink(NULL)
  sink(NULL, type = "message")

  archive
}), c("31", "3945", "7592", "189354"))


saveRDS(initial_design, "initial_designs.rds")
