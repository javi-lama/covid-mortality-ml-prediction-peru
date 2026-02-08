# ==============================================================================
# MULTI-MODEL COMPARISON: STATISTICAL PERFORMANCE METRICS
# ==============================================================================
# Purpose: Generate Table 3, Table 3B, and Table S1 for scientific publication
# Author: COVID-19 Mortality Prediction Project
# Date: 2026-02-08
# Seed: 2026 (reproducibility)
#
# IMPORTANT: Explicit namespacing (package::function) used throughout to prevent
# function name collisions between packages (e.g., dplyr vs stats, pROC vs yardstick)
# ==============================================================================

# ==============================================================================
# SECTION 0: LIBRARY LOADING WITH CONFLICT MANAGEMENT
# ==============================================================================

# Load packages - ORDER MATTERS for conflict priority
# Later packages mask earlier ones, but we use explicit namespacing anyway

suppressPackageStartupMessages({
  library(tidymodels)      # Loads dplyr, ggplot2, recipes, workflows, etc.
  library(tidyverse)       # Data manipulation
  library(pROC)            # ROC analysis, DeLong tests, bootstrap CI
  library(yardstick)       # PR-AUC, Brier score, classification metrics
  library(probably)        # Calibration analysis
  library(broom)           # Tidy model outputs
})

# Set seed for reproducibility
set.seed(2026)

# Suppress scientific notation
options(scipen = 999)

cat("═══════════════════════════════════════════════════════════════\n")
cat("MULTI-MODEL COMPARISON SCRIPT INITIALIZED\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Seed: 2026\n\n")

# ==============================================================================
# SECTION 1: LOAD DATA AND MODELS
# ==============================================================================

cat("--- SECTION 1: Loading Data and Models ---\n")

# Load test and training data
df_testing <- readRDS("data_testing.rds")
df_training <- readRDS("data_training.rds")
rf_recipe <- readRDS("rf_recipe_master.rds")

# Load Random Forest workflow (already fitted)
model_rf <- readRDS("modelo_rf_covid.rds")  # This is a workflow object

# Load XGBoost and SVM (saved as last_fit objects)
fit_xgb <- readRDS("model_xgboost_fit.rds")  # last_fit object
fit_svm <- readRDS("model_svm_fit.rds")      # last_fit object

# Extract fitted workflows from last_fit objects
# NOTE: extract_workflow() from tune package - no namespace needed as tidymodels loads it
model_xgb <- extract_workflow(fit_xgb)
model_svm <- extract_workflow(fit_svm)

# VALIDATION CHECKPOINT 1
cat("\n=== CHECKPOINT 1: Model Loading ===\n")
cat("RF class:", class(model_rf)[1], "\n")
cat("XGB class:", class(model_xgb)[1], "\n")
cat("SVM class:", class(model_svm)[1], "\n")
cat("Test set dimensions:", nrow(df_testing), "x", ncol(df_testing), "\n")
cat("Training set dimensions:", nrow(df_training), "x", ncol(df_training), "\n")
cat("Mortality rate (test):", round(mean(df_testing$desenlace == "Fallecido") * 100, 1), "%\n")

# ==============================================================================
# SECTION 2: RECREATE LOGISTIC REGRESSION (NO SMOTE - BASELINE)
# ==============================================================================

cat("\n--- SECTION 2: Recreating Logistic Regression (No SMOTE) ---\n")

# Specification (matches Comparison_DCA_LogReg.R lines 28-30)
glm_spec <- parsnip::logistic_reg() %>%
  parsnip::set_engine("glm") %>%
  parsnip::set_mode("classification")

# Recipe WITHOUT SMOTE (critical for fair baseline comparison)
# Uses same imputation and normalization as ML models
glm_recipe <- recipes::recipe(desenlace ~ ., data = df_training) %>%
  recipes::step_impute_knn(recipes::all_numeric_predictors(), neighbors = 5) %>%
  recipes::step_impute_mode(recipes::all_nominal_predictors(), -recipes::all_outcomes()) %>%
  recipes::step_dummy(recipes::all_nominal_predictors(), -recipes::all_outcomes()) %>%
  recipes::step_normalize(recipes::all_numeric_predictors())
  # NOTE: NO step_smote() - this is intentional for baseline comparison

# Workflow and fit
glm_workflow <- workflows::workflow() %>%
  workflows::add_recipe(glm_recipe) %>%
  workflows::add_model(glm_spec)

