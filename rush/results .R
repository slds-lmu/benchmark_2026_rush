library(data.table)
library(batchtools)
library(microbenchmark)

# Push running tasks
reg = loadRegistry(file.dir = "core/registry_push_running_tasks", writeable = TRUE)

job_table = unwrap(getJobTable(reg = reg))
set(job_table, j = "runtime_median", value = list(reduceResultsList(reg = reg, fun = function(job, res) summary(res)$median, missing.val = NA_real_)))
set(job_table, j = "runtime_mad", value = list(reduceResultsList(reg = reg, fun = function(job, res) mad(res$time) / 1e6, missing.val = NA_real_)))

job_table[, list(n_parameters, payload_size, runtime_median, runtime_mad)]
fwrite(job_table, "core/results_push_running_tasks.csv")

# Finish tasks
reg = loadRegistry(file.dir = "core/registry_finish_tasks", writeable = TRUE)

job_table = unwrap(getJobTable(reg = reg))
set(job_table, j = "runtime_median", value = list(reduceResultsList(reg = reg, fun = function(job, res) summary(res)$median, missing.val = NA_real_)))
set(job_table, j = "runtime_mad", value = list(reduceResultsList(reg = reg, fun = function(job, res) mad(res$time) / 1e6, missing.val = NA_real_)))

job_table[, list(n_parameters, payload_size, runtime_median, runtime_mad)]
fwrite(job_table, "core/results_finish_tasks.csv")

# Fetch finished tasks
reg = loadRegistry(file.dir = "core/registry_fetch_finished_tasks", writeable = TRUE)

job_table = unwrap(getJobTable(reg = reg))
set(job_table, j = "runtime_median", value = list(reduceResultsList(reg = reg, fun = function(job, res) summary(res)$median, missing.val = NA_real_)))
set(job_table, j = "runtime_mad", value = list(reduceResultsList(reg = reg, fun = function(job, res) mad(res$time) / 1e6, missing.val = NA_real_)))

job_table[, list(n_tasks, n_parameters, payload_size, runtime_median, runtime_mad)]
fwrite(job_table, "core/results_fetch_finished_tasks.csv")  

# Fetch finished tasks with cache
reg = loadRegistry(file.dir = "core/registry_fetch_finished_tasks_cache", writeable = TRUE)

job_table = unwrap(getJobTable(reg = reg))
set(job_table, j = "runtime_median", value = list(reduceResultsList(reg = reg, fun = function(job, res) summary(res)$median, missing.val = NA_real_)))
set(job_table, j = "runtime_mad", value = list(reduceResultsList(reg = reg, fun = function(job, res) mad(res$time) / 1e6, missing.val = NA_real_)))

job_table[, list(n_tasks, n_parameters, payload_size, runtime_median, runtime_mad)]
fwrite(job_table, "core/results_fetch_finished_tasks_cache.csv")


