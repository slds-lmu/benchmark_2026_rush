library(data.table)
library(knitr)
options(scipen = 999)

table_push_running_tasks = data.table::fread("benchmarks/core/results_push_running_tasks.csv")
table_finish_tasks = data.table::fread("benchmarks/core/results_finish_tasks.csv")

table_push_running_tasks = table_push_running_tasks[, list(n_parameters, payload_size, runtime_median_push = runtime_median)]
set(table_push_running_tasks, j = "runtime_median_finish", value = table_finish_tasks$runtime_median)


knitr::kable(table_push_running_tasks[, list(n_parameters, payload_size, runtime_median_push, runtime_median_finish)],
  digits = 2,
  col.names = c("Number of Parameters / Results", "Payload Size", "Runtime Push (ms)", "Runtime Finish (ms)")
)

table_fetch = data.table::fread("benchmarks/core/results_fetch_finished_tasks.csv")
table_fetch_cache = data.table::fread("benchmarks/core/results_fetch_finished_tasks_cache.csv")

table_fetch = table_fetch[, list(n_tasks, n_parameters, payload_size, runtime_median)]
set(table_fetch, j = "runtime_median_cache", value = table_fetch_cache$runtime_median)

knitr::kable(table_fetch,
  digits = 0,
  col.names = c("Number of Tasks", "Number of Parameters / Results", "Payload Size", "Runtime (ms)", "Runtime Cache (ms)")
)

# table = data.table::fread("benchmarks/core/results_fetch_finished_tasks.csv")
# table_wide = dcast(table[payload_size == 1], n_tasks ~ n_parameters, value.var = "runtime_median")
# setnames(table_wide, c("Number of Tasks", "Params = 1", "Params = 10", "Params = 100"))

# knitr::kable(table_wide,
#   digits = 0,
#   col.names = c("Number of Tasks", "Params = 1", "Params = 10", "Params = 100")
# )

# table = data.table::fread("benchmarks/core/results_fetch_finished_tasks_cache.csv")
# table_wide = dcast(table[payload_size == 1], n_tasks ~ n_parameters, value.var = "runtime_median")
# setnames(table_wide, c("Number of Tasks", "Params = 1", "Params = 10", "Params = 100"))

# knitr::kable(table_wide,
#   digits = 0,
#   col.names = c("Number of Tasks", "Params = 1", "Params = 10", "Params = 100")
# )

library(ggplot2)
library(data.table)

table = data.table::fread("benchmarks/core/results_fetch_finished_tasks.csv")
table_cache = data.table::fread("benchmarks/core/results_fetch_finished_tasks_cache.csv")

table = rbindlist(list(without_cache = table, with_cache = table_cache), idcol = "cache")[payload_size == 1]

ggplot(table, aes(x = n_tasks, y = runtime_median, color = cache)) +
  geom_line() +
  geom_point() +
  facet_wrap(~ n_parameters, labeller = labeller(n_parameters = c("1" = "1 Parameter", "10" = "10 Parameters", "100" = "100 Parameters"))) +
  labs(x = "Number of Tasks", y = "Runtime (ms)", color = "Fetching") +
  scale_x_log10(breaks = c(1, 10, 100, 1000, 10000, 100000),
    labels = scales::label_number(scale_cut = scales::cut_short_scale())) +
  scale_color_manual(values = c("without_cache" = "#F8766D", "with_cache" = "#00BFC4"), labels = c("without_cache" = "without cache", "with_cache" = "with cache")) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave("benchmarks/core/fetch_finished_tasks.png", width = 5.5, height = 4)
