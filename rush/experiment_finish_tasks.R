renv::load(".")

library(batchtools)
library(data.table)

registry = "/dss/lxclscratch/00/ra98ror2/registries/benchmark_2026_rush/rush/finish_tasks"

unlink(registry, recursive = TRUE)
reg = makeRegistry(
  file.dir = registry,
  conf.file = NA,
  seed = 7832,
  packages = "renv",
  source = "rush/helper.R"
)
reg$cluster.functions = makeClusterFunctionsHyperQueue()

batchMap(function(n_parameters, payload_size, .job) {
  renv::load(".")
  set.seed(7832)
  library(rush)
  lgr::get_logger("mlr3")$set_threshold("warn")

  config = start_redis(.job)
  rush = RushWorker$new("benchmark", config)

  xss = list(mlr3misc::set_names(replicate(n_parameters, list(runif(payload_size)), simplify = FALSE), paste0("x", seq(n_parameters))))
  key = rush$push_running_tasks(xss)
  yss = list(mlr3misc::set_names(replicate(n_parameters, list(runif(payload_size)), simplify = FALSE), paste0("y", seq(n_parameters))))

  res = microbenchmark::microbenchmark(
    rush$finish_tasks(key, yss),
    unit = "ms",
    times = 10000
  )
  try({rush$connector$SHUTDOWN()}, silent = TRUE)
  res
}, args = CJ(
  n_parameters = c(1, 10, 100),
  payload_size = c(1, 10, 100, 1000, 10000)
), reg = reg)

submitJobs(resources = list(ncpus = 2L, walltime = 600L))
waitForJobs()