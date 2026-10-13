# Generate the renv.lock file for DUC7 app in EDITO

# 1. Check and install renv is absent
if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org/")
}

library(renv)

# 2. List of required packages
app_packages <- c("shiny",
                  "bslib",
                  "xgboost",
                  "terra",
                  "dplyr",
                  "tidyr",
                  "readr",
                  "ggplot2",
                  "maps")

# 3. Initialisation of renv in bare mode
if (!file.exists("renv.lock")) {
  renv::init(bare = TRUE, restart = FALSE)
}

# 4. Analysis of .R/.Rmd file in the project (but not this script)
r_files <- list.files(path = ".", 
                      pattern = "\\.(R|Rmd)$", 
                      recursive = TRUE, 
                      full.names = TRUE)

# Exclude this script
r_files <- r_files[!grepl("create_renv_lock\\.R$", r_files)]

detected_pkgs <- character(0)
if (length(r_files) > 0) {
  deps_list <- lapply(r_files, function(f) {
    message("Analyse des dépendances dans : ", f)
    tryCatch(renv::dependencies(f)$Package, error = function(e) character(0))
  })
  detected_pkgs <- unlist(deps_list)
}

# 5. Clean package list
all_pkgs <- unique(c(app_packages, detected_pkgs))

# Remove duplicates and base/system packages
base_packages <- c("R", "base", "stats", "utils", "methods", "graphics", "grDevices", "grid", "compiler", "tools", "parallel")
pkgs_to_snapshot <- setdiff(all_pkgs, base_packages)

message("\nThe following packages will be registered in renv.lock:")
print(pkgs_to_snapshot)

# 6. Generate renv.lock file
renv::snapshot(packages = pkgs_to_snapshot, prompt = FALSE)

message("\nrenv.lock file was successfully created!")