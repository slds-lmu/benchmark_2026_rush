library(data.table)
library(ggplot2)

n_workers = 448L

results = readRDS("results.rds")

results = set_names(results, c("german-credit", "kddcup09-appetency", "adult", "airlines"))


tab = imap_dtr(results, function(results, task_id) {
  imap_dtr(results, function(result, algorithm) {

    archive = copy(result)

  if ("timestamp_xs" %in% colnames(archive)) {
    # sometimes a running task is present
    archive = archive[state %in% c("finished", "failed")]
    # remove initial design
    archive = archive[101:nrow(archive)]

    last_timestamp = max(archive$timestamp_ys, na.rm = TRUE)

    # fix runtime_learners for cancelled evaluations
    archive[message == "Optimization terminated", timestamp_ys := last_timestamp]
    archive[message == "Optimization terminated", runtime_learners := as.numeric(difftime(timestamp_ys, timestamp_xs, units = "secs"))]

    walltime = as.numeric(difftime(last_timestamp, min(archive$timestamp_xs, na.rm = TRUE), units = "secs"), units = "secs")
  } else {
    # remove initial design
    archive = archive[101:nrow(archive)]
    walltime = as.numeric(difftime(max(archive$timestamp, na.rm = TRUE), min(result[batch_nr == 1][1, timestamp], na.rm = TRUE), units = "secs"), units = "secs")
  }

  archive[, runtime_surrogate := as.numeric(difftime(timestamp_acq_function, timestamp_surrogate,units = "secs"))]
  archive[, runtime_optimizer := as.numeric(difftime(timestamp_loop, timestamp_acq_optimizer, units = "secs"))]
  runtime_learners = sum(archive$runtime_learners, na.rm = TRUE)
  runtime_surrogate = sum(archive$runtime_surrogate, na.rm = TRUE)
  runtime_optimizer = sum(archive$runtime_optimizer, na.rm = TRUE)
  cpu_time = walltime * n_workers

  data.table(
    algorithm = algorithm,
    runtime_learners = runtime_learners,
    runtime_surrogate = runtime_surrogate,
    runtime_optimizer = runtime_optimizer,
    mean_runtime_learners = runtime_learners / nrow(archive),
    walltime = walltime,
    cpu_hours = cpu_time / 60 / 60,
    utilization = (runtime_learners + runtime_surrogate + runtime_optimizer) / cpu_time,
    evals = nrow(archive),
    performance = min(archive$classif.ce, na.rm = TRUE)
  )
  })
}, .idcol = "task_id")

cols = c("runtime_learners", "runtime_surrogate", "runtime_optimizer", "mean_runtime_learners", "walltime", "cpu_hours")
tab[, (cols) := map(.SD, round, 0), .SDcols = cols]
cols = c("utilization", "performance")
tab[, (cols) := map(.SD, signif, 2), .SDcols = cols]

setcolorder(tab, c("task_id", "algorithm", "runtime_learners", "runtime_surrogate", "runtime_optimizer", "mean_runtime_learners", "walltime", "cpu_hours", "evals", "performance", "utilization"))

fwrite(tab, "results.csv")

tab[, task_id := ifelse(duplicated(task_id), "", task_id)]

tab[, algorithm := fcase(
  algorithm == "cl_mbo",      "CLBO",
  algorithm == "central_mbo", "ACBO",
  algorithm == "async_mbo",   "ADBO",
  default = algorithm
)]

tab[, utilization := utilization * 100]

#knitr::kable(tab, format = "latex", booktabs = TRUE)

knitr::kable(tab[, list(task_id, algorithm, mean_runtime_learners, evals, utilization)], 
  format = "markdown", 
  col.names = c("Task", "Algorithm", "Mean Runtime Learners [s]", "Evaluations", "Utilization [%]"), format.args = list(big.mark = ","))

knitr::kable(tab[, list(task_id, algorithm, runtime_learners, runtime_surrogate, runtime_optimizer, mean_runtime_learners, walltime, cpu_hours, performance)], 
  format = "markdown", 
  col.names = c("Task", "Algorithm", "Runtime Learners", "Runtime Surrogate", "Runtime Optimizer", "Mean Runtime Learners [s]", "Walltime [s]", "CPU Hours", "Performance"), format.args = list(big.mark = ","))

plot_data = imap_dtr(results, function(results, task_id) {
  archive = rbindlist(results, fill = TRUE, idcol = "algorithm")
  archive_best = archive[!is.na(classif.ce)]
  archive_best[algorithm == "cl_mbo", walltime := as.numeric(difftime(timestamp, timestamp[1], units = "secs"))]
  archive_best[algorithm == "central_mbo", walltime := as.numeric(difftime(timestamp_ys, timestamp_ys[1], units = "secs"))]
  archive_best[algorithm == "async_mbo", walltime := as.numeric(difftime(timestamp_ys, timestamp_xs[1], units = "secs"))]
  archive_best[, incumbent := cummin(classif.ce), by = algorithm]
  archive_best
}, .idcol = "task_id")


ggplot(plot_data, aes(x = walltime, y = incumbent, color = algorithm)) +
  geom_line() +
  scale_color_discrete(name = "Algorithm") +
  labs(x = "Walltime", y = "Performance") +
  facet_wrap(~task_id, scales = "free_y") +
  theme_minimal(base_size = 14)

ggsave("performance.png", width = 8, height = 6)
