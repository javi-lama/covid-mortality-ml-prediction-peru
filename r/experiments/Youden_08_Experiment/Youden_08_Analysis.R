# ==============================================================================
# WEIGHTED YOUDEN INDEX EXPERIMENT: w=0.8 OPTIMIZATION
# ==============================================================================
# Purpose: Compare sensitivity-weighted threshold optimization (w=0.8) vs standard
#          Youden J (w=1.0) for COVID-19 mortality prediction models
# Author: COVID-19 Mortality Prediction Project
# Date: 2026-02-17
# Seed: 2026 (reproducibility)
#
# METHODOLOGY:
# Standard Youden J:    J = Sensitivity + Specificity - 1
# Weighted Youden:      J_w = Sensitivity + (Specificity * w) - 1
#   where w < 1 penalizes specificity, favoring sensitivity (fewer false negatives)
#
# IMPORTANT: This script uses EXISTING ROC objects - NO model retraining
# ==============================================================================

# ==============================================================================
# SECTION 0: SETUP
# ==============================================================================

# Package loading
suppressPackageStartupMessages({
  library(tidymodels)
  library(tidyverse)
  library(pROC)
  library(patchwork)
  library(yardstick)
})

set.seed(2026)
options(scipen = 999)

# Set working directory to project root
setwd("/Users/javierlamaagurto/Documents/Research/Predicción Mortalidad COVID-19 ML/COVID-19_Mortality_Prediction_ML")

# Create output directory if needed
if (!dir.exists("results/youden_08")) {
  dir.create("results/youden_08", recursive = TRUE)
}

cat("===============================================================================\n")
cat("WEIGHTED YOUDEN INDEX EXPERIMENT INITIALIZED\n")
cat("===============================================================================\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Weight parameter: w = 0.8\n")
cat("Standard Youden: J = Sensitivity + Specificity - 1\n")
cat("Weighted Youden: J_w = Sensitivity + (Specificity * 0.8) - 1\n\n")

# ==============================================================================
# SECTION 1: LOAD EXISTING ROC OBJECTS
# ==============================================================================

cat("--- SECTION 1: Loading Existing ROC Objects ---\n")

# Load from Multi_Model_Comparison.R outputs
roc_list <- readRDS("roc_list_multimodel.rds")
preds_list <- readRDS("preds_list_multimodel.rds")
df_testing <- readRDS("data_testing.rds")

# Select main 4 models (exclude variants if present)
main_models <- c("Random Forest", "XGBoost", "SVM-RBF", "Logistic Regression")
available_models <- intersect(main_models, names(roc_list))

if (length(available_models) < 4) {
  cat("WARNING: Not all 4 main models found. Available models:\n")
  cat(paste(" -", names(roc_list), collapse = "\n"), "\n")
}

roc_list <- roc_list[available_models]
preds_list <- preds_list[available_models]

# VALIDATION CHECKPOINT 1
cat("\n=== CHECKPOINT 1: Data Loaded ===\n")
cat("Models loaded:", paste(names(roc_list), collapse = ", "), "\n")
cat("Test set: n =", nrow(df_testing), "\n")
n_deaths <- sum(df_testing$desenlace == "Fallecido")
n_survivors <- sum(df_testing$desenlace == "Vivo")
cat("Mortality cases (Fallecido):", n_deaths, "\n")
cat("Survival cases (Vivo):", n_survivors, "\n")

stopifnot("Test set should have 263 rows" = nrow(df_testing) == 263)
stopifnot("Should have 42 deaths" = n_deaths == 42)
cat("CHECKPOINT 1: PASSED\n")

# ==============================================================================
# SECTION 2: WEIGHTED YOUDEN FUNCTION DEFINITION
# ==============================================================================

cat("\n--- SECTION 2: Defining Weighted Youden Function ---\n")

#' Calculate weighted Youden index
#' @param sens Sensitivity value (0-1)
#' @param spec Specificity value (0-1)
#' @param w Weight for specificity (0-1). w=1.0 is standard Youden.
#'          w < 1 penalizes specificity, favoring sensitivity
#' @return Weighted Youden J value
weighted_youden <- function(sens, spec, w = 0.8) {
  return(sens + (spec * w) - 1)
}

