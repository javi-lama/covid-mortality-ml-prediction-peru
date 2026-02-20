# ==============================================================================
# MULTI-MODEL FIGURES: PUBLICATION-QUALITY VISUALIZATIONS
# ==============================================================================
# Purpose: Generate Figures 2-4 and Supplementary Figure S1 for publication
# Author: COVID-19 Mortality Prediction Project
# Date: 2026-02-08
# Specifications: 1920x1080, 300 DPI, theme_minimal, 14pt base font
#
# IMPORTANT: Explicit namespacing (package::function) used throughout to prevent
# function name collisions between packages
# ==============================================================================

# ==============================================================================
# SECTION 0: LIBRARY LOADING WITH CONFLICT MANAGEMENT
# ==============================================================================

suppressPackageStartupMessages({
  library(tidymodels)
  library(tidyverse)
  library(pROC)
  library(dcurves)
  library(probably)
  library(patchwork)
})

set.seed(2026)

cat("═══════════════════════════════════════════════════════════════\n")
cat("MULTI-MODEL FIGURES SCRIPT INITIALIZED\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ==============================================================================
# SECTION 1: GLOBAL AESTHETIC CONFIGURATION
# ==============================================================================

# Color palette (colorblind-friendly)
col_rf <- "#004E89"      # Blue - Random Forest
col_xgb <- "#E63946"     # Red - XGBoost
col_svm <- "#2A9D8F"     # Teal - SVM
col_logreg <- "#7F8C8D"  # Gray - Logistic Regression (benchmark)

model_colors <- c(
  "Random Forest" = col_rf,
  "XGBoost" = col_xgb,
  "SVM-RBF" = col_svm,
  "Logistic Regression" = col_logreg
)

# Publication theme
theme_publication <- function(base_size = 14) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 18,
                                          color = "#2C3E50"),
      plot.subtitle = ggplot2::element_text(size = 14, color = "#7F8C8D",
                                             margin = ggplot2::margin(b = 15)),
      axis.title = ggplot2::element_text(face = "bold", size = 15,
                                          color = "#34495E"),
      axis.text = ggplot2::element_text(size = 14, color = "black"),
      legend.position = "bottom",
      legend.text = ggplot2::element_text(size = 12),
      legend.title = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(color = "grey92"),
      plot.margin = ggplot2::margin(20, 20, 20, 20)
    )
}

# ==============================================================================
# SECTION 2: LOAD PRE-COMPUTED OBJECTS FROM COMPARISON SCRIPT
# ==============================================================================

cat("--- SECTION 2: Loading Pre-computed Objects ---\n")

# Load objects saved by Multi_Model_Comparison.R
roc_list <- readRDS("roc_list_multimodel.rds")
preds_list <- readRDS("preds_list_multimodel.rds")
auc_results <- readRDS("auc_results_multimodel.rds")

# Load test data for DCA
df_testing <- readRDS("data_testing.rds")

cat("Loaded roc_list:", names(roc_list), "\n")
cat("Loaded preds_list:", names(preds_list), "\n")

# ==============================================================================
# SECTION 3: FIGURE 2 - MULTI-MODEL ROC CURVE OVERLAY
# ==============================================================================

cat("\n--- SECTION 3: Creating Figure 2 (Multi-Model ROC) ---\n")

# Create legend labels with AUC and CI
legend_labels <- auc_results %>%
  dplyr::mutate(
    label = paste0(Model, ": AUC = ", round(AUC, 3),
                   " (", round(AUC_lower, 3), "-", round(AUC_upper, 3), ")")
  ) %>%
  dplyr::pull(label)

names(legend_labels) <- auc_results$Model

# Convert ROC objects to data frames for ggplot
roc_df <- purrr::map2_dfr(
  roc_list, names(roc_list),
  function(roc_obj, model_name) {
    tibble::tibble(
      sensitivity = roc_obj$sensitivities,
      specificity = roc_obj$specificities,
      model = legend_labels[model_name]
    )
  }
)

# Set factor levels for consistent ordering (by AUC descending)
roc_df$model <- factor(roc_df$model, levels = legend_labels[order(-auc_results$AUC)])

