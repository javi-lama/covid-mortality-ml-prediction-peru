# ==== SMOTE RATIO OPTIMIZATION ANALYSIS ====
# Purpose: Compare different SMOTE over_ratio values to find optimal balance
# Current: over_ratio = 1.0 (perfect 50/50 balance)
# Test: 0.5, 0.6, 0.7, 0.8, 1.0 to find best performance
# Author: Scientific Rigor Enhancement - Phase 5
# Date: 2026-02-04

library(tidymodels)
library(tidyverse)
library(themis)
library(doParallel)

# Load data
source("Data_Cleaning_Organization.R")
source("Random_Forest_Preprocess.R")

print("════════════════════════════════════════════════════════════")
print("SMOTE OVER-RATIO OPTIMIZATION ANALYSIS")
print("════════════════════════════════════════════════════════════")
print("")
print("Testing over_ratio values: 0.5, 0.6, 0.7, 0.8, 1.0")
print("Current baseline: 1.0 (perfect 50/50 balance)")
print("")

# Define SMOTE ratios to test
smote_ratios <- c(0.5, 0.6, 0.7, 0.8, 1.0)

# Parallel setup
all_cores <- detectCores(logical = FALSE)
cl <- makePSOCKcluster(all_cores - 1)
registerDoParallel(cl)

print(paste("Running analysis on", all_cores - 1, "cores..."))
print("")

# Test each SMOTE ratio
smote_comparison <- map_df(smote_ratios, function(ratio) {

  print(paste("Testing SMOTE over_ratio =", ratio, "..."))

  # Create recipe with specific SMOTE ratio
  recipe_smote <- recipe(desenlace ~ ., data = df_training) %>%
    step_impute_knn(all_numeric_predictors(), neighbors = 5) %>%
    step_impute_mode(all_nominal_predictors(), -all_outcomes()) %>%
    step_mutate(
      ratio_hepatico = bilirrtotal / (albumina + 0.1),
      log_plaquetas = log(plaquetas + 1)
    ) %>%
    step_corr(all_numeric_predictors(), threshold = 0.60) %>%
    step_nzv(all_predictors()) %>%
    step_YeoJohnson(all_numeric_predictors()) %>%
    step_normalize(all_numeric_predictors()) %>%
    step_dummy(all_nominal_predictors(), -all_outcomes()) %>%
    step_smote(desenlace, over_ratio = ratio, neighbors = 5)

  # Create RF workflow
  rf_workflow_test <- workflow() %>%
    add_recipe(recipe_smote) %>%
    add_model(rand_forest(trees = 500, mtry = 10, min_n = 20) %>%
                set_engine("ranger") %>%
                set_mode("classification"))

  # 5-fold CV
  set.seed(2026)
  cv_results <- fit_resamples(
    rf_workflow_test,
    resamples = vfold_cv(df_training, v = 5, strata = desenlace),
    metrics = metric_set(roc_auc, sensitivity, specificity, accuracy, kap),
    control = control_resamples(save_pred = FALSE)
  )

  # Extract metrics
  metrics_summary <- collect_metrics(cv_results) %>%
    mutate(SMOTE_Ratio = ratio)

  # Calculate class balance after SMOTE
  recipe_prep <- prep(recipe_smote, training = df_training)
  data_baked <- bake(recipe_prep, new_data = NULL)
  class_counts <- table(data_baked$desenlace)

  # Add balance info
  metrics_summary %>%
    mutate(
      Fallecido_N = class_counts["Fallecido"],
      Vivo_N = class_counts["Vivo"],
      Balance_Ratio = Fallecido_N / Vivo_N
    )
})

# Stop parallel processing
stopCluster(cl)
registerDoSEQ()

print("")
print("════════════════════════════════════════════════════════════")
print("SMOTE RATIO COMPARISON RESULTS")
print("════════════════════════════════════════════════════════════")
print("")

# Display results
smote_summary <- smote_comparison %>%
  select(SMOTE_Ratio, .metric, mean, std_err, Balance_Ratio) %>%
  arrange(.metric, desc(mean))

print("Performance by SMOTE Ratio:")
print(smote_summary)

# Identify best ratio per metric
best_by_metric <- smote_comparison %>%
  group_by(.metric) %>%
  slice_max(mean, n = 1) %>%
  select(.metric, SMOTE_Ratio, mean) %>%
  rename(Best_Ratio = SMOTE_Ratio, Best_Mean = mean)

print("")
print("Best SMOTE Ratio per Metric:")
print(best_by_metric)

# ==== VISUALIZATIONS ====