#' Find optimal threshold using weighted Youden index
#' @param roc_obj pROC roc object
#' @param w Weight parameter for specificity
#' @return tibble with optimal threshold, sens, spec, and weighted J
find_weighted_optimal <- function(roc_obj, w) {
  # Extract all coordinates
  all_coords <- pROC::coords(roc_obj, "all",
                              ret = c("threshold", "sensitivity", "specificity"),
                              transpose = FALSE)

  # Remove infinite thresholds (boundary cases)
  all_coords <- all_coords[is.finite(all_coords$threshold), ]

  # Calculate weighted Youden for all thresholds
  all_coords$weighted_J <- weighted_youden(all_coords$sensitivity,
                                            all_coords$specificity, w)

  # Find optimal (maximum weighted J)
  optimal_idx <- which.max(all_coords$weighted_J)
  optimal <- all_coords[optimal_idx, ]

  return(tibble::tibble(
    threshold = optimal$threshold,
    sensitivity = optimal$sensitivity,
    specificity = optimal$specificity,
    weighted_J = optimal$weighted_J,
    weight = w
  ))
}

cat("Weighted Youden function defined\n")
cat("  Formula: J_w = Sensitivity + (Specificity * w) - 1\n")
cat("  For w=1.0: Standard Youden\n")
cat("  For w=0.8: 20% penalty on Specificity\n")

# ==============================================================================
# SECTION 3: VALIDATION - REPRODUCE w=1.0 (STANDARD YOUDEN)
# ==============================================================================

cat("\n--- SECTION 3: Validating w=1.0 Reproduces Original Results ---\n")

# Load original Table 3 for comparison
original_results <- tryCatch(
  read.csv("results/Table_3_Performance_Raw.csv"),
  error = function(e) {
    cat("WARNING: Table_3_Performance_Raw.csv not found. Using pROC directly.\n")
    return(NULL)
  }
)

# Calculate w=1.0 optimal for all models
baseline_results <- purrr::map_dfr(names(roc_list), function(model_name) {
  result <- find_weighted_optimal(roc_list[[model_name]], w = 1.0)
  result$model <- model_name
  return(result)
})

cat("\n=== w=1.0 BASELINE RESULTS (Custom Function) ===\n")
print(baseline_results %>%
        dplyr::select(model, threshold, sensitivity, specificity, weighted_J))

# Also verify with pROC's native Youden
cat("\n=== Verification with pROC::coords(best.method='youden') ===\n")
for (model_name in names(roc_list)) {
  set.seed(2026)
  pROC_optimal <- pROC::coords(roc_list[[model_name]], x = "best",
                                best.method = "youden",
                                ret = c("threshold", "sensitivity", "specificity"),
                                transpose = FALSE,
                                best.policy = "random")

  custom_thr <- baseline_results$threshold[baseline_results$model == model_name]
  pROC_thr <- pROC_optimal$threshold[1]

  match_status <- ifelse(abs(custom_thr - pROC_thr) < 0.0001, "MATCH", "DIFFER")
  cat(sprintf("  %s: Custom=%.4f, pROC=%.4f [%s]\n",
              model_name, custom_thr, pROC_thr, match_status))
}

# Compare with original Table 3 if available
if (!is.null(original_results)) {
  cat("\n=== Comparison with Original Table 3 ===\n")
  validation_check <- baseline_results %>%
    dplyr::left_join(
      original_results %>%
        dplyr::select(Model, Threshold_orig = Threshold,
                      Sens_orig = Sensitivity, Spec_orig = Specificity),
      by = c("model" = "Model")
    ) %>%
    dplyr::mutate(
      threshold_match = abs(threshold - Threshold_orig) < 0.001,
      sens_match = abs(sensitivity - Sens_orig) < 0.01,
      spec_match = abs(specificity - Spec_orig) < 0.01
    )

  print(validation_check %>%
          dplyr::select(model, threshold, Threshold_orig, threshold_match))
}

cat("\nCHECKPOINT 2: w=1.0 validation completed\n")

# ==============================================================================
# SECTION 4: WEIGHTED YOUDEN w=0.8 OPTIMIZATION
# ==============================================================================

cat("\n--- SECTION 4: Computing w=0.8 Optimal Thresholds ---\n")

# Calculate w=0.8 optimal for all models
weighted_results <- purrr::map_dfr(names(roc_list), function(model_name) {
  result <- find_weighted_optimal(roc_list[[model_name]], w = 0.8)
  result$model <- model_name
  return(result)
})

cat("\n=== w=0.8 WEIGHTED RESULTS ===\n")
print(weighted_results %>%
        dplyr::select(model, threshold, sensitivity, specificity, weighted_J))