# Create ROC plot
Figure_2 <- ggplot2::ggplot(roc_df,
                             ggplot2::aes(x = 1 - specificity, y = sensitivity,
                                          color = model)) +
  # Reference line
  ggplot2::geom_abline(lty = 3, color = "grey50", linewidth = 0.8) +
  # ROC curves
  ggplot2::geom_path(linewidth = 1.3, alpha = 0.9) +
  # Colors - create named vector for legend labels
  ggplot2::scale_color_manual(
    values = stats::setNames(
      c(col_logreg, col_rf, col_svm, col_xgb),
      c(legend_labels["Logistic Regression"],
        legend_labels["Random Forest"],
        legend_labels["SVM-RBF"],
        legend_labels["XGBoost"])
    )
  ) +
  # Axis labels
  ggplot2::labs(
    title = "Figure 2. Multi-Model ROC Curve Comparison",
    subtitle = "Discriminative performance on held-out test set (n = 263)",
    x = "1 - Specificity (False Positive Rate)",
    y = "Sensitivity (True Positive Rate)"
  ) +
  # Coordinates
  ggplot2::coord_equal() +
  # Theme
  theme_publication() +
  ggplot2::theme(
    legend.position = c(0.70, 0.25),
    legend.background = ggplot2::element_rect(fill = "white", color = "grey90"),
    legend.text = ggplot2::element_text(size = 11),
    legend.key.height = ggplot2::unit(0.8, "cm")
  )

# Save
ggplot2::ggsave("Figure_2_MultiModel_ROC.png", Figure_2,
                width = 1920/300, height = 1080/300, dpi = 300,
                units = "in", scale = 3)

cat("Saved: Figure_2_MultiModel_ROC.png\n")

# ==============================================================================
# SECTION 4: FIGURE 3 - DECISION CURVE ANALYSIS
# ==============================================================================

cat("\n--- SECTION 4: Creating Figure 3 (DCA) ---\n")

# Prepare data for dcurves package
df_dca <- df_testing %>%
  dplyr::mutate(
    desenlace_num = ifelse(desenlace == "Fallecido", 1, 0),
    pred_rf = preds_list[["Random Forest"]]$.pred_Fallecido,
    pred_xgb = preds_list[["XGBoost"]]$.pred_Fallecido,
    pred_svm = preds_list[["SVM-RBF"]]$.pred_Fallecido,
    pred_logreg = preds_list[["Logistic Regression"]]$.pred_Fallecido
  )

# Compute DCA for all models
dca_result <- dcurves::dca(
  desenlace_num ~ pred_rf + pred_xgb + pred_svm + pred_logreg,
  data = df_dca,
  thresholds = seq(0, 0.50, by = 0.01),
  label = list(
    pred_rf = "Random Forest",
    pred_xgb = "XGBoost",
    pred_svm = "SVM-RBF",
    pred_logreg = "Logistic Regression"
  )
)

# Extract DCA data
dca_data <- dca_result$dca

# Custom DCA plot
Figure_3 <- ggplot2::ggplot(dca_data,
                             ggplot2::aes(x = threshold, y = net_benefit,
                                          color = label, linetype = label)) +
  # Lines
  ggplot2::geom_line(linewidth = 1.2) +
  # Colors and linetypes
  ggplot2::scale_color_manual(values = c(
    "Random Forest" = col_rf,
    "XGBoost" = col_xgb,
    "SVM-RBF" = col_svm,
    "Logistic Regression" = col_logreg,
    "Treat All" = "#C0392B",
    "Treat None" = "grey50"
  )) +
  ggplot2::scale_linetype_manual(values = c(
    "Random Forest" = "solid",
    "XGBoost" = "solid",
    "SVM-RBF" = "solid",
    "Logistic Regression" = "solid",
    "Treat All" = "dashed",
    "Treat None" = "dotted"
  )) +
  # X-axis as percentage
  ggplot2::scale_x_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, 0.50)
  ) +
  # Y-axis limits
  ggplot2::coord_cartesian(ylim = c(-0.05, 0.20)) +
  # Labels
  ggplot2::labs(
    title = "Figure 3. Decision Curve Analysis: Multi-Model Comparison",
    subtitle = "Net clinical benefit across threshold probabilities (0-50%)",
    x = "Threshold Probability",
    y = "Net Benefit"
  ) +
  # Theme
  theme_publication() +
  ggplot2::theme(
    legend.position = c(0.75, 0.80),
    legend.background = ggplot2::element_rect(fill = "white", color = "grey90")
  )

