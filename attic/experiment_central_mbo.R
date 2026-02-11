file = file(sprintf("logs/central_mbo_%i.log", otask_id), open = "wt")
sink(file)
sink(file, type = "message")

# library(mlr3)
# library(mlr3tuning)
# library(mlr3oml)
# library(mlr3mbo)
# library(mirai)
# library(rush)
# library(mlr3learners)

# n_workers = 4L
# otask_id = 3L
# n_evals = 20L

# otask = otsk(id = otask_id)
# task = as_task(otask)
# resampling = as_resampling(otask)

# learner = lrn("classif.rpart",
#   minsplit  = to_tune(2L, 128L),
#   minbucket = to_tune(2L, 128L),
#   cp        = to_tune(1e-04, 1e-1))

# log_dir = "logs"
# daemons(
#   n = n_workers,
#   url = host_url(port = 5555),
#   remote = remote_config(
#     command = "hq",
#     args = c(
#     "submit",
#     "--cpus", "1",
#     "--stdout", file.path(log_dir, "stdout-%{JOB_ID}-%{TASK_ID}.txt"),
#     "--stderr", file.path(log_dir, "stderr-%{JOB_ID}-%{TASK_ID}.txt"),
#     "--", "."),
#     quote = FALSE
#   )
# )

# Sys.sleep(2)

# while (mirai::status()$connections == 0) {
#   Sys.sleep(10)
#   message("Waiting for workers to connect...")
# }

rush::rush_plan(n_workers = n_workers, config = config, worker_type = "remote")

instance = ti_async(
  task = task,
  learner = learner,
  resampling = resampling,
  measures = msr("classif.ce"),
  terminator = trm("evals", n_evals = n_evals),
  store_benchmark_result = FALSE
)

tuner = tnr("async_mbo_central", design_size = floor(0.25 * n_evals))

time = system.time({tuner$optimize(instance)})
# 91 seconds