# Combine baseline (w=1.0) and weighted (w=0.8)
combined_results <- dplyr::bind_rows(
  baseline_results %>% dplyr::mutate(weight_label = "w=1.0"),
  weighted_results %>% dplyr::mutate(weight_label = "w=0.8")
) %>%
  dplyr::arrange(model, weight_label)

cat("\n=== CHECKPOINT 3: Threshold Comparison ===\n")
comparison_summary <- combined_results %>%
  tidyr::pivot_wider(
    id_cols = model,
    names_from = weight_label,
    values_from = c(threshold, sensitivity, specificity)
  ) %>%
  dplyr::mutate(
    threshold_changed = abs(`threshold_w=1.0` - `threshold_w=0.8`) > 0.0001,
    delta_threshold = `threshold_w=0.8` - `threshold_w=1.0`,
    delta_sens = `sensitivity_w=0.8` - `sensitivity_w=1.0`,
    delta_spec = `specificity_w=0.8` - `specificity_w=1.0`
  )

print(comparison_summary %>%
        dplyr::select(model, `threshold_w=1.0`, `threshold_w=0.8`,
                      delta_threshold, threshold_changed))

# Identify which models changed
models_changed <- comparison_summary$model[comparison_summary$threshold_changed]
models_unchanged <- comparison_summary$model[!comparison_summary$threshold_changed]

cat("\nModels with threshold CHANGE:",
    ifelse(length(models_changed) > 0, paste(models_changed, collapse = ", "), "NONE"), "\n")
cat("Models with SAME threshold:",
    ifelse(length(models_unchanged) > 0, paste(models_unchanged, collapse = ", "), "NONE"), "\n")

# ==============================================================================
# SECTION 5: FULL METRICS CALCULATION AT EACH THRESHOLD
# ==============================================================================

cat("\n--- SECTION 5: Computing Full Metrics at Each Threshold ---\n")

#' Calculate all metrics at a given threshold
#' @param roc_obj pROC roc object
#' @param preds_df Predictions dataframe with .pred_Fallecido and desenlace
#' @param threshold Classification threshold
#' @param model_name Model identifier
#' @param weight_label Weight identifier (w=1.0 or w=0.8)
#' @return tibble with comprehensive metrics
calculate_metrics_at_threshold <- function(roc_obj, preds_df, threshold,
                                            model_name, weight_label) {
  # Apply threshold to get predictions
  pred_class <- ifelse(preds_df$.pred_Fallecido >= threshold, "Fallecido", "Vivo")
  pred_class <- factor(pred_class, levels = c("Fallecido", "Vivo"))
  truth <- factor(preds_df$desenlace, levels = c("Fallecido", "Vivo"))

  # Confusion matrix components
  TP <- sum(pred_class == "Fallecido" & truth == "Fallecido")
  TN <- sum(pred_class == "Vivo" & truth == "Vivo")
  FP <- sum(pred_class == "Fallecido" & truth == "Vivo")
  FN <- sum(pred_class == "Vivo" & truth == "Fallecido")

  # Calculate metrics
  sens <- TP / (TP + FN)
  spec <- TN / (TN + FP)
  ppv <- ifelse((TP + FP) > 0, TP / (TP + FP), NA)
  npv <- ifelse((TN + FN) > 0, TN / (TN + FN), NA)
  accuracy <- (TP + TN) / (TP + TN + FP + FN)

  # Youden indices
  youden_10 <- sens + spec - 1
  youden_08 <- weighted_youden(sens, spec, 0.8)

  # Cohen's Kappa
  cm_data <- tibble::tibble(truth = truth, estimate = pred_class)
  cm <- yardstick::conf_mat(cm_data, truth = truth, estimate = estimate)
  kappa_val <- summary(cm) %>%
    dplyr::filter(.metric == "kap") %>%
    dplyr::pull(.estimate)

  # F1 Score
  f1 <- ifelse((ppv + sens) > 0, 2 * (ppv * sens) / (ppv + sens), NA)

  tibble::tibble(
    Model = model_name,
    Weight = weight_label,
    Threshold = threshold,
    Sensitivity = sens,
    Specificity = spec,
    PPV = ppv,
    NPV = npv,
    Accuracy = accuracy,
    Youden_J_10 = youden_10,
    Youden_J_08 = youden_08,
    Kappa = kappa_val,
    F1 = f1,
    TP = TP,
    TN = TN,
    FP = FP,
    FN = FN
  )
}

