# ==== MODEL EXPERIMENTS: XGBOOST & SVM (ADVANCED MODELING) ====
# Purpose: Compare Random Forest against Gradient Boosting and SVM
# Author: Gemini/Claude for COVID-19 Mortality Project

# 1. SETUP & LIBRARIES
library(tidymodels)
library(tidyverse)
library(xgboost)  # For Gradient Boosting
library(kernlab)  # For SVM
library(doParallel)
library(vip)

# 2. LOAD DATA & PREPROCESSING (STANDALONE MODE)
# Check if running standalone (Rscript) or sourced (interactive)
if(!exists("df_training") || !exists("rf_recipe")) {
  if(file.exists("data_training.rds") && file.exists("rf_recipe_master.rds")) {
    df_training <- readRDS("data_training.rds")
    df_testing <- readRDS("data_testing.rds")
    data_split <- readRDS("data_split.rds")
    rf_recipe <- readRDS("rf_recipe_master.rds")
    cat("✓ Loaded preprocessing objects from RDS files\n")
  } else {
    cat("⚠ Preprocessing objects missing. Running full pipeline...\n")
    source("Data_Cleaning_Organization.R")
    source("Random_Forest_Preprocess.R")
    cat("✓ Preprocessing pipeline completed\n")
  }
} else {
  cat("✓ Using preprocessing objects from current R session\n")
  # Ensure rf_recipe is loaded even if using session objects
  if(!exists("rf_recipe") && file.exists("rf_recipe_master.rds")) {
    rf_recipe <- readRDS("rf_recipe_master.rds")
  }
}

# Reuse the MASTER recipe (ensures apples-to-apples comparison)
# Note: XGBoost requires all dummy variables (one-hot), created by step_dummy
# SVM requires normalization, covered by step_normalize

# ==== 3. MODEL SPECIFICATIONS ====

# A. XGBoost (Gradient Boosting Trees)
xgb_spec <- boost_tree(
  trees = 1000, 
  tree_depth = tune(),         # Complexity of trees
  min_n = tune(),              # Min node size
  loss_reduction = tune(),     # Gamma 
  sample_size = tune(),        # Subsample
  mtry = tune(),               # Colsample_bytree
  learn_rate = tune()          # Eta
) %>% 
  set_engine("xgboost") %>% 
  set_mode("classification")

# B. SVM (Radial Basis Function - Non-Linear)
svm_spec <- svm_rbf(
  cost = tune(), 
  rbf_sigma = tune()
) %>%
  set_engine("kernlab") %>%
  set_mode("classification")

# ==== 4. WORKFLOWS ====

xgb_workflow <- workflow() %>% 
  add_recipe(rf_recipe) %>%
  add_model(xgb_spec)

svm_workflow <- workflow() %>%
  add_recipe(rf_recipe) %>% 
  add_model(svm_spec)

# ==== 5. HYPERPARAMETER TUNING (GRID SEARCH) ====

# Tuning grids (ENHANCED FOR PUBLICATION - 40 combinations)
# XGBoost: Space-filling latin hypercube with data-informed ranges
# Justification:
# - 40 samples for 6D space provides better coverage than original 20
# - Ranges tightened based on XGBoost best practices for imbalanced medical data
# - Avoids extreme/unlikely parameter values for computational efficiency
set.seed(2026)
xgb_grid <- grid_latin_hypercube(
  tree_depth(range = c(3, 10)),          # Narrowed from [1,15] - avoid extreme shallow/deep
  min_n(range = c(5, 30)),               # Tightened from [2,40] - typical optimum range
  loss_reduction(range = c(0, 5)),       # Reduced from [0,10] - gamma rarely >5 optimal
  sample_size = sample_prop(c(0.6, 1.0)), # Raised from 0.5 - subsample 60-100%
  finalize(mtry(), df_training),         # Adaptive to feature count
  learn_rate(range = c(0.01, 0.3)),      # Narrowed from [0.001,0.1] - avoid extreme slow learning
  size = 40                               # Doubled from 20 combinations
)

set.seed(2026)
# SVM Grid (ENHANCED FOR PUBLICATION - 49 combinations)
# Justification:
# - Imbalanced data (16% mortality) requires higher cost values (penalize misclassification)
# - RBF sigma on log scale for proper kernel-scale exploration
# - 49 combinations (7×7) thorough for only 2 parameters
svm_grid <- grid_regular(
  cost(range = c(-2, 2), trans = log10_trans()),  # 0.01 to 100 on log scale
  rbf_sigma(range = c(-3, -0.5), trans = log10_trans()), # 0.001 to 0.316 (kernel-appropriate)
  levels = 7  # 7×7 = 49 combinations
)