set.seed(2026)
model_logreg <- parsnip::fit(glm_workflow, data = df_training)

# VALIDATION CHECKPOINT 2
cat("\n=== CHECKPOINT 2: LogReg Recreation ===\n")
cat("LogReg class:", class(model_logreg)[1], "\n")
cat("LogReg fitted: TRUE\n")

# ==============================================================================
# SECTION 3: GENERATE PREDICTIONS ON TEST SET
# ==============================================================================

cat("\n--- SECTION 3: Generating Predictions ---\n")

# Function to generate standardized predictions
# Uses explicit namespacing for dplyr functions to avoid conflicts with stats/MASS
generate_predictions <- function(model, test_data, model_name) {
  preds_prob <- predict(model, test_data, type = "prob")
  preds_class <- predict(model, test_data, type = "class")

  result <- dplyr::bind_cols(preds_prob, preds_class) %>%
    dplyr::bind_cols(test_data %>% dplyr::select(desenlace)) %>%
    dplyr::mutate(model = model_name)

  # tidymodels already names columns correctly based on factor levels:
  # .pred_Fallecido (column 1) and .pred_Vivo (column 2)
  # Just rename the class prediction column for consistency
  names(result)[3] <- ".pred_class"

  return(result)
}

# Generate predictions for each model
set.seed(2026)
preds_rf <- generate_predictions(model_rf, df_testing, "Random Forest")
preds_xgb <- generate_predictions(model_xgb, df_testing, "XGBoost")
preds_svm <- generate_predictions(model_svm, df_testing, "SVM-RBF")
preds_logreg <- generate_predictions(model_logreg, df_testing, "Logistic Regression")

# Combine all predictions
all_predictions <- dplyr::bind_rows(preds_rf, preds_xgb, preds_svm, preds_logreg)

# VALIDATION CHECKPOINT 3
cat("\n=== CHECKPOINT 3: Predictions Generated ===\n")
cat("Total predictions:", nrow(all_predictions), "\n")
cat("Predictions per model:", nrow(preds_rf), "\n")
cat("Models:", paste(unique(all_predictions$model), collapse = ", "), "\n")
cat("Missing values:", sum(is.na(all_predictions$.pred_Fallecido)), "\n")

# ==============================================================================
# SECTION 4: CREATE pROC OBJECTS
# ==============================================================================

cat("\n--- SECTION 4: Creating pROC Objects ---\n")

# pROC requires: levels = c("control", "case")
# In this study: Vivo = control, Fallecido = case

# NOTE: direction = "<" means controls (Vivo) have LOWER predictor values
# This is CORRECT because .pred_Fallecido should be HIGH for deaths
# BUT if AUC < 0.5, pROC will auto-correct. Let pROC auto-detect direction.

roc_rf <- pROC::roc(response = df_testing$desenlace,
                    predictor = preds_rf$.pred_Fallecido,
                    levels = c("Vivo", "Fallecido"),
                    quiet = TRUE)

roc_xgb <- pROC::roc(response = df_testing$desenlace,
                     predictor = preds_xgb$.pred_Fallecido,
                     levels = c("Vivo", "Fallecido"),
                     quiet = TRUE)

roc_svm <- pROC::roc(response = df_testing$desenlace,
                     predictor = preds_svm$.pred_Fallecido,
                     levels = c("Vivo", "Fallecido"),
                     quiet = TRUE)

roc_logreg <- pROC::roc(response = df_testing$desenlace,
                        predictor = preds_logreg$.pred_Fallecido,
                        levels = c("Vivo", "Fallecido"),
                        quiet = TRUE)

# Store in named lists for iteration
roc_list <- list(
  "Random Forest" = roc_rf,
  "XGBoost" = roc_xgb,
  "SVM-RBF" = roc_svm,
  "Logistic Regression" = roc_logreg
)

preds_list <- list(
  "Random Forest" = preds_rf,
  "XGBoost" = preds_xgb,
  "SVM-RBF" = preds_svm,
  "Logistic Regression" = preds_logreg
)

# VALIDATION CHECKPOINT 4
cat("\n=== CHECKPOINT 4: ROC Objects ===\n")
for(name in names(roc_list)) {
  cat(name, "AUC:", round(pROC::auc(roc_list[[name]]), 4), "\n")
}

