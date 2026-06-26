renv::load(".")

devtools::load_all("../mlr3mbo")

library(mlr3)
library(mlr3tuning)
library(mlr3oml)
library(mlr3mbo)
library(mirai)
library(rush)
library(mlr3extralearners)
library(mlr3misc)
library(R6)
library(checkmate)
library(data.table)
library(bbotk)

walk(list.files("mbo/source", full.names = TRUE), source)


lg = lgr::get_logger("mlr3/mlr3mbo")

config = redux::redis_config()

otask_id = 31L
otask = otsk(id = otask_id)
task = as_task(otask)
resampling = as_resampling(otask)

r = redux::hiredis(config)
r$FLUSHDB()
n_workers = 1L


measure = msr("classif.ce")
terminator = trm("run_time", secs = 30)

learner = set_validate(
  lrn(
    "classif.lightgbm",
    early_stopping_rounds = 100,
    learning_rate = to_tune(1e-3, 1, logscale = TRUE),
    feature_fraction = to_tune(0.1, 1),
    min_data_in_leaf = to_tune(1, 200),
    num_leaves = to_tune(10, 255),
    extra_trees = to_tune(),
    lambda_l1 = to_tune(1e-3, 1e3, logscale = TRUE),
    lambda_l2 = to_tune(1e-3, 1e3, logscale = TRUE),
    min_gain_to_split = to_tune(1e-3, 0.1, logscale = TRUE),
    num_iterations = to_tune(1, 5000, internal = TRUE),
    eval = "binary_error"
  ),
  "test"
)


initial_design = readRDS("mbo/initial_designs.rds")$`31`
  
rush::rush_plan(n_workers = n_workers, config = config, worker_type = "mirai")

mirai::daemons(1)

instance = ti_async(
  task = task,
  learner = learner,
  resampling = resampling,
  measures = measure,
  terminator = trm("run_time", secs = 30),
  store_benchmark_result = FALSE
)

instance$rush

tuner = TunerAsyncMboCentral$new()

xss = transpose_list(initial_design[, instance$archive$cols_x, with = FALSE])
yss = transpose_list(initial_design[, instance$archive$cols_y, with = FALSE])
instance$archive$push_finished_points(xss, yss)

tuner$optimize(instance)
