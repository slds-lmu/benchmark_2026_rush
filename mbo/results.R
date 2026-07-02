library(data.table)
library(ggplot2)
library(mlr3misc)

results = set_names(readRDS("mbo/results/results.rds"), c("german-credit", "kddcup09-appetency", "adult", "airlines"))

aggregated = imap_dtr(results, function(results, task_id) {
  imap_dtr(results, function(result, algorithm) {

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
}, .idcol = "task_id")

setcolorder(aggregated, c("task_id", "algorithm", "runtime_learners", "runtime_surrogate", "runtime_optimizer", "mean_runtime_learners", "walltime", "cpu_hours", "evals", "performance", "utilization"))

fwrite(aggregated, "mbo/results/aggregated.csv")