# Calculate metrics for both weights across all models
full_metrics <- purrr::map_dfr(names(roc_list), function(model_name) {
  # Get thresholds for this model
  thr_10 <- baseline_results$threshold[baseline_results$model == model_name]
  thr_08 <- weighted_results$threshold[weighted_results$model == model_name]

  # Calculate metrics at w=1.0 threshold
  metrics_10 <- calculate_metrics_at_threshold(
    roc_list[[model_name]], preds_list[[model_name]],
    thr_10, model_name, "w=1.0"
  )

  # Calculate metrics at w=0.8 threshold
  metrics_08 <- calculate_metrics_at_threshold(
    roc_list[[model_name]], preds_list[[model_name]],
    thr_08, model_name, "w=0.8"
  )

  dplyr::bind_rows(metrics_10, metrics_08)
})

cat("\n=== CHECKPOINT 4: Full Metrics Computed ===\n")
print(full_metrics %>%
        dplyr::select(Model, Weight, Threshold, Sensitivity, Specificity, PPV, NPV))

# Verify no NaN values
if (any(is.na(full_metrics$NPV))) {
  cat("WARNING: Some NPV values are NA\n")
} else {
  cat("All NPV values are valid (not NA)\n")
}

# ==============================================================================
# SECTION 6: TABLE - YOUDEN COMPARISON (w=1.0 vs w=0.8)
# ==============================================================================

cat("\n--- SECTION 6: Creating Table_Youden_Comparison.csv ---\n")

# Reshape for side-by-side comparison
Table_Youden <- full_metrics %>%
  tidyr::pivot_wider(
    id_cols = Model,
    names_from = Weight,
    values_from = c(Threshold, Sensitivity, Specificity, PPV, NPV, Accuracy, Kappa, F1)
  ) %>%
  dplyr::mutate(
    Delta_Threshold = `Threshold_w=0.8` - `Threshold_w=1.0`,
    Delta_Sens = `Sensitivity_w=0.8` - `Sensitivity_w=1.0`,
    Delta_Spec = `Specificity_w=0.8` - `Specificity_w=1.0`,
    Delta_PPV = `PPV_w=0.8` - `PPV_w=1.0`,
    Delta_NPV = `NPV_w=0.8` - `NPV_w=1.0`,
    Threshold_Changed = abs(Delta_Threshold) > 0.0001
  )

# Print summary
cat("\n=== YOUDEN COMPARISON SUMMARY ===\n")
print(Table_Youden %>%
        dplyr::select(Model, `Threshold_w=1.0`, `Threshold_w=0.8`,
                      Delta_Threshold, Delta_Sens, Delta_Spec, Threshold_Changed))

write.csv(Table_Youden, "results/youden_08/Table_Youden_Comparison.csv",
          row.names = FALSE)
cat("\nSaved: results/youden_08/Table_Youden_Comparison.csv\n")

# ==============================================================================
# SECTION 7: TABLE - CLINICAL IMPACT ANALYSIS
# ==============================================================================

cat("\n--- SECTION 7: Creating Table_Clinical_Impact.csv ---\n")

# Clinical counts from confusion matrices
Table_Clinical <- full_metrics %>%
  dplyr::mutate(
    # Deaths correctly identified (True Positives)
    Deaths_Caught = TP,
    Deaths_Caught_Pct = sprintf("%.1f%%", (TP / n_deaths) * 100),

    # Deaths missed (False Negatives)
    Deaths_Missed = FN,
    Deaths_Missed_Pct = sprintf("%.1f%%", (FN / n_deaths) * 100),

    # False alarms (False Positives)
    False_Alarms = FP,
    False_Alarms_Pct = sprintf("%.1f%%", (FP / n_survivors) * 100),

    # Correctly identified survivors
    True_Negatives = TN,

    # NNS (Number Needed to Screen) = 1/PPV
    NNS = round(1 / PPV, 2)
  ) %>%
  dplyr::select(Model, Weight, Threshold,
                Deaths_Caught, Deaths_Caught_Pct,
                Deaths_Missed, Deaths_Missed_Pct,
                False_Alarms, False_Alarms_Pct,
                True_Negatives, NNS,
                Sensitivity, Specificity, PPV, NPV)

