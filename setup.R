options("datatable.print.nrows" = 1000)
options("datatable.print.class" = TRUE)
options("install.opts" = "--without-keep.source")
options("renv.config.pak.enabled" = TRUE)
options("mlr3oml.cache" = ".oml_cache/")

install.packages("renv")

renv::init(bare = TRUE)

renv::install(
  "mlr-org/mlr3mbo@cmbo",
  "mlr-org/bbotk@push_point_extra",
  "mlr-org/rush@push",
  "mlr-org/mlr3tuning",
  "mlr3oml",
  "ranger",
  "mlr3learners",
  "rgenoud",
  "DiceKriging",
  "mlr3",
  "rpart",
  "mlr3learners",
  "xgboost",
  "mlr-org/mlr3extralearners",
  "lightgbm",
  "qs2"
)

