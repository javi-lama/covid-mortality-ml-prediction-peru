# ==============================================================================
# PARSIMONIOUS CLINICAL LOGISTIC REGRESSION
# ==============================================================================
#
# PURPOSE: OR estimation using ONLY the 8 SHAP-consensus features
#   - Provides a clean, interpretable OR table for the paper
#   - Validates that SHAP-selected features are independently significant
#   - Creates a "minimal viable model" for potential clinical deployment
#
# WHY STANDARD glm() WORKS HERE:
#   - 8 conceptual features = 9 actual predictors (severity has 2 dummies)
#   - EPV = 168 events / 9 predictors = 18.7 (well above >=10 threshold)
#   - Fewer predictors dramatically reduces separation risk
#   - No exotic penalization needed — pure standard logistic regression
#
# ROLE IN THE PAPER:
#   - Original LogReg (37 vars, AUC 0.877) → PRIMARY AUC benchmark (Table 3)
#   - Firth LogReg (36 vars, AUC 0.859) → Stable OR with separation handling
#   - Parsimonious LogReg (9 vars) → Clean OR table, clinical interpretation
#   - All three serve DIFFERENT purposes and belong in the paper
#
# AUTHOR: Gold-Standard Implementation
# DATE: 2026-02-17
# SEED: 2026
#
# ==============================================================================

# ==============================================================================
# SECTION 0: LIBRARY LOADING AND CONFIGURATION
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidymodels)
  library(pROC)
  library(gtsummary)
  library(ResourceSelection)
  library(car)
  library(PRROC)
})

set.seed(2026)
options(scipen = 999)
tidymodels::tidymodels_prefer()

cat("===============================================================================\n")
cat("PARSIMONIOUS CLINICAL LOGISTIC REGRESSION\n")
cat("===============================================================================\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Seed: 2026\n")
cat("Purpose: OR estimation using 8 SHAP-consensus features\n\n")

# Ensure results directory exists
if (!dir.exists("results")) {
  dir.create("results")
  cat("Created: results/ directory\n")
}

# ==============================================================================
# SECTION 1: LOAD DATA AND PREPROCESSING
# ==============================================================================

cat("--- SECTION 1: Loading Data and Preprocessing ---\n")

# Load raw training and testing data
df_training <- readRDS("data_training.rds")
df_testing <- readRDS("data_testing.rds")

cat("Raw training dimensions:", nrow(df_training), "x", ncol(df_training), "\n")
cat("Raw testing dimensions:", nrow(df_testing), "x", ncol(df_testing), "\n")

# Create NO-SMOTE recipe (same preprocessing as ML models, but without SMOTE)
logreg_recipe <- recipes::recipe(desenlace ~ ., data = df_training) %>%
  # A. Imputation for NA
  recipes::step_impute_knn(recipes::all_numeric_predictors(), neighbors = 5) %>%
  recipes::step_impute_mode(recipes::all_nominal_predictors(), -recipes::all_outcomes()) %>%
  # B. Laboratory ratios (SAME as ML models)
  recipes::step_mutate(
    ratio_hepatico = bilirrtotal / (albumina + 0.1),
    log_plaquetas = log(plaquetas + 1)
  ) %>%
  # C. Collinearity cleaning (threshold = 0.60, SAME as ML models)
  recipes::step_corr(recipes::all_numeric_predictors(), threshold = 0.60) %>%
  recipes::step_nzv(recipes::all_predictors()) %>%
  # D. Transformations
  recipes::step_YeoJohnson(recipes::all_numeric_predictors()) %>%
  recipes::step_normalize(recipes::all_numeric_predictors()) %>%
  # E. Encoding
  recipes::step_dummy(recipes::all_nominal_predictors(), -recipes::all_outcomes())
  # NO SMOTE — intentional for parsimonious model

# Prep and bake
logreg_prep <- recipes::prep(logreg_recipe, training = df_training)
train_baked <- recipes::bake(logreg_prep, new_data = NULL)
test_baked <- recipes::bake(logreg_prep, new_data = df_testing)

cat("Baked training dimensions:", nrow(train_baked), "x", ncol(train_baked), "\n")
cat("Baked testing dimensions:", nrow(test_baked), "x", ncol(test_baked), "\n")