cat("\n=== CLINICAL IMPACT SUMMARY ===\n")
cat("Total deaths in test set:", n_deaths, "\n")
cat("Total survivors in test set:", n_survivors, "\n\n")

print(Table_Clinical %>%
        dplyr::select(Model, Weight, Deaths_Caught, Deaths_Missed,
                      False_Alarms, NNS))

# Calculate change from w=1.0 to w=0.8
Table_Clinical_Change <- Table_Clinical %>%
  dplyr::select(Model, Weight, Deaths_Caught, Deaths_Missed, False_Alarms) %>%
  tidyr::pivot_wider(
    id_cols = Model,
    names_from = Weight,
    values_from = c(Deaths_Caught, Deaths_Missed, False_Alarms)
  ) %>%
  dplyr::mutate(
    Additional_Deaths_Caught = `Deaths_Caught_w=0.8` - `Deaths_Caught_w=1.0`,
    Fewer_Deaths_Missed = `Deaths_Missed_w=1.0` - `Deaths_Missed_w=0.8`,
    Additional_False_Alarms = `False_Alarms_w=0.8` - `False_Alarms_w=1.0`
  )

cat("\n=== IMPACT OF w=0.8 vs w=1.0 ===\n")
print(Table_Clinical_Change %>%
        dplyr::select(Model, Additional_Deaths_Caught, Fewer_Deaths_Missed,
                      Additional_False_Alarms))

write.csv(Table_Clinical, "results/youden_08/Table_Clinical_Impact.csv",
          row.names = FALSE)
cat("\nSaved: results/youden_08/Table_Clinical_Impact.csv\n")

# ==============================================================================
# SECTION 8: TABLE - STATISTICAL TESTS (McNemar)
# ==============================================================================

cat("\n--- SECTION 8: Creating Table_Statistical_Tests.csv ---\n")

#' Perform McNemar's test comparing predictions at two thresholds
#' @param preds_df Predictions dataframe
#' @param threshold_1 First threshold (w=1.0)
#' @param threshold_2 Second threshold (w=0.8)
#' @return McNemar test results
perform_mcnemar <- function(preds_df, threshold_1, threshold_2) {
  truth <- preds_df$desenlace
  pred_1 <- ifelse(preds_df$.pred_Fallecido >= threshold_1, "Fallecido", "Vivo")
  pred_2 <- ifelse(preds_df$.pred_Fallecido >= threshold_2, "Fallecido", "Vivo")

  # Only perform test if predictions differ
  if (identical(pred_1, pred_2)) {
    return(tibble::tibble(
      b_discordant = 0,
      c_discordant = 0,
      statistic = NA_real_,
      p_value = NA_real_,
      significant = NA,
      note = "Identical predictions - no test needed"
    ))
  }

  # Count discordant pairs
  # b = correct at w=1.0 but wrong at w=0.8
  # c = wrong at w=1.0 but correct at w=0.8
  correct_1 <- (pred_1 == truth)
  correct_2 <- (pred_2 == truth)

  b <- sum(correct_1 & !correct_2)  # Better at w=1.0
  c <- sum(!correct_1 & correct_2)  # Better at w=0.8

  # McNemar test
  if ((b + c) == 0) {
    return(tibble::tibble(
      b_discordant = b,
      c_discordant = c,
      statistic = NA_real_,
      p_value = NA_real_,
      significant = NA,
      note = "No discordant pairs"
    ))
  }

  test_result <- tryCatch({
    cont_table <- matrix(c(
      sum(correct_1 & correct_2),   # a: Both correct
      b,                             # b: Only w=1.0 correct
      c,                             # c: Only w=0.8 correct
      sum(!correct_1 & !correct_2)  # d: Both wrong
    ), nrow = 2, byrow = TRUE)

    stats::mcnemar.test(cont_table, correct = TRUE)
  }, error = function(e) {
    return(list(statistic = NA, p.value = NA))
  })

  tibble::tibble(
    b_discordant = b,
    c_discordant = c,
    statistic = as.numeric(test_result$statistic),
    p_value = test_result$p.value,
    significant = ifelse(!is.na(test_result$p.value),
                          test_result$p.value < 0.05, NA),
    note = ifelse(c > b, "w=0.8 better",
                  ifelse(b > c, "w=1.0 better", "Tied"))
  )
}

