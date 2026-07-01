OptimizerAsyncMboCentral = R6Class("OptimizerAsyncMboCentral",
  inherit = bbotk::OptimizerAsync,

  public = list(
    #' @description
    #' Creates a new instance of this [R6][R6::R6Class] class.
    #'
    #' If `surrogate` is `NULL` and the `acq_function$surrogate` field is populated, this [SurrogateLearner] is used.
    #' Otherwise, `default_surrogate(instance)` is used.
    #' If `acq_function` is `NULL` and the `acq_optimizer$acq_function` field is populated, 
    #' this [AcqFunction] is used (and therefore its `$surrogate` if populated; see above).
    #' Otherwise `default_acqfunction(instance)` is used.
    #' If `acq_optimizer` is `NULL`, `default_acqoptimizer(instance)` is used.
    #'
    #' Even if already initialized, the `surrogate$archive` field will always be overwritten 
    #' by the [bbotk::ArchiveAsync] of the current [bbotk::OptimInstanceAsyncSingleCrit] to be optimized.
    #'
    #' For more information on default values for `surrogate`, `acq_function`, `acq_optimizer` 
    #' and `result_assigner`, see `?mbo_defaults`.
    #'
    #' @template param_id
    #' @template param_surrogate
    #' @template param_acq_function
    #' @template param_acq_optimizer
    #' @template param_result_assigner
    #' @template param_label
    #' @param param_set ([paradox::ParamSet])\cr
    #'  Set of control parameters.
    #' @template param_man
    initialize = function(
      id = "async_mbo_central",
      surrogate = NULL,
      acq_function = NULL,
      acq_optimizer = NULL,
      result_assigner = NULL,
      param_set = NULL,
      label = "Centralized Asynchronous Model Based Optimization",
      man = "mlr3mbo::OptimizerAsyncMboCentral"
      ){

      default_param_set = ps(
        initial_design = p_uty(),
        design_size = p_int(lower = 1, default = 100L),
        design_function = p_fct(c("random", "sobol", "lhs"), default = "sobol"),
        n_workers = p_int(lower = 1L)
      )
      param_set = c(default_param_set, param_set)

      param_set$set_values(design_size = 100L, design_function = "sobol")

      super$initialize("async_mbo_central",
        param_set = param_set,
        param_classes = c("ParamLgl", "ParamInt", "ParamDbl", "ParamFct"),
        properties = c("dependencies", "single-crit"),  # is replaced with dynamic AB after construction
        packages = c("mlr3mbo", "rush"),  # is replaced with dynamic AB after construction
        label = label,
        man = man)

      self$surrogate = assert_r6(surrogate, classes = "Surrogate", null.ok = TRUE)
      self$acq_function = assert_r6(acq_function, classes = "AcqFunction", null.ok = TRUE)
      self$acq_optimizer = assert_r6(acq_optimizer, classes = "AcqOptimizer", null.ok = TRUE)
      self$result_assigner = assert_r6(result_assigner, classes = "ResultAssigner", null.ok = TRUE)
    },

    #' @description
    #' Print method.
    #'
    #' @return (`character()`).
    print = function() {
      catn(format(self), if (is.na(self$label)) "" else paste0(": ", self$label))
      catn(str_indent("* Parameter classes:", self$param_classes))
      catn(str_indent("* Properties:", self$properties))
      catn(str_indent("* Packages:", self$packages))
      catn(str_indent("* Surrogate:", if (is.null(self$surrogate)) "-" else self$surrogate$print_id))
      catn(str_indent("* Acquisition Function:", if (is.null(self$acq_function)) "-" else class(self$acq_function)[1L]))
      catn(str_indent("* Acquisition Function Optimizer:", if (is.null(self$acq_optimizer)) "-" else self$acq_optimizer$print_id))
      catn(str_indent("* Result Assigner:", if (is.null(self$result_assigner)) "-" else class(self$result_assigner)[1L]))
    },

    #' @description
    #' Reset the optimizer.
    #' Sets the following fields to `NULL`:
    #' `surrogate`, `acq_function`, `acq_optimizer`,`result_assigner`
    #' Resets parameter values `design_size` and `design_function` to their defaults.
    reset = function() {
      private$.surrogate = NULL
      private$.acq_function = NULL
      private$.acq_optimizer = NULL
      private$.result_assigner = NULL
      self$param_set$set_values(design_size = 100L, design_function = "sobol")
    },

    #' @description
    #' Performs the optimization on an [bbotk::OptimInstanceAsyncSingleCrit] until termination.
    #' The main process fits the surrogate model and optimizes the acquisition function.
    #' Workers only evaluate points from the queue.
    #' The single evaluations will be written into the [bbotk::ArchiveAsync].
    #' The result will be written into the instance object.
    #'
    #' @param inst ([bbotk::OptimInstanceAsyncSingleCrit]).
    #' @return [data.table::data.table()]
    optimize = function(inst) {
      # setup MBO components
      if (is.null(self$acq_function)) {
        self$acq_function = self$acq_optimizer$acq_function %??% default_acqfunction(inst)
      }

      if (is.null(self$surrogate)) {  # acq_function$surrogate has precedence
        self$surrogate = self$acq_function$surrogate %??% default_surrogate(inst)
      }

      if (is.null(self$acq_optimizer)) {
        self$acq_optimizer = default_acqoptimizer(self$acq_function, inst)
      }

      if (is.null(self$result_assigner)) {
        self$result_assigner = default_result_assigner(inst)
      }

      self$surrogate$reset()
      self$acq_function$reset()
      self$acq_optimizer$reset()

      self$surrogate$archive = inst$archive
      self$acq_function$surrogate = self$surrogate
      self$acq_optimizer$acq_function = self$acq_function

      check_packages_installed(self$packages, msg = sprintf("Package '%%s' required but not installed for Optimizer '%s'", format(self)))

      pv = self$param_set$values
      n_workers = pv$n_workers

      # initial design
      design = if (inst$archive$n_evals) {
        lg$debug("Using archive with %s evaluations as initial design", inst$archive$n_evals)
        NULL
      } else if (is.null(pv$initial_design)) {
        # generate initial design
        generate_design = switch(pv$design_function,
          "random" = generate_design_random,
          "sobol" = generate_design_sobol,
          "lhs" = generate_design_lhs)

        lg$debug("Generating sobol design with size %s", pv$design_size)
        generate_design(inst$search_space, n = pv$design_size)$data
      } else {
        # use provided initial design
        lg$debug("Using provided initial design with size %s", nrow(pv$initial_design))

        xss = transpose_list(pv$initial_design[, inst$archive$cols_x, with = FALSE])
        yss = transpose_list(pv$initial_design[, inst$archive$cols_y, with = FALSE])
        inst$archive$push_finished_points(xss, yss)
        NULL
      }

      # initialize optimization
      inst$archive$start_time = Sys.time()
      get_private(inst)$.initialize_context(self)
      call_back("on_optimization_begin", inst$objective$callbacks, inst$objective$context)

      # send design to workers
      if (!is.null(design)) {
        inst$archive$push_points(transpose_list(design))
      }

      if (getOption("bbotk.debug", FALSE)) {
        # debug mode runs .optimize() in main process
        rush = rush::RushWorker$new(inst$rush$network_id)
        inst$rush = rush
        inst$archive$rush = rush
        worker_type = "debug_local"

        call_back("on_worker_begin", inst$objective$callbacks, inst$objective$context)

        # run optimizer loop
        private$.optimize(inst)

        call_back("on_worker_end", inst$objective$callbacks, inst$objective$context)
      } else {
        # run .optimize() on workers
        rush = inst$rush
        worker_type = rush::rush_config()$worker_type %??% "mirai"

        if (worker_type == "script") {
          # worker script
          rush$worker_script(
            worker_loop = bbotk_worker_loop,
            packages = c(self$packages, inst$objective$packages, "bbotk"),
            optimizer = self,
            instance = inst
          )

          rush$wait_for_workers(n = 1)
        } else if (worker_type == "mirai") {
          # mirai workers
          worker_ids = rush$start_workers(
            n_workers = n_workers,
            worker_loop = bbotk_worker_loop,
            packages = c(self$packages, inst$objective$packages, "bbotk"),
            optimizer = self,
            instance = inst
          )

          rush$wait_for_workers(n = 1, worker_ids)
        } else if (worker_type == "processx") {
          # processx workers
          worker_ids = rush$start_local_workers(
            n_workers = n_workers,
            worker_loop = bbotk_worker_loop,
            packages = c(self$packages, inst$objective$packages, "bbotk"),
            optimizer = self,
            instance = inst
          )

          rush$wait_for_workers(n = 1, worker_ids)
        }
      }

      lg$info(
        "Starting to optimize %i parameter(s) with '%s' and '%s' on %s %s worker(s)",
        inst$search_space$length,
        self$format(),
        inst$terminator$format(with_params = TRUE),
        as.character(rush::rush_config()$n_workers %??% ""),
        worker_type
      )

      n_running_workers = 0
      # wait until optimization is finished
      # check terminated workers when the terminator is "none"
      while (!inst$is_terminated) {
        Sys.sleep(1)

        if (rush$n_running_workers > n_running_workers) {
          n_running_workers = rush$n_running_workers
          lg$info("%i worker(s) running", n_running_workers)
        }

        # print logger messages from workers
        rush$print_log()

        # print evaluations
        if (getOption("bbotk.tiny_logging", FALSE)) {
          tiny_logging(inst, self)
        } else {
          new_results = inst$rush$fetch_new_tasks()
          if (nrow(new_results)) {
            lg$info("Results of %i configuration(s):", nrow(new_results))
            setcolorder(new_results, c(inst$archive$cols_y, inst$archive$cols_x, "timestamp_xs", "timestamp_ys"))
            cns = setdiff(colnames(new_results), c("pid", "x_domain", "keys"))
            lg$info(capture.output(print(
              new_results[, cns, with = FALSE],
              class = FALSE,
              row.names = FALSE,
              print.keys = FALSE
            )))
          }
        }

        rush$detect_lost_workers()

        if (!rush$n_running_workers) {
          lg$info("All workers have terminated.")
          break
        }

        # check queue status and propose new points if needed
        # we need at least one finished evaluation to fit the surrogate
        n_finished = inst$archive$n_finished

        if (n_finished >= 1 && !inst$is_terminated) {
          # check if there are idle workers (not enough points in queue/running)
          # we want to keep the queue filled so workers don't idle
          n_queued = inst$archive$n_queued
          n_running = inst$archive$n_running

          # propose new points if queue is running low
          # aim to have at least n_workers points queued/running
          n_to_propose = max(0, rush$n_running_workers - n_queued - n_running)

          if (n_to_propose > 0) {
            for (i in seq_len(n_to_propose)) {
              if (inst$is_terminated) break

              # propose a new point using MBO
              # update surrogate on each iteration to account for newly queued points
              xdt = tryCatch(
                {
                  timestamp_surrogate = Sys.time()
                  self$acq_function$surrogate$update()
                  timestamp_acq_function = Sys.time()
                  self$acq_function$update()
                  timestamp_acq_optimizer = Sys.time()
                  xdt = self$acq_optimizer$optimize()
                  timestamp_loop = Sys.time()
                  set(xdt, j = "timestamp_surrogate", value = timestamp_surrogate)
                  set(xdt, j = "timestamp_acq_function", value = timestamp_acq_function)
                  set(xdt, j = "timestamp_acq_optimizer", value = timestamp_acq_optimizer)
                  set(xdt, j = "timestamp_loop", value = timestamp_loop)
                  xdt
                },
                Mlr3ErrorMbo = function(cond) {
                  lg$warn("Caught the following error: %s", cond$message)
                  lg$info("Proposing a randomly sampled point")
                  xdt = generate_design_random(inst$search_space, n = 1L)$data
                  set(xdt, j = "timestamp_surrogate", value = NA)
                  set(xdt, j = "timestamp_acq_function", value = NA)
                  set(xdt, j = "timestamp_acq_optimizer", value = NA)
                  set(xdt, j = "timestamp_loop", value = NA)
                  xdt
                }
              )
              # push the new point to the queue
              xs = transpose_list(xdt)[[1]]
              extra = xs[names(xs) %nin% inst$archive$cols_x]
              xs = xs[inst$archive$cols_x]
              inst$archive$push_points(list(xs), extra = list(extra))
              lg$debug("Proposed new point and pushed to queue")
            }
          }
        }
      }

      # remove queued tasks that were not evaluated before termination
      # running tasks are left to the workers that own them
      rush$empty_queue()

      if (!inst$archive$n_finished) {
        stopf("Optimization terminated without any finished evaluations.")
      }

      # final surrogate update
      tryCatch(
        {
          self$surrogate$update()
        },
        Mlr3ErrorMboSurrogateUpdate = function(error_condition) {
          lg$warn("Could not update the surrogate a final time after the optimization process has terminated.")
        }
      )

      # assign result
      private$.assign_result(inst)
      lg$info("Finished optimizing after %i evaluation(s)", inst$rush$n_finished_tasks)
      lg$info("Result:")

      # print result
      if (getOption("bbotk.tiny_logging", FALSE)) {
        bbotk::tiny_result(inst, self)
      } else {
        lg$info(capture.output(print(inst$result, class = FALSE, row.names = FALSE, print.keys = FALSE)))
      }

      call_back("on_optimization_end", inst$objective$callbacks, inst$objective$context)
      inst$rush$stop_workers(type = "kill")
      return(inst$result)
    }
  ),

  active = list(
    #' @template field_surrogate
    surrogate = function(rhs) {
      if (missing(rhs)) {
        private$.surrogate
      } else {
        private$.surrogate = assert_r6(rhs, classes = "SurrogateLearner", null.ok = TRUE)
      }
    },

    #' @template field_acq_function
    acq_function = function(rhs) {
      if (missing(rhs)) {
        private$.acq_function
      } else {
        private$.acq_function = assert_r6(rhs, classes = "AcqFunction", null.ok = TRUE)
      }
    },

    #' @template field_acq_optimizer
    acq_optimizer = function(rhs) {
      if (missing(rhs)) {
        private$.acq_optimizer
      } else {
        private$.acq_optimizer = assert_r6(rhs, classes = "AcqOptimizer", null.ok = TRUE)
      }
    },

    #' @template field_result_assigner
    result_assigner = function(rhs) {
      if (missing(rhs)) {
        private$.result_assigner
      } else {
        private$.result_assigner = assert_r6(rhs, classes = "ResultAssigner", null.ok = TRUE)
      }
    },

    #' @template field_param_classes
    param_classes = function(rhs) {
      if (missing(rhs)) {
        param_classes_surrogate = c("logical" = "ParamLgl", "integer" = "ParamInt", "numeric" = "ParamDbl", "factor" = "ParamFct")
        if (!is.null(self$surrogate)) {
          param_classes_surrogate = param_classes_surrogate[c("logical", "integer", "numeric", "factor") %in% self$surrogate$feature_types] # surrogate has precedence over acq_function$surrogate
        }
        param_classes_acq_opt = if (!is.null(self$acq_optimizer)) {
          self$acq_optimizer$optimizer$param_classes
        } else {
          c("ParamLgl", "ParamInt", "ParamDbl", "ParamFct")
        }
        unname(intersect(param_classes_surrogate, param_classes_acq_opt))
      } else {
        stop("$param_classes is read-only.")
      }
    },

    #' @template field_properties
    properties = function(rhs) {
      if (missing(rhs)) {
        properties_loop_function = "single-crit"
        properties_surrogate = "dependencies"
        if (!is.null(self$surrogate)) {
          if ("missings" %nin% self$surrogate$properties) {
            properties_surrogate = character()
          }
        }
        unname(c(properties_surrogate, properties_loop_function))
      } else {
        stop("$properties is read-only.")
      }
    },

    #' @template field_packages
    packages = function(rhs) {
      if (missing(rhs)) {
        union(c("mlr3mbo", "rush"), c(self$acq_function$packages, self$surrogate$packages, self$acq_optimizer$optimizer$packages, self$result_assigner$packages))
      } else {
        stop("$packages is read-only.")
      }
    }
  ),

  private = list(
    .surrogate = NULL,
    .acq_function = NULL,
    .acq_optimizer = NULL,
    .result_assigner = NULL,

    # Worker loop: continuously pop and evaluate points from the queue until terminated
    .optimize = function(inst) {
      while (!inst$is_terminated) {
        # try to pop a point from the queue
        task = inst$archive$pop_point()

        if (!is.null(task)) {
          # evaluate the point
          xs_trafoed = bbotk:::trafo_xs(task$xs, inst$search_space)

          mlr3misc::call_back("on_optimizer_queue_before_eval", inst$objective$callbacks, inst$objective$context)

          ys = inst$objective$eval(xs_trafoed)

          mlr3misc::call_back("on_optimizer_queue_after_eval", inst$objective$callbacks, inst$objective$context)

          inst$archive$push_result(task$key, ys, x_domain = xs_trafoed)
        } else {
          # no points in queue, wait for main process to add more
          Sys.sleep(0.1)
        }
      }
    },

    .assign_result = function(inst) {
      self$result_assigner$assign_result(inst)
    }
  )
)
