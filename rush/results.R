library(data.table)
library(batchtools)
library(microbenchmark)

registry = "registries/"

# summarize the 10,000 replicates of one microbenchmark job
runtime_summary = function(reg, job_table) {
  stats = reduceResultsList(
    # pass the ids explicitly so the rows stay aligned with `job_table` even if a job is missing
    ids = job_table$job.id,
    fun = function(job, res) {
      time = res$time / 1e6
      q = quantile(time, c(0.25, 0.5, 0.75, 0.95, 0.99), names = FALSE)
      list(
        runtime_median = q[2],
        runtime_q25 = q[1],
        runtime_q75 = q[3],
        runtime_iqr = q[3] - q[1],
        runtime_q95 = q[4],
        runtime_q99 = q[5],
        # mad() is scale-equivariant, so this matches the previous mad(res$time) / 1e6
        runtime_mad = mad(time)
      )
    },
    missing.val = list(
      runtime_median = NA_real_,
      runtime_q25 = NA_real_,
      runtime_q75 = NA_real_,
      runtime_iqr = NA_real_,
      runtime_q95 = NA_real_,
      runtime_q99 = NA_real_,
      runtime_mad = NA_real_
    ),
    reg = reg
  )

  cbind(job_table, rbindlist(stats))
}

runtime_columns = c("runtime_median", "runtime_q25", "runtime_q75", "runtime_iqr",
  "runtime_q95", "runtime_q99", "runtime_mad")

# Push running tasks
reg = loadRegistry(file.dir = file.path(registry, "push_running_tasks"))

job_table = runtime_summary(reg, unwrap(getJobTable(reg = reg)))

job_table = job_table[, c("n_parameters", "payload_size", runtime_columns), with = FALSE]
fwrite(job_table, "rush/results/push_running_tasks.csv")

# Finish tasks
reg = loadRegistry(file.dir = file.path(registry, "finish_tasks"))

job_table = runtime_summary(reg, unwrap(getJobTable(reg = reg)))

job_table = job_table[, c("n_parameters", "payload_size", runtime_columns), with = FALSE]
fwrite(job_table, "rush/results/finish_tasks.csv")

# Fetch finished tasks
reg = loadRegistry(file.dir = file.path(registry, "fetch_finished_tasks"))

job_table = runtime_summary(reg, unwrap(getJobTable(reg = reg)))

job_table = job_table[, c("n_tasks", "n_parameters", "payload_size", runtime_columns), with = FALSE]
fwrite(job_table, "rush/results/fetch_finished_tasks.csv")

# Fetch finished tasks with cache
reg = loadRegistry(file.dir = file.path(registry, "fetch_finished_tasks_cache"))

job_table = runtime_summary(reg, unwrap(getJobTable(reg = reg)))

job_table = job_table[, c("n_tasks", "n_parameters", "payload_size", runtime_columns), with = FALSE]
fwrite(job_table, "rush/results/fetch_finished_tasks_cache.csv")