# Verify outcome variable
cat("Outcome variable: desenlace\n")
cat("Outcome levels:", levels(train_baked$desenlace), "\n")
cat("Training outcome distribution:\n")
print(table(train_baked$desenlace))

# ==============================================================================
# SECTION 2: SELECT THE 8 SHAP CONSENSUS FEATURES
# ==============================================================================

cat("\n--- SECTION 2: Selecting 8 SHAP Consensus Features ---\n")

# Define the 9 predictors (8 features, but severity splits into 2 dummies)
# These are the exact column names in the baked data
consensus_features <- c(
  "edad",
  "albumina",
  "bilirrtotal",
  "log_plaquetas",
  "severidad_sars_Moderado",
  "severidad_sars_Severo",
  "sxingr_disnea_TRUE.",
  "sxingr_cefalea_TRUE.",
  "sexo_mujer"
)

# Verify all features exist in baked data
available_cols <- names(train_baked)
missing <- setdiff(consensus_features, available_cols)

if (length(missing) > 0) {
  cat("WARNING: These features not found in baked data:\n")
  print(missing)
  cat("\nAvailable columns:\n")
  print(available_cols)
  stop("Fix feature names before proceeding!")
} else {
  cat("All 9 predictors (8 features + severity split) found in baked data.\n")
}

# Subset data to only consensus features + outcome
train_parsi <- train_baked %>%
  dplyr::select(dplyr::all_of(c(consensus_features, "desenlace")))
test_parsi <- test_baked %>%
  dplyr::select(dplyr::all_of(c(consensus_features, "desenlace")))

cat("Parsimonious training dimensions:", nrow(train_parsi), "x", ncol(train_parsi), "\n")
cat("Parsimonious testing dimensions:", nrow(test_parsi), "x", ncol(test_parsi), "\n")

# ==============================================================================
# SECTION 3: EPV VERIFICATION
# ==============================================================================

cat("\n--- SECTION 3: EPV Verification ---\n")

n_events <- sum(train_parsi$desenlace == "Fallecido")
n_predictors <- length(consensus_features)  # 9
epv <- n_events / n_predictors

cat("Events (deaths) in training:", n_events, "\n")
cat("Predictors:", n_predictors, "\n")
cat("EPV (Events Per Variable):", round(epv, 1), "\n")
cat("Status:", ifelse(epv >= 10, "ADEQUATE (>= 10)", "WARNING: < 10"), "\n")

# Save EPV analysis
epv_df <- data.frame(
  Metric = c("Events (deaths)", "Predictors", "EPV"),
  Value = c(n_events, n_predictors, round(epv, 2)),
  Status = c(NA, NA, ifelse(epv >= 10, "ADEQUATE", "WARNING"))
)
utils::write.csv(epv_df, "results/Table_EPV_Parsimonious.csv", row.names = FALSE)
cat("Saved: results/Table_EPV_Parsimonious.csv\n")

# ==============================================================================
# SECTION 4: FIT STANDARD LOGISTIC REGRESSION
# ==============================================================================

cat("\n--- SECTION 4: Fit Standard Logistic Regression ---\n")

# Check current factor levels
cat("Original outcome levels:", levels(train_parsi$desenlace), "\n")
cat("Reference level (coded as 0):", levels(train_parsi$desenlace)[1], "\n")

# Relevel so Vivo is reference — this means glm will model P(Fallecido | X)
train_parsi$desenlace <- stats::relevel(train_parsi$desenlace, ref = "Vivo")
test_parsi$desenlace <- stats::relevel(test_parsi$desenlace, ref = "Vivo")

cat("After releveling - Reference level:", levels(train_parsi$desenlace)[1], "\n")
cat("Modeled probability:", levels(train_parsi$desenlace)[2], "\n")

# Fit standard glm
glm_parsi <- stats::glm(
  desenlace ~ .,
  data = train_parsi,
  family = stats::binomial(link = "logit")
)