# Perform McNemar test for each model
mcnemar_results <- purrr::map_dfr(names(roc_list), function(model_name) {
  thr_10 <- baseline_results$threshold[baseline_results$model == model_name]
  thr_08 <- weighted_results$threshold[weighted_results$model == model_name]

  result <- perform_mcnemar(preds_list[[model_name]], thr_10, thr_08)
  result$Model <- model_name
  result$Threshold_w10 <- thr_10
  result$Threshold_w08 <- thr_08
  return(result)
})

# Create final statistical tests table
Table_Statistical <- mcnemar_results %>%
  dplyr::select(Model,
                `Threshold (w=1.0)` = Threshold_w10,
                `Threshold (w=0.8)` = Threshold_w08,
                `Better at w=1.0 (b)` = b_discordant,
                `Better at w=0.8 (c)` = c_discordant,
                `McNemar Chi-sq` = statistic,
                `p-value` = p_value,
                `Significant (p<0.05)` = significant,
                Interpretation = note)

cat("\n=== McNEMAR TEST RESULTS ===\n")
cat("b = patients correctly classified by w=1.0 but not w=0.8\n")
cat("c = patients correctly classified by w=0.8 but not w=1.0\n\n")
print(Table_Statistical)

write.csv(Table_Statistical, "results/youden_08/Table_Statistical_Tests.csv",
          row.names = FALSE)
cat("\nSaved: results/youden_08/Table_Statistical_Tests.csv\n")

# ==============================================================================
# SECTION 9: FIGURE - YOUDEN CURVES 4-PANEL
# ==============================================================================

cat("\n--- SECTION 9: Creating Figure_Youden_Curves_4panel.png ---\n")

# Color palette
col_w10 <- "#2C3E50"  # Dark blue for w=1.0
col_w08 <- "#E74C3C"  # Red for w=0.8

# Create Youden curve data for all models
youden_curves <- purrr::map_dfr(names(roc_list), function(model_name) {
  roc_obj <- roc_list[[model_name]]
  all_coords <- pROC::coords(roc_obj, "all",
                              ret = c("threshold", "sensitivity", "specificity"),
                              transpose = FALSE)
  all_coords <- all_coords[is.finite(all_coords$threshold), ]

  all_coords %>%
    dplyr::as_tibble() %>%
    dplyr::mutate(
      youden_10 = sensitivity + specificity - 1,
      youden_08 = weighted_youden(sensitivity, specificity, 0.8),
      model = model_name
    )
})

# Create individual panels
create_youden_panel <- function(model_name) {
  model_data <- youden_curves %>% dplyr::filter(model == model_name)
  opt_10 <- baseline_results %>% dplyr::filter(model == model_name)
  opt_08 <- weighted_results %>% dplyr::filter(model == model_name)

  # Check if thresholds differ
  same_threshold <- abs(opt_10$threshold - opt_08$threshold) < 0.0001
  delta_thr <- opt_08$threshold - opt_10$threshold

  subtitle_text <- ifelse(same_threshold,
                          "Same optimal threshold",
                          sprintf("Threshold shift: %+.4f", delta_thr))

  ggplot2::ggplot(model_data, ggplot2::aes(x = threshold)) +
    ggplot2::geom_line(ggplot2::aes(y = youden_10, color = "w=1.0 (Standard)"),
                        linewidth = 1.0) +
    ggplot2::geom_line(ggplot2::aes(y = youden_08, color = "w=0.8 (Weighted)"),
                        linewidth = 1.0, linetype = "dashed") +
    # Optimal points
    ggplot2::geom_vline(xintercept = opt_10$threshold, color = col_w10,
                         linetype = "dotted", linewidth = 0.7, alpha = 0.8) +
    ggplot2::geom_vline(xintercept = opt_08$threshold, color = col_w08,
                         linetype = "dotted", linewidth = 0.7, alpha = 0.8) +
    # Mark optimal points
    ggplot2::geom_point(data = opt_10,
                         ggplot2::aes(x = threshold, y = weighted_J),
                         color = col_w10, size = 3) +
    ggplot2::geom_point(data = opt_08,
                         ggplot2::aes(x = threshold, y = weighted_J),
                         color = col_w08, size = 3) +
    ggplot2::scale_color_manual(
      values = c("w=1.0 (Standard)" = col_w10, "w=0.8 (Weighted)" = col_w08),
      name = "Youden Index"
    ) +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    ggplot2::labs(
      title = model_name,
      subtitle = subtitle_text,
      x = "Threshold",
      y = "Youden J"
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      legend.position = "bottom",
      plot.title = ggplot2::element_text(face = "bold", size = 12),
      plot.subtitle = ggplot2::element_text(size = 10, color = "gray40")
    )
}

