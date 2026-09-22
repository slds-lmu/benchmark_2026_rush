library(batchtools)
library(data.table)

registry = "registries/fetch_finished_tasks"

unlink(registry, recursive = TRUE)
reg = makeRegistry(
  file.dir = registry,
  conf.file = NA,
  seed = 7832,
  packages = "renv",
  source = "rush/helper.R"
)
reg$cluster.functions = makeClusterFunctionsHyperQueue()

batchMap(function(n_tasks, n_parameters, payload_size, .job) {
  renv::load(".")
  library(rush)
  lgr::get_logger("mlr3")$set_threshold("warn")

  config = start_redis(.job)
  rush = RushWorker$new("benchmark", config)
  on.exit(try(rush$connector$SHUTDOWN(), silent = TRUE), add = TRUE)

  setup = function() {
    rush$reset(workers = FALSE)
    xss = replicate(n_tasks, mlr3misc::set_names(replicate(n_parameters, list(runif(payload_size)), simplify = FALSE), paste0("x", seq(n_parameters))), simplify = FALSE)
    keys = rush$push_running_tasks(xss = xss)
    yss = replicate(length(xss), list(y = runif(payload_size)), simplify = FALSE)
    rush$finish_tasks(keys, yss)
  }

  times = max(1L, as.integer(1000L * min(1, 1000L / n_tasks)))

  res = microbenchmark::microbenchmark(
    rush$fetch_finished_tasks(),
    times = times,
    unit = "ms",
    setup = setup()
  )
  res
}, args = CJ(
  n_tasks = c(1, 10, 100, 1e3, 1e4, 1e5),
  n_parameters = c(1, 10, 100),
  payload_size = c(1, 10, 100)
), reg = reg)

submitJobs(resources = list(ncpus = 2L, walltime = 3600L))