# Check convergence
cat("\n=== MODEL FIT ===\n")
cat("Converged:", glm_parsi$converged, "\n")
cat("AIC:", round(glm_parsi$aic, 1), "\n")
cat("Null deviance:", round(glm_parsi$null.deviance, 1), "\n")
cat("Residual deviance:", round(glm_parsi$deviance, 1), "\n")

# Check for separation: Look for extreme coefficients
cat("\n=== COEFFICIENT CHECK ===\n")
coef_summary <- summary(glm_parsi)$coefficients
print(round(coef_summary, 4))

# Flag any coefficient with |estimate| > 10 (potential separation indicator)
extreme_coefs <- abs(stats::coef(glm_parsi)) > 10
if (any(extreme_coefs[-1])) {  # Exclude intercept
  cat("\nWARNING: Extreme coefficients detected:\n")
  print(stats::coef(glm_parsi)[extreme_coefs])
  cat("If severity coefficients are extreme, this may be expected due to strong effect.\n")
} else {
  cat("\nNo extreme coefficients detected. Standard MLE appears stable.\n")
}

# ==============================================================================
# SECTION 5: ODDS RATIOS WITH 95% PROFILE LIKELIHOOD CI
# ==============================================================================

cat("\n--- SECTION 5: Odds Ratios with Profile Likelihood CI ---\n")

# Calculate profile likelihood confidence intervals (more accurate than Wald)
cat("Calculating profile likelihood confidence intervals...\n")
profile_ci <- stats::confint(glm_parsi)

# Create OR table
or_table <- data.frame(
  Variable = names(stats::coef(glm_parsi))[-1],  # Exclude intercept
  Coefficient = stats::coef(glm_parsi)[-1],
  OR = exp(stats::coef(glm_parsi)[-1]),
  CI_Lower = exp(profile_ci[-1, 1]),
  CI_Upper = exp(profile_ci[-1, 2]),
  p_value = summary(glm_parsi)$coefficients[-1, "Pr(>|z|)"],
  stringsAsFactors = FALSE
)
rownames(or_table) <- NULL

# Add significance stars
or_table$Significance <- dplyr::case_when(
  or_table$p_value < 0.001 ~ "***",
  or_table$p_value < 0.01 ~ "**",
  or_table$p_value < 0.05 ~ "*",
  or_table$p_value < 0.10 ~ ".",
  TRUE ~ ""
)

# Sort by p-value
or_table <- or_table[order(or_table$p_value), ]

cat("\n=== ODDS RATIOS ===\n")
print(or_table[, c("Variable", "OR", "CI_Lower", "CI_Upper", "p_value", "Significance")])

# CRITICAL VERIFICATION: Are ORs finite and plausible?
cat("\n=== OR PLAUSIBILITY CHECK ===\n")

severity_or <- or_table[grepl("severidad", or_table$Variable), ]
if (nrow(severity_or) > 0) {
  cat("Severity Severo OR:", round(severity_or$OR[grepl("Severo", severity_or$Variable)], 2), "\n")
  cat("Severity Moderado OR:", round(severity_or$OR[grepl("Moderado", severity_or$Variable)], 2), "\n")
}

cat("Age OR (per 1 SD):", round(or_table$OR[or_table$Variable == "edad"], 2), "\n")
cat("Albumin OR (per 1 SD):", round(or_table$OR[or_table$Variable == "albumina"], 2), "\n")

# Check if any CI includes infinity
infinite_ci <- is.infinite(or_table$CI_Lower) | is.infinite(or_table$CI_Upper)
if (any(infinite_ci)) {
  cat("\n*** ALERT: Infinite CI detected for:", or_table$Variable[infinite_ci], "***\n")
  cat("*** Consider Firth's method for this model. ***\n")
} else {
  cat("\nAll confidence intervals are finite. Standard glm() is adequate.\n")
}

# Save OR table
utils::write.csv(or_table, "results/Table_OddsRatios_Parsimonious.csv", row.names = FALSE)
cat("Saved: results/Table_OddsRatios_Parsimonious.csv\n")

# ==============================================================================
# SECTION 6: PUBLICATION-QUALITY OR TABLE (gtsummary)
# ==============================================================================

cat("\n--- SECTION 6: Publication-Quality OR Table ---\n")