# ==============================================================================
# SECTION 5: ROC-AUC WITH 95% BOOTSTRAP CI (B=2000)
# ==============================================================================

cat("\n--- SECTION 5: Computing ROC-AUC with Bootstrap CI ---\n")

compute_auc_ci <- function(roc_obj, model_name, boot_n = 2000, seed = 2026) {
  set.seed(seed)
  cat("  Computing CI for", model_name, "...\n")

  # pROC::ci.auc - explicit namespace
  ci_result <- pROC::ci.auc(roc_obj, method = "bootstrap", boot.n = boot_n,
                            progress = "none")

  tibble::tibble(
    Model = model_name,
    AUC = ci_result[2],
    AUC_lower = ci_result[1],
    AUC_upper = ci_result[3]
  )
}

# Compute for all models
auc_results <- purrr::map2_dfr(
  roc_list, names(roc_list),
  ~compute_auc_ci(.x, .y, boot_n = 2000)
)

cat("\n=== CHECKPOINT 5: AUC with 95% CI ===\n")
print(auc_results)

# ==============================================================================
# SECTION 6: YOUDEN-OPTIMIZED THRESHOLDS AND CLASSIFICATION METRICS
# ==============================================================================

cat("\n--- SECTION 6: Computing Youden Thresholds and Classification Metrics ---\n")

compute_optimal_metrics <- function(roc_obj, preds_df, model_name, boot_n = 2000, seed = 2026) {
  cat("  Computing metrics for", model_name, "...\n")

  # Set seed for reproducibility of random tie-breaking
  set.seed(seed)

  # Get optimal threshold using Youden's J (pROC::coords)
  # best.policy = "random" handles ties, with seed set above for reproducibility
  optimal <- pROC::coords(roc_obj, x = "best", best.method = "youden",
                          ret = c("threshold", "sensitivity", "specificity",
                                  "ppv", "npv"),
                          transpose = FALSE,
                          best.policy = "random")

  # Bootstrap CI for sensitivity, specificity, ppv, npv (pROC::ci.coords)
  # Set seed again for bootstrap reproducibility
  set.seed(seed)
  ci_metrics <- pROC::ci.coords(roc_obj, x = "best", best.method = "youden",
                                ret = c("sensitivity", "specificity", "ppv", "npv"),
                                boot.n = boot_n,
                                best.policy = "random")

  # Apply threshold to get predicted classes
  threshold <- optimal$threshold[1]  # Take first if multiple
  pred_class <- ifelse(preds_df$.pred_Fallecido >= threshold,
                       "Fallecido", "Vivo")
  pred_class <- factor(pred_class, levels = c("Fallecido", "Vivo"))

  # Create confusion matrix for Kappa (yardstick::conf_mat)
  cm_data <- tibble::tibble(
    truth = preds_df$desenlace,
    estimate = pred_class
  )
  cm <- yardstick::conf_mat(cm_data, truth = truth, estimate = estimate)

  # Calculate Cohen's Kappa
  kappa_val <- summary(cm) %>%
    dplyr::filter(.metric == "kap") %>%
    dplyr::pull(.estimate)

  tibble::tibble(
    Model = model_name,
    Threshold = threshold,
    Sensitivity = optimal$sensitivity[1],
    Sens_lower = ci_metrics$sensitivity[1],
    Sens_upper = ci_metrics$sensitivity[3],
    Specificity = optimal$specificity[1],
    Spec_lower = ci_metrics$specificity[1],
    Spec_upper = ci_metrics$specificity[3],
    PPV = optimal$ppv[1],
    PPV_lower = ci_metrics$ppv[1],
    PPV_upper = ci_metrics$ppv[3],
    NPV = optimal$npv[1],
    NPV_lower = ci_metrics$npv[1],
    NPV_upper = ci_metrics$npv[3],
    Kappa = kappa_val
  )
}

# Compute for all models
classification_metrics <- purrr::map2_dfr(
  names(roc_list), names(preds_list),
  function(roc_name, preds_name) {
    compute_optimal_metrics(roc_list[[roc_name]], preds_list[[preds_name]], roc_name)
  }
)

cat("\n=== CHECKPOINT 6: Classification Metrics ===\n")
print(classification_metrics %>% dplyr::select(Model, Threshold, Sensitivity, Specificity, Kappa))