# Create 4-panel figure
panels <- purrr::map(names(roc_list), create_youden_panel)
Figure_Youden_4Panel <- patchwork::wrap_plots(panels, ncol = 2) +
  patchwork::plot_annotation(
    title = "Weighted Youden Index Optimization: w=1.0 vs w=0.8",
    subtitle = "Vertical lines indicate optimal thresholds; Points mark maximum J",
    caption = "w=0.8 penalizes specificity by 20%, favoring sensitivity (fewer missed deaths)",
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold"),
      plot.subtitle = ggplot2::element_text(size = 11),
      plot.caption = ggplot2::element_text(size = 9, color = "gray50")
    )
  ) +
  patchwork::plot_layout(guides = "collect") &
  ggplot2::theme(legend.position = "bottom")

ggplot2::ggsave("results/youden_08/Figure_Youden_Curves_4panel.png",
                Figure_Youden_4Panel,
                width = 12, height = 10, dpi = 300)
cat("Saved: results/youden_08/Figure_Youden_Curves_4panel.png\n")

# ==============================================================================
# SECTION 10: FIGURE - SENSITIVITY-SPECIFICITY TRADEOFF
# ==============================================================================

cat("\n--- SECTION 10: Creating Figure_SensSpec_Tradeoff.png ---\n")

# Prepare data for plotting
tradeoff_data <- full_metrics %>%
  dplyr::select(Model, Weight, Sensitivity, Specificity) %>%
  tidyr::pivot_longer(cols = c(Sensitivity, Specificity),
                      names_to = "Metric", values_to = "Value") %>%
  dplyr::mutate(
    Model = factor(Model, levels = names(roc_list)),
    Weight = factor(Weight, levels = c("w=1.0", "w=0.8")),
    Metric = factor(Metric, levels = c("Sensitivity", "Specificity"))
  )

# Create dodge position
dodge_width <- 0.7

# Create grouped bar chart
Figure_Tradeoff <- ggplot2::ggplot(tradeoff_data,
                                    ggplot2::aes(x = Model, y = Value,
                                                 fill = interaction(Metric, Weight))) +
  ggplot2::geom_bar(stat = "identity",
                    position = ggplot2::position_dodge(width = dodge_width),
                    width = 0.65, color = "white", linewidth = 0.3) +
  ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", Value)),
                      position = ggplot2::position_dodge(width = dodge_width),
                      vjust = -0.5, size = 2.8) +
  ggplot2::scale_fill_manual(
    values = c(
      "Sensitivity.w=1.0" = "#3498DB",
      "Sensitivity.w=0.8" = "#E74C3C",
      "Specificity.w=1.0" = "#85C1E9",
      "Specificity.w=0.8" = "#F5B7B1"
    ),
    labels = c("Sens (w=1.0)", "Sens (w=0.8)", "Spec (w=1.0)", "Spec (w=0.8)"),
    name = "Metric"
  ) +
  ggplot2::scale_y_continuous(limits = c(0, 1.15),
                               breaks = seq(0, 1, 0.2),
                               labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Sensitivity-Specificity Tradeoff: Standard vs Weighted Youden",
    subtitle = "Impact of w=0.8 weighting on classification performance",
    x = NULL,
    y = "Metric Value",
    caption = "Note: Higher sensitivity (fewer missed deaths) may come at cost of lower specificity (more false alarms)"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 0, hjust = 0.5, size = 10),
    legend.position = "bottom",
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.caption = ggplot2::element_text(size = 9, color = "gray50")
  ) +
  ggplot2::guides(fill = ggplot2::guide_legend(nrow = 1))

ggplot2::ggsave("results/youden_08/Figure_SensSpec_Tradeoff.png",
                Figure_Tradeoff,
                width = 12, height = 8, dpi = 300)
cat("Saved: results/youden_08/Figure_SensSpec_Tradeoff.png\n")

# ==============================================================================
# SECTION 11: SUMMARY AND KEY FINDINGS
# ==============================================================================

cat("\n")
cat("===============================================================================\n")
cat("         WEIGHTED YOUDEN EXPERIMENT COMPLETE                                   \n")
cat("===============================================================================\n")

# Key findings summary
cat("\n=== KEY FINDINGS ===\n")