# Create gtsummary table
tbl_or <- gtsummary::tbl_regression(
  glm_parsi,
  exponentiate = TRUE,
  label = list(
    edad ~ "Age (per 1 SD)",
    albumina ~ "Serum Albumin (per 1 SD)",
    bilirrtotal ~ "Total Bilirubin (per 1 SD)",
    log_plaquetas ~ "Platelet Count, log (per 1 SD)",
    severidad_sars_Moderado ~ "COVID Severity: Moderate vs. Mild",
    severidad_sars_Severo ~ "COVID Severity: Severe vs. Mild",
    `sxingr_disnea_TRUE.` ~ "Dyspnea at Admission",
    `sxingr_cefalea_TRUE.` ~ "Headache at Admission",
    sexo_mujer ~ "Female Sex"
  ),
  pvalue_fun = ~ gtsummary::style_pvalue(.x, digits = 3)
) %>%
  gtsummary::bold_p(t = 0.05) %>%
  gtsummary::modify_header(label ~ "**Predictor**") %>%
  gtsummary::modify_caption("**Parsimonious Logistic Regression: Odds Ratios for SHAP-Consensus Predictors**")

# Save as HTML
tryCatch({
  tbl_or %>%
    gtsummary::as_gt() %>%
    gt::gtsave("results/Table_OddsRatios_Parsimonious_Publication.html")
  cat("Saved: results/Table_OddsRatios_Parsimonious_Publication.html\n")
}, error = function(e) {
  cat("Note: HTML table creation skipped:", e$message, "\n")
})

# Also save as CSV
tbl_or_df <- tbl_or %>% gtsummary::as_tibble()
utils::write.csv(tbl_or_df, "results/Table_OddsRatios_Parsimonious_Publication.csv", row.names = FALSE)
cat("Saved: results/Table_OddsRatios_Parsimonious_Publication.csv\n")

# ==============================================================================
# SECTION 7: PREDICTIONS ON TEST SET (PROBABILITY SCALE)
# ==============================================================================

cat("\n--- SECTION 7: Predictions on Test Set ---\n")

# predict.glm with type = "response" gives probabilities directly
pred_probs <- stats::predict(glm_parsi, newdata = test_parsi, type = "response")

# CRITICAL VERIFICATION: Must be on [0, 1] scale
cat("Prediction range:", round(range(pred_probs), 4), "\n")
cat("Mean predicted probability:", round(mean(pred_probs), 4), "\n")

if (any(pred_probs < 0) | any(pred_probs > 1)) {
  stop("CRITICAL ERROR: Predictions outside [0, 1] range!")
}
stopifnot(all(pred_probs >= 0 & pred_probs <= 1))
cat("VERIFIED: All predictions on probability scale [0, 1].\n")

# ==============================================================================
# SECTION 8: ROC ANALYSIS AND THRESHOLD
# ==============================================================================

cat("\n--- SECTION 8: ROC Analysis and Threshold ---\n")

# Build ROC object
# Direction "<" means: lower predictor values = "Vivo", higher = "Fallecido"
roc_parsi <- pROC::roc(
  response = test_parsi$desenlace,
  predictor = pred_probs,
  levels = c("Vivo", "Fallecido"),
  direction = "<",
  quiet = TRUE
)

cat("AUC:", round(pROC::auc(roc_parsi), 4), "\n")

# Bootstrap 95% CI for AUC
cat("Calculating bootstrap 95% CI for AUC (2000 iterations)...\n")
auc_ci <- pROC::ci.auc(roc_parsi, method = "bootstrap", boot.n = 2000,
                        progress = "none", parallel = FALSE)
cat("AUC 95% CI:", round(auc_ci[1], 4), "-", round(auc_ci[3], 4), "\n")

# Youden threshold (automatically on probability scale from pROC)
youden_coords <- pROC::coords(
  roc_parsi,
  x = "best",
  best.method = "youden",
  ret = c("threshold", "sensitivity", "specificity"),
  transpose = FALSE
)

# Handle case where multiple thresholds have same Youden J
if (nrow(youden_coords) > 1) {
  cat("Multiple optimal thresholds found. Using first.\n")
  youden_coords <- youden_coords[1, ]
}

