library(batchtools)
library(data.table)

registry = "registries/rush_local/push_running_tasks"

dir.create(dirname(registry), recursive = TRUE, showWarnings = FALSE)
unlink(registry, recursive = TRUE)
reg = makeRegistry(
  file.dir = registry,
  conf.file = NA,
  seed = 7832,
  packages = "renv",
  source = "rush_local/helper.R"
)
# local run: jobs are executed sequentially in a separate R process each
reg$cluster.functions = makeClusterFunctionsInteractive(external = TRUE)

batchMap(function(n_parameters, payload_size, .job) {
  renv::load(".")
  set.seed(7832)
  library(rush)
  lgr::get_logger("mlr3")$set_threshold("warn")

  config = start_redis(.job)
  rush = RushWorker$new("benchmark", config)

  xss = list(mlr3misc::set_names(replicate(n_parameters, list(runif(payload_size)), simplify = FALSE), paste0("x", seq(n_parameters))))

  res = microbenchmark::microbenchmark(
    rush$push_running_tasks(xss),
    times = 10000,
    unit = "ms",
    setup = rush$reset(workers = FALSE)
  )
  try({rush$connector$SHUTDOWN()}, silent = TRUE)
  res
}, args = CJ(
  n_parameters = c(1, 10, 100),
  payload_size = c(1, 10, 100, 1000, 10000)
), reg = reg)

submitJobs(reg = reg)
