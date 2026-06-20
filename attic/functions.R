create_tasks = function(n_tasks, n_parameters) {
  replicate(n_tasks, mlr3misc::set_names(replicate(n_parameters, runif(1), simplify = FALSE), paste0("x", seq(n_parameters))), simplify = FALSE)
}

# push running tasks
setup_push_running_tasks = function(instance, rush) {
  xss = create_tasks(instance$n_tasks, instance$n_parameters)
  list(xss = xss)
}

reset_push_running_tasks = function(instance, rush) {
  rush$reset_data()
}

run_push_running_tasks = function(xss, rush) {
  rush$push_running_tasks(xss)
}

# push results
setup_push_results = function(instance, rush) {
  setup = setup_push_running_tasks(instance, rush)
  keys = mlr3misc::invoke(run_push_running_tasks, rush = rush, .args = setup)
  yss = replicate(length(keys), list(y = runif(1)), simplify = FALSE)
  list(yss = yss, keys = keys)
}

reset_push_results = function(instance, rush) {
  
}

run_push_results = function(yss, keys, rush) {
  rush$push_results(keys, yss)
}

# Fetch Finished Tasks
setup_fetch_finished_tasks = function(instance, rush) {
  list()
}

reset_fetch_finished_tasks = function(instance, rush) {
  rush$reset_data()
  setup = setup_push_results(instance, rush)
  mlr3misc::invoke(run_push_results, rush = rush, .args = setup)
}

run_fetch_finished_tasks = function(rush) {
  rush$fetch_finished_tasks()
}

# Fetch Cached Tasks
setup_fetch_cached_tasks = function(instance, rush) {
  list()
}

reset_fetch_cached_tasks = function(instance, rush) {
  # add task to cache
  reset_fetch_finished_tasks(instance, rush)
  rush$fetch_finished_tasks()
  # add new task
  xss = list(list(x1 = runif(1)))
  keys = rush$push_running_tasks(xss)
  rush$push_results(keys, list(list(y = 100)))
}

run_fetch_cached_tasks = function(rush) {
  rush$fetch_finished_tasks()
}

# push queue
setup_push_tasks = function(instance, rush) {
  xss = create_tasks(instance$n_tasks, instance$n_parameters)
  list(xss = xss)
}

reset_push_tasks = function(instance, rush) {
  rush$reset_data()
}

run_push_tasks = function(xss, rush) {
  rush$push_tasks(xss)
}

setup_functions = list(
  # main functions
  push_running_tasks = setup_push_tasks,
  push_results = setup_push_results,
  fetch_finished_tasks = setup_fetch_finished_tasks,
  fetch_cached_tasks = setup_fetch_cached_tasks,
  # queue
  push_tasks = setup_push_tasks
)

reset_functions = list(
  # main functions
  push_running_tasks = reset_push_running_tasks,
  push_results = reset_push_results,
  fetch_finished_tasks = reset_fetch_finished_tasks,
  fetch_cached_tasks = reset_fetch_cached_tasks,
  # queue
  push_tasks = reset_push_tasks
)

run_functions = list(
  # main functions
  push_running_tasks = run_push_running_tasks,
  push_results = run_push_results,
  fetch_finished_tasks = run_fetch_finished_tasks,
  fetch_cached_tasks = run_fetch_cached_tasks,
  # queue
  push_tasks = run_push_tasks
)


