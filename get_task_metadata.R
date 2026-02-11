library(mlr3oml)
library(mlr3)
library(data.table)
library(knitr)

# Task IDs from launch.R
task_ids = c(31L, 3945L, 7592L, 189354L)

# Function to extract metadata from a task
extract_metadata = function(otask_id) {
  otask = otsk(id = otask_id)
  task = as_task(otask)
  
  # Extract positive class
  pos_class = NA_character_
  if (task$task_type == "classif" && length(task$class_names) == 2L) {
    pos_class = task$positive
  }
  
  # Extract metadata
  metadata = data.table(
    task_id = otask_id,
    name = otask$name,
    n_instances = task$nrow,
    n_features = task$ncol - 1L,  # Exclude target
    n_classes = if (task$task_type == "classif") length(task$class_names) else NA_integer_,
    task_type = task$task_type,
    target = task$target_names,
    positive_class = pos_class
  )
  
  return(metadata)
}

# Extract metadata for all tasks
metadata_list = lapply(task_ids, extract_metadata)
metadata_dt = rbindlist(metadata_list)

# Convert to data.frame and clean up
metadata_df = as.data.frame(metadata_dt)

# Extract short name (e.g., "credit-g" from "Task 31: credit-g (Supervised Classification)")
metadata_df$name = sub("^Task \\d+: (.+?) \\(.*\\)$", "\\1", metadata_df$name)

# Remove columns: task_type, target, positive_class
metadata_df = metadata_df[, c("task_id", "name", "n_instances", "n_features", "n_classes")]

# Replace NA values with "-" for better display
metadata_df$n_classes[is.na(metadata_df$n_classes)] = "-"

# Rename columns for better display
colnames(metadata_df) = c("Task ID", "Name", "Instances", "Features", "Classes")

# Generate markdown table using knitr::kable
table_md = knitr::kable(metadata_df, format = "markdown", align = c("r", "l", "r", "r", "r"))

# Print to console
cat(table_md)
cat("\n\n")

# Save to file
writeLines(table_md, "task_metadata.md")
cat("Metadata table saved to task_metadata.md\n")
