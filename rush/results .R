library(data.table)
library(batchtools)
library(microbenchmark)

registry = "/dss/lxclscratch/00/ra98ror2/registries/benchmark_2026_rush/rush"

# Push running tasks
reg = loadRegistry(file.dir = file.path(registry, "push_running_tasks"))

job_table = unwrap(getJobTable(reg = reg))
set(job_table, j = "runtime_median", value = list(reduceResultsList(reg = reg, fun = function(job, res) summary(res)$median, missing.val = NA_real_)))
set(job_table, j = "runtime_mad", value = list(reduceResultsList(reg = reg, fun = function(job, res) mad(res$time) / 1e6, missing.val = NA_real_)))

job_table = job_table[, list(n_parameters, payload_size, runtime_median, runtime_mad)]
fwrite(job_table, "rush/results/push_running_tasks.csv")

# Finish tasks
reg = loadRegistry(file.dir = file.path(registry, "finish_tasks"))

job_table = unwrap(getJobTable(reg = reg))
set(job_table, j = "runtime_median", value = list(reduceResultsList(reg = reg, fun = function(job, res) summary(res)$median, missing.val = NA_real_)))
set(job_table, j = "runtime_mad", value = list(reduceResultsList(reg = reg, fun = function(job, res) mad(res$time) / 1e6, missing.val = NA_real_)))

job_table = job_table[, list(n_parameters, payload_size, runtime_median, runtime_mad)]
fwrite(job_table, "rush/results/finish_tasks.csv")

# Fetch finished tasks
reg = loadRegistry(file.dir = file.path(registry, "fetch_finished_tasks"))

job_table = unwrap(getJobTable(reg = reg))
set(job_table, j = "runtime_median", value = list(reduceResultsList(reg = reg, fun = function(job, res) summary(res)$median, missing.val = NA_real_)))
set(job_table, j = "runtime_mad", value = list(reduceResultsList(reg = reg, fun = function(job, res) mad(res$time) / 1e6, missing.val = NA_real_)))

job_table = job_table[, list(n_tasks, n_parameters, payload_size, runtime_median, runtime_mad)]
fwrite(job_table, "rush/results/fetch_finished_tasks.csv")  

# Fetch finished tasks with cache
reg = loadRegistry(file.dir = file.path(registry, "fetch_finished_tasks_cache"))

job_table = unwrap(getJobTable(reg = reg))
set(job_table, j = "runtime_median", value = list(reduceResultsList(reg = reg, fun = function(job, res) summary(res)$median, missing.val = NA_real_)))
set(job_table, j = "runtime_mad", value = list(reduceResultsList(reg = reg, fun = function(job, res) mad(res$time) / 1e6, missing.val = NA_real_)))

job_table = job_table[, list(n_tasks, n_parameters, payload_size, runtime_median, runtime_mad)]
fwrite(job_table, "rush/results/fetch_finished_tasks_cache.csv")