# Parallel Processing
all_cores <- detectCores(logical = FALSE)
cl <- makePSOCKcluster(all_cores - 1)
registerDoParallel(cl)

# Create CV Folds (Missing from Preprocess script)
set.seed(2026)
cv_folds <- vfold_cv(df_training, v = 5, strata = desenlace)

print("--- Starting XGBoost Tuning ---")
set.seed(2026)
xgb_res <- tune_grid(
  xgb_workflow,
  resamples = cv_folds, # Utilizing the same CV folds from RF script
  grid = xgb_grid,
  metrics = metric_set(roc_auc, sensitivity, specificity, pr_auc),
  control = control_grid(save_pred = TRUE, verbose = TRUE)
)

print("--- Starting SVM Tuning ---")
set.seed(2026)
svm_res <- tune_grid(
  svm_workflow,
  resamples = cv_folds,
  grid = svm_grid,
  metrics = metric_set(roc_auc, sensitivity, specificity, pr_auc),
  control = control_grid(save_pred = TRUE, verbose = TRUE)
)

stopCluster(cl)
registerDoSEQ()

# ==== 5.5 HYPERPARAMETER SENSITIVITY ANALYSIS ====
# Publication-quality reporting of hyperparameter impact

print("--- XGBOOST TOP 5 CONFIGURATIONS ---")
xgb_top5 <- show_best(xgb_res, n = 5, metric = "roc_auc")
print(xgb_top5)

print("--- SVM TOP 5 CONFIGURATIONS ---")
svm_top5 <- show_best(svm_res, n = 5, metric = "roc_auc")
print(svm_top5)

# Visualize hyperparameter sensitivity
plot_xgb_sensitivity <- autoplot(xgb_res, metric = "roc_auc") +
  ggtitle("XGBoost Hyperparameter Sensitivity",
          subtitle = "ROC-AUC across parameter space (40 configurations)") +
  theme_minimal()

plot_svm_sensitivity <- autoplot(svm_res, metric = "roc_auc") +
  ggtitle("SVM Hyperparameter Sensitivity",
          subtitle = "ROC-AUC across cost and RBF sigma (49 configurations)") +
  theme_minimal()

print(plot_xgb_sensitivity)
print(plot_svm_sensitivity)

# Save sensitivity plots for publication
ggsave("Figure_XGBoost_Sensitivity.png", plot_xgb_sensitivity, width = 10, height = 6, dpi = 300)
ggsave("Figure_SVM_Sensitivity.png", plot_svm_sensitivity, width = 10, height = 6, dpi = 300)

# ==== 6. SELECT BEST MODELS ====

# XGBoost Best
best_xgb <- select_best(xgb_res, metric = "roc_auc")
print("Best XGBoost Parameters:")
print(best_xgb)
final_xgb_workflow <- finalize_workflow(xgb_workflow, best_xgb)

# SVM Best
best_svm <- select_best(svm_res, metric = "roc_auc")
print("Best SVM Parameters:")
print(best_svm)
final_svm_workflow <- finalize_workflow(svm_workflow, best_svm)

# ==== 7. FINAL EVALUATION (TEST SET) ====

# Fit XGBoost
fit_xgb <- last_fit(final_xgb_workflow, data_split)
metrics_xgb <- collect_metrics(fit_xgb) %>% mutate(Model = "XGBoost")

# Fit SVM
fit_svm <- last_fit(final_svm_workflow, data_split)
metrics_svm <- collect_metrics(fit_svm) %>% mutate(Model = "SVM (RBF)")

# Load Reference RF Metrics (if available, else placeholder)
# metrics_rf <- collect_metrics(final_fit) %>% mutate(Model = "Random Forest")

# Combine results
comparison_table <- bind_rows(metrics_xgb, metrics_svm) %>%
  filter(.metric == "roc_auc") %>%
  select(Model, .estimate) %>%
  arrange(desc(.estimate))

print("--- FINAL LEADERSHIP BOARD (ROC-AUC) ---")
print(comparison_table)

# ==== 8. SAVE MODELS ====
saveRDS(fit_xgb, "model_xgboost_fit.rds")
saveRDS(fit_svm, "model_svm_fit.rds")