youden_threshold <- youden_coords$threshold
youden_sensitivity <- youden_coords$sensitivity
youden_specificity <- youden_coords$specificity

# CRITICAL VERIFICATION: Threshold must be between 0 and 1
cat("Youden threshold:", round(youden_threshold, 4), "\n")
cat("Sensitivity at threshold:", round(youden_sensitivity, 4), "\n")
cat("Specificity at threshold:", round(youden_specificity, 4), "\n")

if (youden_threshold < 0 | youden_threshold > 1) {
  stop("CRITICAL ERROR: Threshold outside [0, 1] range!")
}
stopifnot(youden_threshold >= 0 & youden_threshold <= 1)
cat("VERIFIED: Threshold is on probability scale [0, 1].\n")

# ==============================================================================
# SECTION 9: CLASSIFICATION METRICS AT YOUDEN THRESHOLD
# ==============================================================================

cat("\n--- SECTION 9: Classification Metrics ---\n")

# Apply threshold
predicted_class <- factor(
  ifelse(pred_probs >= youden_threshold, "Fallecido", "Vivo"),
  levels = c("Vivo", "Fallecido")
)

# Confusion matrix
actual_class <- test_parsi$desenlace
cm <- table(Predicted = predicted_class, Actual = actual_class)

cat("\nConfusion Matrix:\n")
print(cm)

# VERIFICATION: Both classes must be predicted
if (nrow(cm) != 2 || ncol(cm) != 2) {
  cat("\nWARNING: Confusion matrix incomplete!\n")
} else if (any(rowSums(cm) == 0)) {
  cat("\nWARNING: Not all predicted classes used!\n")
} else {
  cat("\nVERIFIED: Both predicted classes used.\n")
}

# Extract counts
TP <- cm["Fallecido", "Fallecido"]
TN <- cm["Vivo", "Vivo"]
FP <- cm["Fallecido", "Vivo"]
FN <- cm["Vivo", "Fallecido"]

# Compute metrics
sensitivity <- TP / (TP + FN)
specificity <- TN / (TN + FP)
ppv <- TP / (TP + FP)
npv <- TN / (TN + FN)
accuracy <- (TP + TN) / sum(cm)

# Kappa
observed_agreement <- accuracy
expected_agreement <- ((TP + FP) * (TP + FN) + (TN + FN) * (TN + FP)) / sum(cm)^2
kappa_val <- (observed_agreement - expected_agreement) / (1 - expected_agreement)

# PR-AUC
pr_obj <- PRROC::pr.curve(
  scores.class0 = pred_probs[actual_class == "Fallecido"],
  scores.class1 = pred_probs[actual_class == "Vivo"],
  curve = FALSE
)
pr_auc <- pr_obj$auc.integral

# Brier Score
actual_binary <- as.numeric(actual_class == "Fallecido")
brier_score <- mean((pred_probs - actual_binary)^2)

# Compile metrics
metrics_df <- data.frame(
  Metric = c("ROC-AUC", "AUC_Lower", "AUC_Upper", "PR-AUC", "Brier_Score",
             "Threshold", "Sensitivity", "Specificity", "PPV", "NPV",
             "Accuracy", "Kappa"),
  Value = round(c(pROC::auc(roc_parsi), auc_ci[1], auc_ci[3], pr_auc, brier_score,
                  youden_threshold, sensitivity, specificity, ppv, npv,
                  accuracy, kappa_val), 4),
  stringsAsFactors = FALSE
)

cat("\n=== PERFORMANCE METRICS ===\n")
print(metrics_df)

# Verify NPV is not NaN
if (is.nan(npv)) {
  cat("\nWARNING: NPV is NaN!\n")
} else {
  cat("\nVERIFIED: NPV is not NaN.\n")
}

# Save metrics
utils::write.csv(metrics_df, "results/Table_Parsimonious_Metrics.csv", row.names = FALSE)
cat("Saved: results/Table_Parsimonious_Metrics.csv\n")

# ==============================================================================
# SECTION 10: CALIBRATION ASSESSMENT
# ==============================================================================

cat("\n--- SECTION 10: Calibration Assessment ---\n")