# 1. Performance across ratios
plot_performance <- smote_comparison %>%
  ggplot(aes(x = SMOTE_Ratio, y = mean, color = .metric)) +
  geom_line(size = 1) +
  geom_point(size = 3) +
  geom_errorbar(aes(ymin = mean - std_err, ymax = mean + std_err),
                width = 0.05, alpha = 0.5) +
  facet_wrap(~.metric, scales = "free_y", ncol = 2) +
  labs(
    title = "Impact of SMOTE Over-Ratio on Model Performance",
    subtitle = "5-Fold CV with Random Forest (trees=500, mtry=10, min_n=20)",
    x = "SMOTE Over-Ratio",
    y = "CV Performance (Mean ± SE)",
    caption = "Higher over_ratio = more aggressive minority class oversampling"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

print(plot_performance)
ggsave("Figure_SMOTE_Ratio_Comparison.png", plot_performance,
       width = 12, height = 8, dpi = 300)

# 2. ROC-AUC focused comparison
plot_auc <- smote_comparison %>%
  filter(.metric == "roc_auc") %>%
  ggplot(aes(x = SMOTE_Ratio, y = mean)) +
  geom_line(size = 1.2, color = "darkblue") +
  geom_point(size = 4, color = "darkblue") +
  geom_errorbar(aes(ymin = mean - std_err, ymax = mean + std_err),
                width = 0.05, color = "darkblue", alpha = 0.7) +
  geom_vline(xintercept = 1.0, linetype = "dashed", color = "red") +
  annotate("text", x = 1.0, y = max(smote_comparison$mean[smote_comparison$.metric == "roc_auc"]),
           label = "Current\n(1.0)", vjust = -0.5, color = "red") +
  labs(
    title = "SMOTE Over-Ratio Impact on ROC-AUC",
    subtitle = "Finding optimal balance between sensitivity and specificity",
    x = "SMOTE Over-Ratio (Minority:Majority)",
    y = "ROC-AUC (Mean ± SE)"
  ) +
  theme_minimal()

print(plot_auc)
ggsave("Figure_SMOTE_AUC_Focus.png", plot_auc, width = 10, height = 6, dpi = 300)

# 3. Sensitivity vs Specificity trade-off
plot_tradeoff <- smote_comparison %>%
  filter(.metric %in% c("sensitivity", "specificity")) %>%
  ggplot(aes(x = SMOTE_Ratio, y = mean, color = .metric)) +
  geom_line(size = 1.2) +
  geom_point(size = 4) +
  scale_color_manual(values = c("sensitivity" = "darkgreen", "specificity" = "darkorange"),
                     name = "Metric") +
  labs(
    title = "SMOTE Impact on Sensitivity-Specificity Trade-off",
    subtitle = "Higher ratio increases sensitivity (catches deaths) but may reduce specificity",
    x = "SMOTE Over-Ratio",
    y = "Performance (Mean)"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

print(plot_tradeoff)
ggsave("Figure_SMOTE_Tradeoff.png", plot_tradeoff, width = 10, height = 6, dpi = 300)

print("")
print("════════════════════════════════════════════════════════════")
print("RECOMMENDATION")
print("════════════════════════════════════════════════════════════")

# Determine optimal ratio based on ROC-AUC
optimal_ratio <- smote_comparison %>%
  filter(.metric == "roc_auc") %>%
  slice_max(mean, n = 1) %>%
  pull(SMOTE_Ratio)

optimal_auc <- smote_comparison %>%
  filter(.metric == "roc_auc" & SMOTE_Ratio == optimal_ratio) %>%
  pull(mean)

baseline_auc <- smote_comparison %>%
  filter(.metric == "roc_auc" & SMOTE_Ratio == 1.0) %>%
  pull(mean)

improvement <- (optimal_auc - baseline_auc) * 100

print(paste0("Optimal SMOTE over_ratio: ", optimal_ratio))
print(paste0("ROC-AUC at optimal ratio: ", round(optimal_auc, 4)))
print(paste0("ROC-AUC at baseline (1.0): ", round(baseline_auc, 4)))

if(optimal_ratio != 1.0) {
  print(paste0("Improvement: +", round(improvement, 3), " percentage points"))
  print("")
  print("RECOMMENDATION:")
  print(paste0("  Update Random_Forest_Preprocess.R line 107 to:"))
  print(paste0("  step_smote(desenlace, over_ratio = ", optimal_ratio, ", neighbors = 5)"))
  print("")
  print("JUSTIFICATION:")
  if(optimal_ratio < 1.0) {
    minority_count <- round(882 * optimal_ratio)
    print(paste0("  - Over_ratio = ", optimal_ratio, " creates ~", minority_count, ":882 balance"))
    print("  - Less aggressive than 1.0, reduces risk of noise amplification")
    print("  - Maintains improved minority class representation")
    print("  - Optimizes ROC-AUC without overfitting to minority class")
  }
} else {
  print("")
  print("RECOMMENDATION:")
  print("  Current over_ratio = 1.0 is OPTIMAL")
  print("  No change needed to Random_Forest_Preprocess.R")
  print("")
  print("JUSTIFICATION:")
  print("  - Ratio = 1.0 provides best ROC-AUC performance")
  print("  - Perfect balance maximizes model's ability to learn minority class")
  print("  - Trade-off between sensitivity and specificity is optimal at this ratio")
}

print("")
print("════════════════════════════════════════════════════════════")

# Save results
write.csv(smote_comparison, "smote_ratio_comparison_results.csv", row.names = FALSE)
saveRDS(smote_comparison, "smote_ratio_comparison_results.rds")

print("")
print("Results saved to:")
print("  - smote_ratio_comparison_results.csv")
print("  - smote_ratio_comparison_results.rds")
print("  - Figure_SMOTE_Ratio_Comparison.png")
print("  - Figure_SMOTE_AUC_Focus.png")
print("  - Figure_SMOTE_Tradeoff.png")
print("")
print("Analysis complete!")
