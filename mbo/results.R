library(data.table)
library(ggplot2)
library(mlr3misc)

task_names = c("31" = "german-credit", "3945" = "kddcup09-appetency", "7592" = "adult", "189354" = "airlines")
algorithms = c("cl_mbo", "central_mbo", "async_mbo")

# one file per (algorithm, task, repl), exported after submission returns.
pattern = sprintf("^(%s)_([0-9]+)_([0-9]+)\\.rds$", paste(algorithms, collapse = "|"))
files = list.files("mbo/results", pattern = pattern)
if (!length(files)) {
  stopf("No result files in mbo/results, run mbo/experiment.R first")
}

aggregated = map_dtr(files, function(file) {
  cell = regmatches(file, regexec(pattern, file))[[1]]
  algorithm = cell[[2]]
  otask_id = cell[[3]]
  repl = as.integer(cell[[4]])

  result = readRDS(file.path("mbo/results", file))
  archive = copy(result)

  if ("timestamp_xs" %in% colnames(archive)) {
    # remove initial design
    first_timestamp = min(archive$timestamp_xs, na.rm = TRUE)
    archive = archive[timestamp_xs != first_timestamp]

    # fix runtime_learners for cancelled evaluations 
    last_timestamp = max(archive$timestamp_ys, na.rm = TRUE)
    archive[is.na(timestamp_ys), timestamp_ys := last_timestamp]
    archive[is.na(runtime_learners), runtime_learners := as.numeric(difftime(timestamp_ys, timestamp_xs, units = "secs"))]

    walltime = as.numeric(difftime(last_timestamp, min(archive$timestamp_xs, na.rm = TRUE), units = "secs"), units = "secs")

    # only count finished evaluations
    evals = nrow(archive[state == "finished"])

    # calculate mean runtime only from finished evaluations
    mean_runtime_learners = archive[state == "finished", mean(runtime_learners, na.rm = TRUE)]
  } else {
    # remove initial design
    archive = archive[101:nrow(archive)]
    walltime = as.numeric(difftime(max(archive$timestamp, na.rm = TRUE), min(result[batch_nr == 1][1, timestamp], na.rm = TRUE), units = "secs"), units = "secs")
    evals = nrow(archive)
    mean_runtime_learners = mean(archive$runtime_learners, na.rm = TRUE)
  }
  # calculate runtimes
  archive[, runtime_surrogate := as.numeric(difftime(timestamp_acq_function, timestamp_surrogate,units = "secs"))]
  archive[, runtime_optimizer := as.numeric(difftime(timestamp_loop, timestamp_acq_optimizer, units = "secs"))]

  # sum runtimes
  runtime_learners = sum(archive$runtime_learners, na.rm = TRUE)
  runtime_surrogate = sum(archive$runtime_surrogate, na.rm = TRUE)
  runtime_optimizer = sum(archive$runtime_optimizer, na.rm = TRUE)

  # compute cpu time as walltime * number of workers
  cpu_time = walltime * 448L

  data.table(
    repl = repl,
    task_id = task_names[[otask_id]],
    algorithm = algorithm,
    runtime_learners = runtime_learners,
    runtime_surrogate = runtime_surrogate,
    runtime_optimizer = runtime_optimizer,
    mean_runtime_learners = mean_runtime_learners,
    walltime = walltime,
    cpu_hours = cpu_time / 60 / 60,
    utilization = (runtime_learners + runtime_surrogate + runtime_optimizer) / cpu_time,
    evals = evals,
    performance = min(archive$classif.ce, na.rm = TRUE)
  )
})

# keep task and algorithm in benchmark order rather than alphabetical file order
aggregated[, task_id := factor(task_id, levels = task_names)]
aggregated[, algorithm := factor(algorithm, levels = algorithms)]
setorder(aggregated, repl, task_id, algorithm)

setcolorder(aggregated, c("repl", "task_id", "algorithm", "runtime_learners", "runtime_surrogate", "runtime_optimizer", "mean_runtime_learners", "walltime", "cpu_hours", "evals", "performance", "utilization"))

fwrite(aggregated, "mbo/results/aggregated.csv")

# mean over repls
measures = setdiff(colnames(aggregated), c("repl", "task_id", "algorithm"))
aggregated_mean = aggregated[, lapply(.SD, mean, na.rm = TRUE), by = c("task_id", "algorithm"), .SDcols = measures]
aggregated_mean[, repls := aggregated[, .N, by = c("task_id", "algorithm")]$N]

fwrite(aggregated_mean, "mbo/results/aggregated_mean.csv")