# ==============================================================================
# SECTION 7: PR-AUC (PRECISION-RECALL AUC)
# ==============================================================================

cat("\n--- SECTION 7: Computing PR-AUC ---\n")

# Using yardstick::pr_auc() - explicit namespace to avoid pROC conflict
compute_pr_auc <- function(preds_df, model_name) {
  cat("  Computing PR-AUC for", model_name, "...\n")

  # Prepare data frame for yardstick
  pr_data <- tibble::tibble(
    truth = preds_df$desenlace,
    .pred_Fallecido = preds_df$.pred_Fallecido
  )

  # yardstick::pr_auc requires event_level = "first" if positive class is first level
  # Check factor levels
  if(levels(pr_data$truth)[1] == "Fallecido") {
    event_lvl <- "first"
  } else {
    event_lvl <- "second"
  }

  pr_result <- yardstick::pr_auc(pr_data, truth = truth, .pred_Fallecido,
                                  event_level = event_lvl)

  pr_result$.estimate
}

pr_auc_results <- tibble::tibble(
  Model = names(preds_list),
  PR_AUC = purrr::map_dbl(names(preds_list), ~compute_pr_auc(preds_list[[.x]], .x))
)

cat("\n=== CHECKPOINT 7: PR-AUC ===\n")
print(pr_auc_results)

# ==============================================================================
# SECTION 8: BRIER SCORE
# ==============================================================================

cat("\n--- SECTION 8: Computing Brier Score ---\n")

# Brier Score = mean((p - y)^2) where y is 0/1
compute_brier <- function(preds_df, model_name) {
  cat("  Computing Brier Score for", model_name, "...\n")

  y <- ifelse(preds_df$desenlace == "Fallecido", 1, 0)
  p <- preds_df$.pred_Fallecido
  mean((p - y)^2)
}

brier_results <- tibble::tibble(
  Model = names(preds_list),
  Brier_Score = purrr::map_dbl(names(preds_list), ~compute_brier(preds_list[[.x]], .x))
)

cat("\n=== CHECKPOINT 8: Brier Score ===\n")
print(brier_results)

# ==============================================================================
# SECTION 9: DELONG PAIRWISE TESTS (ALL 6 PAIRS)
# ==============================================================================

cat("\n--- SECTION 9: DeLong Pairwise Tests ---\n")

# Define all 6 model pairs
model_pairs <- list(
  c("Random Forest", "XGBoost"),
  c("Random Forest", "SVM-RBF"),
  c("Random Forest", "Logistic Regression"),
  c("XGBoost", "SVM-RBF"),
  c("XGBoost", "Logistic Regression"),
  c("SVM-RBF", "Logistic Regression")
)

perform_delong_test <- function(pair, roc_list) {
  cat("  Testing:", pair[1], "vs", pair[2], "...\n")

  roc1 <- roc_list[[pair[1]]]
  roc2 <- roc_list[[pair[2]]]

  # pROC::roc.test for DeLong test
  test_result <- pROC::roc.test(roc1, roc2, method = "delong")

  # Convert auc objects to numeric to avoid bind_rows() class conflict
  auc1 <- as.numeric(pROC::auc(roc1))
  auc2 <- as.numeric(pROC::auc(roc2))

  tibble::tibble(
    Model_1 = pair[1],
    Model_2 = pair[2],
    AUC_1 = auc1,
    AUC_2 = auc2,
    Delta_AUC = auc1 - auc2,
    Z_statistic = as.numeric(test_result$statistic),
    p_value = test_result$p.value,
    Significant_0.05 = test_result$p.value < 0.05
  )
}

delong_results <- purrr::map_dfr(model_pairs, perform_delong_test, roc_list = roc_list)

cat("\n=== CHECKPOINT 9: DeLong Pairwise Tests ===\n")
print(delong_results %>% dplyr::select(Model_1, Model_2, Delta_AUC, p_value, Significant_0.05))

# SCIENTIFIC INTEGRITY CHECK
rf_vs_logreg <- delong_results %>%
  dplyr::filter(Model_1 == "Random Forest" & Model_2 == "Logistic Regression")