# Calibration model: logit(observed) = alpha + beta * logit(predicted)
# Ideal: alpha = 0, beta = 1
pred_probs_cal <- pmax(pmin(pred_probs, 1 - 1e-10), 1e-10)  # Clip to avoid Inf
cal_logit_preds <- stats::qlogis(pred_probs_cal)

cal_model <- stats::glm(actual_binary ~ cal_logit_preds, family = stats::binomial())
cal_intercept <- stats::coef(cal_model)[1]
cal_slope <- stats::coef(cal_model)[2]

cat("Calibration intercept:", round(cal_intercept, 4), "(ideal: 0)\n")
cat("Calibration slope:", round(cal_slope, 4), "(ideal: 1)\n")

if (abs(cal_intercept) < 0.5 & cal_slope > 0.8 & cal_slope < 1.2) {
  cat("OK: Calibration appears adequate.\n")
} else {
  cat("WARNING: Calibration may be suboptimal.\n")
}

# Save calibration
cal_df <- data.frame(
  Metric = c("Intercept", "Slope", "Intercept_SE", "Slope_SE"),
  Value = c(
    round(cal_intercept, 4),
    round(cal_slope, 4),
    round(summary(cal_model)$coefficients[1, 2], 4),
    round(summary(cal_model)$coefficients[2, 2], 4)
  ),
  Ideal = c(0, 1, NA, NA)
)
utils::write.csv(cal_df, "results/Table_Calibration_Parsimonious.csv", row.names = FALSE)
cat("Saved: results/Table_Calibration_Parsimonious.csv\n")

# ==============================================================================
# SECTION 11: HOSMER-LEMESHOW TEST
# ==============================================================================

cat("\n--- SECTION 11: Hosmer-Lemeshow Goodness-of-Fit ---\n")

hl_test <- tryCatch({
  ResourceSelection::hoslem.test(x = actual_binary, y = pred_probs, g = 10)
}, error = function(e) {
  cat("H-L with g=10 failed. Trying g=8...\n")
  tryCatch({
    ResourceSelection::hoslem.test(x = actual_binary, y = pred_probs, g = 8)
  }, error = function(e2) {
    cat("H-L with g=8 failed. Trying g=5...\n")
    tryCatch({
      ResourceSelection::hoslem.test(x = actual_binary, y = pred_probs, g = 5)
    }, error = function(e3) {
      cat("ERROR: H-L test failed with all group sizes.\n")
      NULL
    })
  })
})

if (!is.null(hl_test)) {
  cat("H-L Chi-square:", round(hl_test$statistic, 4), "\n")
  cat("Degrees of freedom:", hl_test$parameter, "\n")
  cat("H-L p-value:", round(hl_test$p.value, 4), "\n")
  cat("Interpretation:", ifelse(hl_test$p.value > 0.05,
      "Adequate fit (fail to reject H0)", "Poor fit (reject H0)"), "\n")

  # Save
  hl_df <- data.frame(
    Statistic = c("Chi_Square", "df", "p_value"),
    Value = c(round(hl_test$statistic, 4), hl_test$parameter, round(hl_test$p.value, 4))
  )
  utils::write.csv(hl_df, "results/Table_HosmerLemeshow_Parsimonious.csv", row.names = FALSE)
  cat("Saved: results/Table_HosmerLemeshow_Parsimonious.csv\n")
} else {
  cat("Hosmer-Lemeshow test could not be computed.\n")
}

# ==============================================================================
# SECTION 12: DELONG COMPARISONS VS ALL OTHER MODELS
# ==============================================================================

cat("\n--- SECTION 12: DeLong Comparisons ---\n")

# Load existing ROC objects from multi-model comparison
roc_list <- tryCatch(readRDS("roc_list_multimodel.rds"), error = function(e) NULL)

