# Activate the renv project library on R startup. Without this, batchtools jobs
# launched on HyperQueue workers start a plain Rscript that cannot find
# batchtools/rush/etc. (they live in renv/library), so every task exits 1.
source("renv/activate.R")

options("datatable.print.nrows" = 1000)
options("datatable.print.class" = TRUE)
options("install.opts" = "--without-keep.source")
options("renv.config.pak.enabled" = TRUE)
options("mlr3oml.cache" = ".oml_cache/")