cat("\n╔══════════════════════════════════════════════════════════════╗\n")
cat("║              SCIENTIFIC INTEGRITY CHECK                      ║\n")
cat("╠══════════════════════════════════════════════════════════════╣\n")
cat("║ RF vs LogReg p-value:", sprintf("%.4f", rf_vs_logreg$p_value), "                          ║\n")
if(rf_vs_logreg$p_value > 0.05) {
  cat("║ CONFIRMED: RF does NOT statistically outperform LogReg      ║\n")
  cat("║ All claims must reflect 'comparable performance'            ║\n")
} else {
  cat("║ WARNING: Unexpected result - RF vs LogReg is significant    ║\n")
}
cat("╚══════════════════════════════════════════════════════════════╝\n")

# ==============================================================================
# SECTION 10: CALIBRATION METRICS (SLOPE, INTERCEPT)
# ==============================================================================

cat("\n--- SECTION 10: Computing Calibration Metrics ---\n")

# Calibration assessed by regressing observed outcomes on logit(predicted)
# Ideal calibration: intercept = 0, slope = 1

compute_calibration_metrics <- function(preds_df, model_name) {
  cat("  Computing calibration for", model_name, "...\n")

  # Convert outcome to 0/1
  y <- ifelse(preds_df$desenlace == "Fallecido", 1, 0)
  p <- preds_df$.pred_Fallecido

  # Avoid log(0) and log(1)
  p_clipped <- pmin(pmax(p, 0.001), 0.999)
  logit_p <- log(p_clipped / (1 - p_clipped))

  # Logistic regression: observed ~ logit(predicted)
  # Using stats::glm explicitly
  cal_model <- stats::glm(y ~ logit_p, family = stats::binomial(link = "logit"))

  # Extract coefficients
  coefs <- summary(cal_model)$coefficients

  tibble::tibble(
    Model = model_name,
    Intercept = coefs[1, 1],
    Intercept_SE = coefs[1, 2],
    Intercept_p = coefs[1, 4],
    Slope = coefs[2, 1],
    Slope_SE = coefs[2, 2],
    Slope_p = coefs[2, 4]
  )
}

calibration_results <- purrr::map_dfr(
  names(preds_list),
  ~compute_calibration_metrics(preds_list[[.x]], .x)
)

cat("\n=== CHECKPOINT 10: Calibration Metrics ===\n")
print(calibration_results %>% dplyr::select(Model, Intercept, Slope))
cat("Note: Ideal calibration: Intercept=0, Slope=1\n")

# ==============================================================================
# SECTION 11: ASSEMBLE TABLE 3 (PERFORMANCE METRICS)
# ==============================================================================

cat("\n--- SECTION 11: Assembling Table 3 ---\n")

# Merge all metrics
Table_3 <- auc_results %>%
  dplyr::left_join(pr_auc_results, by = "Model") %>%
  dplyr::left_join(brier_results, by = "Model") %>%
  dplyr::left_join(classification_metrics, by = "Model") %>%
  dplyr::select(
    Model,
    AUC, AUC_lower, AUC_upper,
    PR_AUC,
    Brier_Score,
    Sensitivity, Sens_lower, Sens_upper,
    Specificity, Spec_lower, Spec_upper,
    PPV, PPV_lower, PPV_upper,
    NPV, NPV_lower, NPV_upper,
    Kappa,
    Threshold
  )

# Format for publication (with CI strings)
Table_3_formatted <- Table_3 %>%
  dplyr::mutate(
    `ROC-AUC (95% CI)` = paste0(round(AUC, 3), " (",
                                 round(AUC_lower, 3), "-",
                                 round(AUC_upper, 3), ")"),
    `Sensitivity (95% CI)` = paste0(round(Sensitivity, 2), " (",
                                     round(Sens_lower, 2), "-",
                                     round(Sens_upper, 2), ")"),
    `Specificity (95% CI)` = paste0(round(Specificity, 2), " (",
                                     round(Spec_lower, 2), "-",
                                     round(Spec_upper, 2), ")"),
    `PPV (95% CI)` = paste0(round(PPV, 2), " (",
                            round(PPV_lower, 2), "-",
                            round(PPV_upper, 2), ")"),
    `NPV (95% CI)` = paste0(round(NPV, 2), " (",
                            round(NPV_lower, 2), "-",
                            round(NPV_upper, 2), ")"),
    `PR-AUC` = round(PR_AUC, 3),
    `Brier Score` = round(Brier_Score, 4),
    `Cohen's Kappa` = round(Kappa, 3),
    `Optimal Threshold` = round(Threshold, 3)
  ) %>%
  dplyr::select(Model, `ROC-AUC (95% CI)`, `PR-AUC`, `Brier Score`,
         `Sensitivity (95% CI)`, `Specificity (95% CI)`,
         `PPV (95% CI)`, `NPV (95% CI)`, `Cohen's Kappa`,
         `Optimal Threshold`)

