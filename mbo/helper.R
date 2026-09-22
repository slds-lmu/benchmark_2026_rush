# Shared by mbo/initial_design.R and mbo/experiment.R

# OptimizerAsyncMboCentral.R and bayesopt_mpcl.R log through a global `lg`
lg = lgr::get_logger("mlr3/mlr3mbo")

#  31L credit g
#  3945L KDDCup09_appetency
#  7592L Adult
#  189354L Airlines
otask_ids = c(31L, 3945L, 7592L, 189354L)

mbo_learner = function() {
  mlr3::set_validate(
    mlr3::lrn(
      "classif.lightgbm",
      early_stopping_rounds = 100,
      learning_rate = paradox::to_tune(1e-3, 1, logscale = TRUE),
      feature_fraction = paradox::to_tune(0.1, 1),
      min_data_in_leaf = paradox::to_tune(1, 200),
      num_leaves = paradox::to_tune(10, 255),
      extra_trees = paradox::to_tune(),
      lambda_l1 = paradox::to_tune(1e-3, 1e3, logscale = TRUE),
      lambda_l2 = paradox::to_tune(1e-3, 1e3, logscale = TRUE),
      min_gain_to_split = paradox::to_tune(1e-3, 0.1, logscale = TRUE),
      num_iterations = paradox::to_tune(1, 5000, internal = TRUE),
      eval = "binary_error"
    ),
    "test"
  )
}

initial_design_file = function(otask_id, repl) {
  sprintf("mbo/results/initial_design_%i_%i.rds", otask_id, repl)
}

# bring up n_workers mirai daemons as HyperQueue tasks 
# and block until all of them have connected
start_daemons = function(n_workers, profile = NULL) {
  mirai::daemons(0, .compute = profile)

  mirai::daemons(
    n = n_workers,
    url = mirai::host_url(port = 5554),
    .compute = profile,
    remote = mirai::remote_config(
      command = "hq",
      args = c(
        "submit",
        "--cpus",
        "1",
        "--stdout=none",
        "--stderr=none",
        "--",
        "."
      ),
      quote = FALSE
    )
  )

  Sys.sleep(2)

  while (mirai::status(.compute = profile)$connections < n_workers) {
    Sys.sleep(10)
    mlr3misc::messagef(
      "Waiting for workers to connect... %i/%i",
      mirai::status(.compute = profile)$connections,
      n_workers
    )
  }
}

stop_daemons = function(profile = NULL) {
  mirai::daemons(0, .compute = profile)
}

# Write every finished job's result to its own file. `path` maps a one-row job
# parameter table to a file path. Only finished jobs are exported, so this can run
# after a partial submission without failing on the cells that are still missing.
export_results = function(reg, path) {
  pars = batchtools::unwrap(batchtools::getJobPars(reg = reg))
  ids = batchtools::findDone(reg = reg)$job.id

  mlr3misc::walk(ids, function(id) {
    cell = pars[list(id), on = "job.id"]
    saveRDS(batchtools::loadResult(id, reg = reg), path(cell))
  })

  mlr3misc::messagef("Exported %i of %i job(s)", length(ids), nrow(pars))
}