# Save
ggplot2::ggsave("Figure_3_MultiModel_DCA.png", Figure_3,
                width = 1920/300, height = 1080/300, dpi = 300,
                units = "in", scale = 3)

cat("Saved: Figure_3_MultiModel_DCA.png\n")

# ==============================================================================
# SECTION 5: FIGURE 4 - CALIBRATION PLOTS (PANELED)
# ==============================================================================

cat("\n--- SECTION 5: Creating Figure 4 (Calibration Panel) ---\n")

# Function to compute calibration data
compute_calibration_data <- function(preds_df, model_name, n_bins = 10) {
  preds_df %>%
    dplyr::mutate(
      prob_bin = cut(.pred_Fallecido,
                     breaks = seq(0, 1, length.out = n_bins + 1),
                     include.lowest = TRUE),
      observed = ifelse(desenlace == "Fallecido", 1, 0)
    ) %>%
    dplyr::group_by(prob_bin) %>%
    dplyr::summarise(
      predicted = mean(.pred_Fallecido),
      observed = mean(observed),
      n = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::mutate(model = model_name)
}

# Compute for each ML model (excluding LogReg for main figure)
cal_rf <- compute_calibration_data(preds_list[["Random Forest"]], "Random Forest")
cal_xgb <- compute_calibration_data(preds_list[["XGBoost"]], "XGBoost")
cal_svm <- compute_calibration_data(preds_list[["SVM-RBF"]], "SVM-RBF")

# Combine
cal_data <- dplyr::bind_rows(cal_rf, cal_xgb, cal_svm)

# Set factor levels for faceting order
cal_data$model <- factor(cal_data$model,
                          levels = c("Random Forest", "XGBoost", "SVM-RBF"))

# Compute Brier scores for annotation
brier_rf <- mean((preds_list[["Random Forest"]]$.pred_Fallecido -
                   ifelse(preds_list[["Random Forest"]]$desenlace == "Fallecido", 1, 0))^2)
brier_xgb <- mean((preds_list[["XGBoost"]]$.pred_Fallecido -
                    ifelse(preds_list[["XGBoost"]]$desenlace == "Fallecido", 1, 0))^2)
brier_svm <- mean((preds_list[["SVM-RBF"]]$.pred_Fallecido -
                    ifelse(preds_list[["SVM-RBF"]]$desenlace == "Fallecido", 1, 0))^2)

brier_labels <- tibble::tibble(
  model = factor(c("Random Forest", "XGBoost", "SVM-RBF"),
                  levels = c("Random Forest", "XGBoost", "SVM-RBF")),
  label = c(
    paste0("Brier = ", round(brier_rf, 3)),
    paste0("Brier = ", round(brier_xgb, 3)),
    paste0("Brier = ", round(brier_svm, 3))
  ),
  x = 0.75,
  y = 0.15
)

# Create calibration panel
Figure_4 <- ggplot2::ggplot(cal_data, ggplot2::aes(x = predicted, y = observed)) +
  # Perfect calibration line
  ggplot2::geom_abline(intercept = 0, slope = 1, linetype = "dashed",
                        color = "grey50", linewidth = 1) +
  # Calibration points
  ggplot2::geom_point(ggplot2::aes(size = n), alpha = 0.7, color = col_rf) +
  # Smoothed calibration curve
  ggplot2::geom_smooth(method = "loess", se = TRUE, color = col_rf,
                        fill = col_rf, alpha = 0.2, span = 1) +
  # Facet by model
  ggplot2::facet_wrap(~model, ncol = 3) +
  # Brier score annotations
  ggplot2::geom_text(data = brier_labels,
                      ggplot2::aes(x = x, y = y, label = label),
                      size = 5, fontface = "bold", color = "#2C3E50") +
  # Axis limits
  ggplot2::scale_x_continuous(limits = c(0, 1),
                               labels = scales::percent_format()) +
  ggplot2::scale_y_continuous(limits = c(0, 1),
                               labels = scales::percent_format()) +
  # Size legend
  ggplot2::scale_size_continuous(range = c(3, 10), name = "n per bin") +
  # Labels
  ggplot2::labs(
    title = "Figure 4. Calibration Assessment: ML Model Comparison",
    subtitle = "Observed mortality rate vs. predicted probability (10 bins)",
    x = "Mean Predicted Probability",
    y = "Observed Event Rate"
  ) +
  # Theme
  theme_publication() +
  ggplot2::theme(
    strip.text = ggplot2::element_text(face = "bold", size = 14),
    strip.background = ggplot2::element_rect(fill = "grey95", color = NA)
  )

# Save
ggplot2::ggsave("Figure_4_Calibration_Panel.png", Figure_4,
                width = 1920/300, height = 1080/300, dpi = 300,
                units = "in", scale = 3)

cat("Saved: Figure_4_Calibration_Panel.png\n")

# ==============================================================================
# SECTION 6: FIGURE S1 - AUC FOREST PLOT
# ==============================================================================

cat("\n--- SECTION 6: Creating Figure S1 (AUC Forest Plot) ---\n")

# Prepare data
forest_data <- auc_results %>%
  dplyr::mutate(Model = forcats::fct_reorder(Model, AUC))

# Create forest plot
Figure_S1 <- ggplot2::ggplot(forest_data, ggplot2::aes(x = AUC, y = Model)) +
  # Vertical reference lines
  ggplot2::geom_vline(xintercept = 0.5, linetype = "dotted",
                       color = "grey70", linewidth = 0.8) +
  ggplot2::geom_vline(xintercept = 0.8, linetype = "dashed",
                       color = "#27AE60", alpha = 0.5, linewidth = 0.8) +
  # CI error bars
  ggplot2::geom_errorbarh(ggplot2::aes(xmin = AUC_lower, xmax = AUC_upper),
                           height = 0.2, linewidth = 1, color = "grey30") +
  # Point estimates
  ggplot2::geom_point(ggplot2::aes(color = Model), size = 5) +
  # Colors
  ggplot2::scale_color_manual(values = model_colors) +
  # Axis limits
  ggplot2::scale_x_continuous(limits = c(0.65, 1.0),
                               breaks = seq(0.65, 1, 0.05)) +
  # Labels
  ggplot2::labs(
    title = "Supplementary Figure S1. Forest Plot of ROC-AUC",
    subtitle = "95% bootstrap confidence intervals (B = 2000)",
    x = "ROC-AUC",
    y = ""
  ) +
  # Add AUC text labels
  ggplot2::geom_text(ggplot2::aes(label = paste0(round(AUC, 3), " [",
                                                   round(AUC_lower, 3), "-",
                                                   round(AUC_upper, 3), "]")),
                      hjust = -0.1, size = 4, fontface = "bold") +
  # Expand x-axis for labels
  ggplot2::coord_cartesian(xlim = c(0.65, 1.05)) +
  # Theme
  theme_publication() +
  ggplot2::theme(
    legend.position = "none",
    axis.text.y = ggplot2::element_text(face = "bold", size = 14)
  )

# Save
ggplot2::ggsave("Figure_S1_AUC_Forest.png", Figure_S1,
                width = 1920/300, height = 800/300, dpi = 300,
                units = "in", scale = 3)

cat("Saved: Figure_S1_AUC_Forest.png\n")

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("            MULTI-MODEL FIGURES COMPLETE                       \n")
cat("═══════════════════════════════════════════════════════════════\n")
cat("\nOutputs generated:\n")
cat("  1. Figure_2_MultiModel_ROC.png (1920x1080, 300 DPI)\n")
cat("  2. Figure_3_MultiModel_DCA.png (1920x1080, 300 DPI)\n")
cat("  3. Figure_4_Calibration_Panel.png (1920x1080, 300 DPI)\n")
cat("  4. Figure_S1_AUC_Forest.png (1920x800, 300 DPI)\n")
cat("═══════════════════════════════════════════════════════════════\n")