# Export raw and formatted
write.csv(Table_3, "Table_3_Performance_Raw.csv", row.names = FALSE)
write.csv(Table_3_formatted, "Table_3_Performance.csv", row.names = FALSE)
cat("Saved: Table_3_Performance.csv\n")
cat("Saved: Table_3_Performance_Raw.csv\n")

# ==============================================================================
# SECTION 12: ASSEMBLE TABLE 3B (DELONG MATRIX)
# ==============================================================================

cat("\n--- SECTION 12: Assembling Table 3B ---\n")

Table_3B <- delong_results %>%
  dplyr::mutate(
    Comparison = paste0(Model_1, " vs ", Model_2),
    Delta_AUC = round(Delta_AUC, 4),
    Z_statistic = round(Z_statistic, 3),
    p_value = round(p_value, 4)
  ) %>%
  dplyr::select(Comparison, Delta_AUC, Z_statistic, p_value, Significant_0.05)

write.csv(Table_3B, "Table_3B_DeLong_Matrix.csv", row.names = FALSE)
cat("Saved: Table_3B_DeLong_Matrix.csv\n")

# ==============================================================================
# SECTION 13: ASSEMBLE TABLE S1 (CALIBRATION METRICS)
# ==============================================================================

cat("\n--- SECTION 13: Assembling Table S1 ---\n")

Table_S1 <- calibration_results %>%
  dplyr::mutate(
    Intercept = round(Intercept, 3),
    Intercept_SE = round(Intercept_SE, 3),
    Intercept_p = round(Intercept_p, 4),
    Slope = round(Slope, 3),
    Slope_SE = round(Slope_SE, 3),
    Slope_p = round(Slope_p, 4)
  ) %>%
  dplyr::select(Model, Intercept, Intercept_SE, Intercept_p,
         Slope, Slope_SE, Slope_p)

write.csv(Table_S1, "Table_S1_Calibration_Metrics.csv", row.names = FALSE)
cat("Saved: Table_S1_Calibration_Metrics.csv\n")

# ==============================================================================
# SECTION 14: SAVE ROC OBJECTS FOR FIGURES SCRIPT
# ==============================================================================

cat("\n--- SECTION 14: Saving Objects for Figures Script ---\n")

# Save objects for Multi_Model_Figures.R
saveRDS(roc_list, "roc_list_multimodel.rds")
saveRDS(preds_list, "preds_list_multimodel.rds")
saveRDS(auc_results, "auc_results_multimodel.rds")
saveRDS(model_logreg, "model_logreg_fit.rds")

cat("Saved: roc_list_multimodel.rds\n")
cat("Saved: preds_list_multimodel.rds\n")
cat("Saved: auc_results_multimodel.rds\n")
cat("Saved: model_logreg_fit.rds\n")

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("            MULTI-MODEL COMPARISON COMPLETE                    \n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("\nOutputs generated:\n")
cat("  1. Table_3_Performance.csv (formatted with CI strings)\n")
cat("  2. Table_3_Performance_Raw.csv (numeric values)\n")
cat("  3. Table_3B_DeLong_Matrix.csv (6 pairwise tests)\n")
cat("  4. Table_S1_Calibration_Metrics.csv (slope/intercept)\n")
cat("\nIntermediate objects for figures:\n")
cat("  5. roc_list_multimodel.rds\n")
cat("  6. preds_list_multimodel.rds\n")
cat("  7. auc_results_multimodel.rds\n")
cat("  8. model_logreg_fit.rds\n")
cat("\n═══════════════════════════════════════════════════════════════\n")

# Print final Table 3 to console
cat("\n=== TABLE 3: MULTI-MODEL PERFORMANCE COMPARISON ===\n\n")
print(Table_3_formatted, n = 4)

cat("\n=== TABLE 3B: DELONG PAIRWISE COMPARISONS ===\n\n")
print(Table_3B, n = 6)

cat("\n")
cat("Session Info:\n")
print(sessionInfo()$R.version$version.string)
cat("═══════════════════════════════════════════════════════════════\n")