# Check which models show threshold change
threshold_changes <- Table_Youden %>%
  dplyr::filter(Threshold_Changed) %>%
  dplyr::pull(Model)

if (length(threshold_changes) == 0) {
  cat("\n1. NO MODELS show threshold changes between w=1.0 and w=0.8\n")
  cat("   This indicates the ROC curve shapes produce identical optima\n")
  cat("   for both weighting schemes in this dataset.\n")
} else {
  cat("\n1. Models with threshold changes:\n")
  for (m in threshold_changes) {
    delta <- Table_Youden$Delta_Threshold[Table_Youden$Model == m]
    delta_sens <- Table_Youden$Delta_Sens[Table_Youden$Model == m]
    delta_spec <- Table_Youden$Delta_Spec[Table_Youden$Model == m]
    cat(sprintf("   - %s: Threshold %+.4f, Sens %+.3f, Spec %+.3f\n",
                m, delta, delta_sens, delta_spec))
  }
}

# Models without change
no_change <- setdiff(names(roc_list), threshold_changes)
if (length(no_change) > 0) {
  cat("\n2. Models with IDENTICAL thresholds (w=1.0 = w=0.8):\n")
  for (m in no_change) {
    cat(sprintf("   - %s (threshold = %.4f)\n", m,
                Table_Youden$`Threshold_w=1.0`[Table_Youden$Model == m]))
  }
  cat("\n   Interpretation: These models have robust local optima on their ROC curves\n")
  cat("   that do not shift with moderate changes in sensitivity-specificity weighting.\n")
}

# Clinical impact summary
cat("\n3. Clinical Impact Summary:\n")
for (m in names(roc_list)) {
  change_row <- Table_Clinical_Change %>% dplyr::filter(Model == m)
  if (change_row$Additional_Deaths_Caught[1] != 0) {
    cat(sprintf("   - %s: %+d deaths caught, %+d false alarms\n",
                m, change_row$Additional_Deaths_Caught[1],
                change_row$Additional_False_Alarms[1]))
  } else {
    cat(sprintf("   - %s: No change (identical thresholds)\n", m))
  }
}

cat("\n4. Interpretation:\n")
cat("   - w=0.8 penalizes specificity by 20%, favoring sensitivity\n")
cat("   - When thresholds are identical, the local ROC curve maximum\n")
cat("     is robust to moderate changes in sensitivity-specificity weighting\n")
cat("   - This is scientifically valuable: it shows which models' optima\n")
cat("     are sensitive to cost assumptions vs which are robust\n")

cat("\n=== OUTPUT FILES ===\n")
cat("Tables:\n")
cat("  - results/youden_08/Table_Youden_Comparison.csv\n")
cat("  - results/youden_08/Table_Clinical_Impact.csv\n")
cat("  - results/youden_08/Table_Statistical_Tests.csv\n")
cat("Figures:\n")
cat("  - results/youden_08/Figure_Youden_Curves_4panel.png\n")
cat("  - results/youden_08/Figure_SensSpec_Tradeoff.png\n")

# Decision framework evaluation
cat("\n=== DECISION FRAMEWORK EVALUATION ===\n")
cat("Criteria for adopting w=0.8:\n")

for (m in threshold_changes) {
  cat(sprintf("\n%s:\n", m))
  row <- Table_Youden %>% dplyr::filter(Model == m)

  # Check criteria
  sens_improve <- row$Delta_Sens >= 0.05
  spec_decrease <- row$Delta_Spec >= -0.10
  npv_maintained <- row$`NPV_w=0.8` >= 0.95

  cat(sprintf("  [ ] Sensitivity improvement >= 5pp: %+.1f%% (%s)\n",
              row$Delta_Sens * 100, ifelse(sens_improve, "PASS", "FAIL")))
  cat(sprintf("  [ ] Specificity decrease <= 10pp: %+.1f%% (%s)\n",
              row$Delta_Spec * 100, ifelse(spec_decrease, "PASS", "FAIL")))
  cat(sprintf("  [ ] NPV maintained >= 0.95: %.3f (%s)\n",
              row$`NPV_w=0.8`, ifelse(npv_maintained, "PASS", "FAIL")))
}

if (length(threshold_changes) == 0) {
  cat("\nNo threshold changes detected - w=0.8 produces identical results to w=1.0\n")
  cat("for all models in this dataset.\n")
}

cat("\n===============================================================================\n")
cat("EXPERIMENT COMPLETE\n")
cat("===============================================================================\n")