if (!is.null(roc_list)) {
  delong_results <- data.frame(
    Comparison = character(),
    AUC_Parsi = numeric(),
    AUC_Other = numeric(),
    Delta_AUC = numeric(),
    DeLong_Z = numeric(),
    p_value = numeric(),
    stringsAsFactors = FALSE
  )

  for (model_name in names(roc_list)) {
    tryCatch({
      dt <- pROC::roc.test(roc_parsi, roc_list[[model_name]], method = "delong")
      delong_results <- rbind(delong_results, data.frame(
        Comparison = paste("Parsimonious vs", model_name),
        AUC_Parsi = round(pROC::auc(roc_parsi), 4),
        AUC_Other = round(pROC::auc(roc_list[[model_name]]), 4),
        Delta_AUC = round(pROC::auc(roc_parsi) - pROC::auc(roc_list[[model_name]]), 4),
        DeLong_Z = round(dt$statistic, 4),
        p_value = round(dt$p.value, 4),
        stringsAsFactors = FALSE
      ))
      cat("  ", model_name, ": delta =",
          round(pROC::auc(roc_parsi) - pROC::auc(roc_list[[model_name]]), 4),
          ", p =", round(dt$p.value, 4), "\n")
    }, error = function(e) {
      cat("  Error comparing to", model_name, ":", e$message, "\n")
    })
  }

  if (nrow(delong_results) > 0) {
    cat("\n=== DELONG COMPARISON SUMMARY ===\n")
    print(delong_results)
    utils::write.csv(delong_results, "results/Table_DeLong_Parsimonious.csv", row.names = FALSE)
    cat("Saved: results/Table_DeLong_Parsimonious.csv\n")
  }
} else {
  cat("roc_list_multimodel.rds not found. Skipping DeLong comparisons.\n")
}

# ==============================================================================
# SECTION 13: ASSUMPTION DIAGNOSTICS
# ==============================================================================

cat("\n--- SECTION 13: Assumption Diagnostics ---\n")

# VIF (standard, since all predictors are single-df in this subset)
cat("VIF Analysis...\n")
vif_parsi <- car::vif(glm_parsi)
cat("VIF values:\n")
print(round(vif_parsi, 2))

# Note: severity dummies will have high VIF with each other (expected, structural)
# Flag only non-severity variables with VIF > 5
non_severity <- !grepl("severidad", names(vif_parsi))
problematic_vif <- vif_parsi[non_severity] > 5

if (any(problematic_vif)) {
  cat("WARNING: High VIF in non-severity variables:",
      names(vif_parsi[non_severity][problematic_vif]), "\n")
} else {
  cat("No multicollinearity concerns (excluding structural severity correlation).\n")
}

# Save VIF
vif_df <- data.frame(
  Variable = names(vif_parsi),
  VIF = round(vif_parsi, 2),
  Concern = ifelse(vif_parsi > 5 & !grepl("severidad", names(vif_parsi)), "YES", "")
)
utils::write.csv(vif_df, "results/Table_VIF_Parsimonious.csv", row.names = FALSE)
cat("Saved: results/Table_VIF_Parsimonious.csv\n")

# Linearity: Test via quadratic term
cat("\nLinearity Assessment (Quadratic Term Test)...\n")

continuous_vars <- c("edad", "albumina", "bilirrtotal", "log_plaquetas")

linearity_results <- data.frame(
  Variable = character(),
  Quadratic_p = numeric(),
  Linear = character(),
  stringsAsFactors = FALSE
)

for (var in continuous_vars) {
  tryCatch({
    # Add quadratic term and test significance
    formula_quad <- stats::as.formula(paste("desenlace ~ . + I(", var, "^2)"))
    glm_quad <- stats::glm(formula_quad, data = train_parsi, family = stats::binomial())
    quad_term <- paste0("I(", var, "^2)")
    quad_p <- summary(glm_quad)$coefficients[quad_term, "Pr(>|z|)"]

    linearity_results <- rbind(linearity_results, data.frame(
      Variable = var,
      Quadratic_p = round(quad_p, 4),
      Linear = ifelse(quad_p >= 0.05, "Yes (p >= 0.05)", "No (p < 0.05)"),
      stringsAsFactors = FALSE
    ))
    cat("  ", var, ": quadratic p =", round(quad_p, 4),
        ifelse(quad_p >= 0.05, "(Linear OK)", "(Non-linear)"), "\n")
  }, error = function(e) {
    cat("  Skipping", var, ":", e$message, "\n")
  })
}

utils::write.csv(linearity_results, "results/Table_Linearity_Parsimonious.csv", row.names = FALSE)
cat("Saved: results/Table_Linearity_Parsimonious.csv\n")

# ==============================================================================
# SECTION 14: EXPORT ALL ARTIFACTS
# ==============================================================================

cat("\n--- SECTION 14: Exporting Artifacts ---\n")

saveRDS(glm_parsi, "model_logreg_parsimonious.rds")
saveRDS(roc_parsi, "roc_logreg_parsimonious.rds")
saveRDS(pred_probs, "preds_logreg_parsimonious.rds")

cat("Saved: model_logreg_parsimonious.rds\n")
cat("Saved: roc_logreg_parsimonious.rds\n")
cat("Saved: preds_logreg_parsimonious.rds\n")

# ==============================================================================
# SECTION 15: FINAL VERIFICATION CHECKLIST
# ==============================================================================

cat("\n")
cat("===============================================================================\n")
cat("=== PARSIMONIOUS LOGREG: VERIFICATION CHECKLIST ===\n")
cat("===============================================================================\n")

cat("\n1. Method: Standard glm() [NO exotic penalization]:", glm_parsi$converged, "\n")
cat("2. EPV:", round(epv, 1), ifelse(epv >= 10, "[ADEQUATE]", "[WARNING]"), "\n")
cat("3. N predictors:", n_predictors, "\n")
cat("4. Threshold:", round(youden_threshold, 4), "[PROBABILITY SCALE]\n")
cat("5. Sensitivity:", round(sensitivity, 4), "\n")
cat("6. Specificity:", round(specificity, 4), ifelse(specificity > 0, "[> 0: OK]", "[FAILED]"), "\n")
cat("7. NPV:", round(npv, 4), ifelse(!is.nan(npv), "[NOT NaN: OK]", "[FAILED]"), "\n")
cat("8. AUC:", round(pROC::auc(roc_parsi), 4), "\n")

if (!is.null(hl_test) && !is.nan(hl_test$p.value)) {
  cat("9. H-L p-value:", round(hl_test$p.value, 4), "[NOT NaN: OK]\n")
} else {
  cat("9. H-L p-value: [COULD NOT COMPUTE]\n")
}

# Check OR CIs
infinite_ci_check <- any(is.infinite(or_table$CI_Lower) | is.infinite(or_table$CI_Upper))
cat("10. OR CIs finite:", ifelse(!infinite_ci_check, "[OK]", "[FAILED]"), "\n")

cat("\n")
cat("===============================================================================\n")
cat("OUTPUTS\n")
cat("===============================================================================\n")
cat("\nTables:\n")
cat("  - results/Table_EPV_Parsimonious.csv\n")
cat("  - results/Table_OddsRatios_Parsimonious.csv\n")
cat("  - results/Table_OddsRatios_Parsimonious_Publication.html\n")
cat("  - results/Table_OddsRatios_Parsimonious_Publication.csv\n")
cat("  - results/Table_Parsimonious_Metrics.csv\n")
cat("  - results/Table_Calibration_Parsimonious.csv\n")
cat("  - results/Table_HosmerLemeshow_Parsimonious.csv\n")
cat("  - results/Table_DeLong_Parsimonious.csv\n")
cat("  - results/Table_VIF_Parsimonious.csv\n")
cat("  - results/Table_Linearity_Parsimonious.csv\n")
cat("\nModel artifacts:\n")
cat("  - model_logreg_parsimonious.rds\n")
cat("  - roc_logreg_parsimonious.rds\n")
cat("  - preds_logreg_parsimonious.rds\n")

cat("\n")
cat("===============================================================================\n")
cat("ROLE IN THE PAPER\n")
cat("===============================================================================\n")
cat("  - Original LogReg (37 vars, AUC 0.877) --> PRIMARY AUC benchmark (Table 3)\n")
cat("  - Firth LogReg (36 vars, AUC 0.859) --> Stable OR with separation handling\n")
cat("  - Parsimonious LogReg (9 vars) --> Clean OR table, clinical interpretation\n")
cat("  - All three serve DIFFERENT purposes and belong in the paper\n")
cat("===============================================================================\n")
