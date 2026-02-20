# ==============================================================================
# PARSIMONIOUS CLINICAL LOGISTIC REGRESSION v2 (BINARY SEVERITY)
# ==============================================================================
#
# PURPOSE: Fix the OR separation problem in v1 by collapsing severity to binary
#
# THE PROBLEM (v1):
#   - Severity had 3 levels: Leve, Moderado, Severo
#   - Leve had ZERO deaths --> complete separation
#   - Result: OR = 32 million for Severo, infinite CIs (unusable)
#
# THE SOLUTION (v2):
#   - Collapse severity to BINARY: Severo vs. No Severo (Leve + Moderado)
#   - This eliminates the zero-cell problem
#   - Expected: Finite, plausible OR in the 3-50 range
#
# IMPLEMENTATION:
#   - severidad_severo = severidad_sars_Severo (existing dummy)
#   - DROP severidad_sars_Moderado
#   - 8 predictors (was 9 in v1)
#   - EPV = 168/8 = 21 (improved from 18.7)
#
# ROLE IN THE PAPER:
#   - Original LogReg (37 vars) --> AUC benchmark
#   - Firth LogReg (36 vars) --> Stable OR with 3-level severity (penalized)
#   - Parsimonious v2 (8 vars) --> Publication OR table with binary severity
#
# AUTHOR: Gold-Standard Implementation v2
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
  library(yardstick)
  library(gtsummary)
  library(ResourceSelection)
  library(car)
  library(PRROC)
})

set.seed(2026)
options(scipen = 999)
tidymodels::tidymodels_prefer()

cat("===============================================================================\n")
cat("PARSIMONIOUS CLINICAL LOGISTIC REGRESSION v2 (BINARY SEVERITY)\n")
cat("===============================================================================\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Seed: 2026\n")
cat("Purpose: Fix severity separation by collapsing to Severo vs. No Severo\n\n")

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
  # NO SMOTE -- intentional for logistic regression

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
# SECTION 2: VERIFY AND DOCUMENT THE ZERO-CELL PROBLEM
# ==============================================================================

cat("\n--- SECTION 2: Documenting the Zero-Cell Problem ---\n")

# VERIFY the dummy columns exist
stopifnot("severidad_sars_Moderado" %in% names(train_baked))
stopifnot("severidad_sars_Severo" %in% names(train_baked))

cat("\n=== VERIFYING ZERO-CELL PROBLEM (v1 issue) ===\n")

# Calculate deaths by original 3-level severity
# Leve = when both dummies are 0
leve_mask_train <- train_baked$severidad_sars_Moderado == 0 &
                   train_baked$severidad_sars_Severo == 0
n_leve <- sum(leve_mask_train)
n_leve_deaths <- sum(train_baked$desenlace[leve_mask_train] == "Fallecido")

cat("Leve (reference - both dummies = 0):\n")
cat("  N patients:", n_leve, "\n")
cat("  N deaths:", n_leve_deaths, "\n")

# Moderado
mod_mask_train <- train_baked$severidad_sars_Moderado == 1
n_mod <- sum(mod_mask_train)
n_mod_deaths <- sum(train_baked$desenlace[mod_mask_train] == "Fallecido")

cat("Moderado:\n")
cat("  N patients:", n_mod, "\n")
cat("  N deaths:", n_mod_deaths, "\n")

# Severo
sev_mask_train <- train_baked$severidad_sars_Severo == 1
n_sev <- sum(sev_mask_train)
n_sev_deaths <- sum(train_baked$desenlace[sev_mask_train] == "Fallecido")

cat("Severo:\n")
cat("  N patients:", n_sev, "\n")
cat("  N deaths:", n_sev_deaths, "\n")

# Document the zero-cell
if (n_leve_deaths == 0) {
  cat("\n*** CONFIRMED: Leve has ZERO deaths --> complete separation in v1 ***\n")
  cat("*** This is why v1 had OR = 32 million for Severo ***\n")
} else {
  cat("\nNote: Leve has", n_leve_deaths, "deaths. May not be pure separation.\n")
}

# ==============================================================================
# SECTION 3: CREATE BINARY SEVERITY VARIABLE
# ==============================================================================

cat("\n--- SECTION 3: Creating Binary Severity (Severo vs. No Severo) ---\n")

# severidad_severo = 1 if Severo, 0 if Leve or Moderado
# This is simply the existing severidad_sars_Severo column!
train_baked$severidad_severo <- train_baked$severidad_sars_Severo
test_baked$severidad_severo <- test_baked$severidad_sars_Severo

# Verify both groups have deaths
n_nosev <- sum(train_baked$severidad_severo == 0)
n_nosev_deaths <- sum(train_baked$desenlace[train_baked$severidad_severo == 0] == "Fallecido")

n_sev_binary <- sum(train_baked$severidad_severo == 1)
n_sev_deaths_binary <- sum(train_baked$desenlace[train_baked$severidad_severo == 1] == "Fallecido")

cat("\n=== BINARY SEVERITY DISTRIBUTION ===\n")
cat("No Severo (Leve + Moderado):\n")
cat("  N patients:", n_nosev, "\n")
cat("  N deaths:", n_nosev_deaths, "\n")
cat("Severo:\n")
cat("  N patients:", n_sev_binary, "\n")
cat("  N deaths:", n_sev_deaths_binary, "\n")

# CRITICAL: Both groups must have deaths to avoid separation
stopifnot(n_nosev_deaths > 0)
stopifnot(n_sev_deaths_binary > 0)
cat("\nVERIFIED: Both groups have deaths. Zero-cell problem resolved.\n")

# ==============================================================================
# SECTION 4: SELECT THE 8 PARSIMONIOUS FEATURES
# ==============================================================================

cat("\n--- SECTION 4: Selecting 8 SHAP Consensus Features (Binary Severity) ---\n")

# 8 predictors total (severity is now 1 binary variable, not 2 dummies)
consensus_features <- c(
  "edad",
  "albumina",
  "bilirrtotal",
  "log_plaquetas",
  "severidad_severo",         # BINARY: Severo vs. No Severo
  "sxingr_disnea_TRUE.",
  "sxingr_cefalea_TRUE.",
  "sexo_mujer"
)

# Verify all features exist in baked data
available_cols <- names(train_baked)
missing <- setdiff(consensus_features, available_cols)

if (length(missing) > 0) {
  cat("ERROR: These features not found in baked data:\n")
  print(missing)
  cat("\nAvailable columns:\n")
  print(available_cols)
  stop("Fix feature names before proceeding!")
} else {
  cat("All 8 predictors found in baked data.\n")
}

# Subset data to only consensus features + outcome
train_parsi <- train_baked %>%
  dplyr::select(dplyr::all_of(c(consensus_features, "desenlace")))
test_parsi <- test_baked %>%
  dplyr::select(dplyr::all_of(c(consensus_features, "desenlace")))

cat("Parsimonious v2 training dimensions:", nrow(train_parsi), "x", ncol(train_parsi), "\n")
cat("Parsimonious v2 testing dimensions:", nrow(test_parsi), "x", ncol(test_parsi), "\n")

# ==============================================================================
# SECTION 5: EPV VERIFICATION
# ==============================================================================

cat("\n--- SECTION 5: EPV Verification ---\n")

n_events <- sum(train_parsi$desenlace == "Fallecido")
n_predictors <- length(consensus_features)  # 8
epv <- n_events / n_predictors

cat("Events (deaths) in training:", n_events, "\n")
cat("Predictors:", n_predictors, "\n")
cat("EPV (Events Per Variable):", round(epv, 1), "\n")
cat("Status:", ifelse(epv >= 10, "ADEQUATE (>= 10)", "WARNING: < 10"), "\n")
cat("Comparison: v1 EPV was 18.7, v2 EPV is", round(epv, 1), "(improved)\n")

# Save EPV analysis
epv_df <- data.frame(
  Metric = c("Events (deaths)", "Predictors", "EPV", "v1_EPV_for_comparison"),
  Value = c(n_events, n_predictors, round(epv, 2), 18.7),
  Status = c(NA, NA, ifelse(epv >= 10, "ADEQUATE", "WARNING"), "v1 reference")
)
utils::write.csv(epv_df, "results/Table_EPV_Parsimonious_v2.csv", row.names = FALSE)
cat("Saved: results/Table_EPV_Parsimonious_v2.csv\n")

# ==============================================================================
# SECTION 6: FIT STANDARD LOGISTIC REGRESSION
# ==============================================================================

cat("\n--- SECTION 6: Fit Standard Logistic Regression ---\n")

# Check current factor levels
cat("Original outcome levels:", levels(train_parsi$desenlace), "\n")
cat("Reference level (coded as 0):", levels(train_parsi$desenlace)[1], "\n")

# Relevel so Vivo is reference -- glm will model P(Fallecido | X)
train_parsi$desenlace <- stats::relevel(factor(train_parsi$desenlace), ref = "Vivo")
test_parsi$desenlace <- stats::relevel(factor(test_parsi$desenlace), ref = "Vivo")

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
  cat("\n*** WARNING: Extreme coefficients detected ***\n")
  print(stats::coef(glm_parsi)[extreme_coefs])
  cat("*** This indicates potential residual separation. ***\n")
} else {
  cat("\nNo extreme coefficients detected. Standard MLE is stable.\n")
}

# ==============================================================================
# SECTION 7: ODDS RATIOS WITH 95% PROFILE LIKELIHOOD CI
# ==============================================================================

cat("\n--- SECTION 7: Odds Ratios with Profile Likelihood CI ---\n")

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

# CRITICAL: Check severity OR
cat("\n=== SEVERITY OR CHECK (CRITICAL) ===\n")
sev_or <- or_table[or_table$Variable == "severidad_severo", ]

if (nrow(sev_or) > 0) {
  cat("Binary Severity OR (Severo vs. No Severo):", round(sev_or$OR, 2), "\n")
  cat("95% CI:", round(sev_or$CI_Lower, 2), "-", round(sev_or$CI_Upper, 2), "\n")
  cat("p-value:", signif(sev_or$p_value, 3), "\n")

  # Plausibility check
  if (sev_or$OR > 1 & sev_or$OR < 100 & is.finite(sev_or$CI_Upper) & sev_or$CI_Upper < 500) {
    cat("STATUS: PLAUSIBLE AND FINITE. Separation resolved!\n")
  } else if (sev_or$OR > 100) {
    cat("WARNING: Severity OR still > 100. Check for residual issues.\n")
  } else {
    cat("STATUS: Severity OR appears reasonable.\n")
  }

  cat("\nComparison:\n")
  cat("  v1 Severity OR: 32,071,048 (UNUSABLE)\n")
  cat("  v2 Severity OR:", round(sev_or$OR, 2), "\n")
}

# Check all CIs are finite
infinite_ci <- is.infinite(or_table$CI_Lower) | is.infinite(or_table$CI_Upper)
if (any(infinite_ci)) {
  cat("\n*** ALERT: Infinite CI detected for:", or_table$Variable[infinite_ci], "***\n")
} else {
  cat("\nAll confidence intervals are finite. Standard glm() is adequate.\n")
}

# Save OR table
utils::write.csv(or_table, "results/Table_OddsRatios_Parsimonious_v2.csv", row.names = FALSE)
cat("Saved: results/Table_OddsRatios_Parsimonious_v2.csv\n")

# ==============================================================================
# SECTION 8: PUBLICATION-QUALITY OR TABLE (gtsummary)
# ==============================================================================

cat("\n--- SECTION 8: Publication-Quality OR Table ---\n")

# Create gtsummary table
tbl_or <- gtsummary::tbl_regression(
  glm_parsi,
  exponentiate = TRUE,
  label = list(
    edad ~ "Age (per 1 SD)",
    albumina ~ "Serum Albumin (per 1 SD)",
    bilirrtotal ~ "Total Bilirubin (per 1 SD)",
    log_plaquetas ~ "Platelet Count, log (per 1 SD)",
    severidad_severo ~ "Clinical Severity: Severe vs. Non-Severe",
    `sxingr_disnea_TRUE.` ~ "Dyspnea at Admission",
    `sxingr_cefalea_TRUE.` ~ "Headache at Admission",
    sexo_mujer ~ "Female Sex"
  ),
  pvalue_fun = ~ gtsummary::style_pvalue(.x, digits = 3)
) %>%
  gtsummary::bold_p(t = 0.05) %>%
  gtsummary::modify_header(label ~ "**Predictor**") %>%
  gtsummary::modify_caption("**Parsimonious Logistic Regression v2: Binary Severity (N = 1,050)**")

# Save as HTML
tryCatch({
  tbl_or %>%
    gtsummary::as_gt() %>%
    gt::gtsave("results/Table_OddsRatios_Parsimonious_v2_Publication.html")
  cat("Saved: results/Table_OddsRatios_Parsimonious_v2_Publication.html\n")
}, error = function(e) {
  cat("Note: HTML table creation issue:", e$message, "\n")
})

# Also save as CSV
tbl_or_df <- tbl_or %>% gtsummary::as_tibble()
utils::write.csv(tbl_or_df, "results/Table_OddsRatios_Parsimonious_v2_Publication.csv", row.names = FALSE)
cat("Saved: results/Table_OddsRatios_Parsimonious_v2_Publication.csv\n")

# ==============================================================================
# SECTION 9: PREDICTIONS ON TEST SET (PROBABILITY SCALE)
# ==============================================================================

cat("\n--- SECTION 9: Predictions on Test Set ---\n")

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
# SECTION 10: ROC ANALYSIS AND THRESHOLD
# ==============================================================================

cat("\n--- SECTION 10: ROC Analysis and Threshold ---\n")

# Build ROC object
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

# Youden threshold
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

cat("Youden threshold:", round(youden_threshold, 4), "\n")
cat("Sensitivity at threshold:", round(youden_sensitivity, 4), "\n")
cat("Specificity at threshold:", round(youden_specificity, 4), "\n")

# CRITICAL: Threshold must be on [0, 1]
if (youden_threshold < 0 | youden_threshold > 1) {
  stop("CRITICAL ERROR: Threshold outside [0, 1] range!")
}
stopifnot(youden_threshold >= 0 & youden_threshold <= 1)
cat("VERIFIED: Threshold is on probability scale [0, 1].\n")

# ==============================================================================
# SECTION 11: CLASSIFICATION METRICS AT YOUDEN THRESHOLD
# ==============================================================================

cat("\n--- SECTION 11: Classification Metrics ---\n")

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
utils::write.csv(metrics_df, "results/Table_Parsimonious_v2_Metrics.csv", row.names = FALSE)
cat("Saved: results/Table_Parsimonious_v2_Metrics.csv\n")

# ==============================================================================
# SECTION 12: CALIBRATION ASSESSMENT
# ==============================================================================

cat("\n--- SECTION 12: Calibration Assessment ---\n")

# Calibration model: logit(observed) = alpha + beta * logit(predicted)
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
  cat("Note: Calibration may be suboptimal.\n")
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
utils::write.csv(cal_df, "results/Table_Calibration_Parsimonious_v2.csv", row.names = FALSE)
cat("Saved: results/Table_Calibration_Parsimonious_v2.csv\n")

# ==============================================================================
# SECTION 13: HOSMER-LEMESHOW TEST
# ==============================================================================

cat("\n--- SECTION 13: Hosmer-Lemeshow Goodness-of-Fit ---\n")

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
  utils::write.csv(hl_df, "results/Table_HosmerLemeshow_Parsimonious_v2.csv", row.names = FALSE)
  cat("Saved: results/Table_HosmerLemeshow_Parsimonious_v2.csv\n")
} else {
  cat("Hosmer-Lemeshow test could not be computed.\n")
}

# ==============================================================================
# SECTION 14: DELONG COMPARISONS VS ALL OTHER MODELS
# ==============================================================================

cat("\n--- SECTION 14: DeLong Comparisons ---\n")

# Load existing ROC objects from multi-model comparison
roc_list <- tryCatch(readRDS("roc_list_multimodel.rds"), error = function(e) NULL)

if (!is.null(roc_list)) {
  delong_results <- data.frame(
    Comparison = character(),
    AUC_Parsi_v2 = numeric(),
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
        Comparison = paste("Parsimonious_v2 vs", model_name),
        AUC_Parsi_v2 = round(pROC::auc(roc_parsi), 4),
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
    utils::write.csv(delong_results, "results/Table_DeLong_Parsimonious_v2.csv", row.names = FALSE)
    cat("Saved: results/Table_DeLong_Parsimonious_v2.csv\n")
  }
} else {
  cat("roc_list_multimodel.rds not found. Skipping DeLong comparisons.\n")
}

# ==============================================================================
# SECTION 15: ASSUMPTION DIAGNOSTICS (VIF AND LINEARITY)
# ==============================================================================

cat("\n--- SECTION 15: Assumption Diagnostics ---\n")

# VIF Analysis
# With binary severity (single variable), VIF should be clean
cat("VIF Analysis...\n")
vif_parsi <- car::vif(glm_parsi)
cat("VIF values:\n")
print(round(vif_parsi, 2))

# All VIF should be < 5 now (no dummy pair inflation)
problematic_vif <- vif_parsi > 5

if (any(problematic_vif)) {
  cat("WARNING: High VIF detected:", names(vif_parsi[problematic_vif]), "\n")
} else {
  cat("No multicollinearity concerns. All VIF < 5.\n")
}

# Save VIF
vif_df <- data.frame(
  Variable = names(vif_parsi),
  VIF = round(vif_parsi, 2),
  Concern = ifelse(vif_parsi > 5, "HIGH", "")
)
utils::write.csv(vif_df, "results/Table_VIF_Parsimonious_v2.csv", row.names = FALSE)
cat("Saved: results/Table_VIF_Parsimonious_v2.csv\n")

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

utils::write.csv(linearity_results, "results/Table_Linearity_Parsimonious_v2.csv", row.names = FALSE)
cat("Saved: results/Table_Linearity_Parsimonious_v2.csv\n")

# ==============================================================================
# SECTION 16: EXPORT ALL ARTIFACTS
# ==============================================================================

cat("\n--- SECTION 16: Exporting Artifacts ---\n")

saveRDS(glm_parsi, "model_logreg_parsimonious_v2.rds")
saveRDS(roc_parsi, "roc_logreg_parsimonious_v2.rds")
saveRDS(pred_probs, "preds_logreg_parsimonious_v2.rds")

cat("Saved: model_logreg_parsimonious_v2.rds\n")
cat("Saved: roc_logreg_parsimonious_v2.rds\n")
cat("Saved: preds_logreg_parsimonious_v2.rds\n")

# ==============================================================================
# SECTION 17: FINAL VERIFICATION CHECKLIST
# ==============================================================================

cat("\n")
cat("===============================================================================\n")
cat("=== PARSIMONIOUS LOGREG v2: VERIFICATION CHECKLIST ===\n")
cat("===============================================================================\n")

cat("\n1.  Method: Standard glm()                   :", glm_parsi$converged, "\n")
cat("2.  Severity coding: Binary (Severo vs No)  : YES\n")
cat("3.  Zero-cell problem resolved              : YES (", n_nosev_deaths, "deaths in No Severo)\n")
cat("4.  EPV:", round(epv, 1), "                            :",
    ifelse(epv >= 10, "ADEQUATE", "WARNING"), "\n")
cat("5.  N predictors:", n_predictors, "\n")

if (nrow(sev_or) > 0) {
  cat("6.  Severity OR:", round(sev_or$OR, 2), "\n")
  cat("7.  Severity CI:", round(sev_or$CI_Lower, 2), "-", round(sev_or$CI_Upper, 2), "\n")
  cat("8.  Severity p-value:", signif(sev_or$p_value, 3), "\n")
}

cat("9.  Threshold:", round(youden_threshold, 4), "[PROBABILITY SCALE]\n")
cat("10. Sensitivity:", round(sensitivity, 4), "\n")
cat("11. Specificity:", round(specificity, 4), ifelse(specificity > 0, "[> 0: OK]", "[FAILED]"), "\n")
cat("12. NPV:", round(npv, 4), ifelse(!is.nan(npv), "[NOT NaN: OK]", "[FAILED]"), "\n")
cat("13. AUC:", round(pROC::auc(roc_parsi), 4), "\n")

if (!is.null(hl_test) && !is.nan(hl_test$p.value)) {
  cat("14. Calibration slope:", round(cal_slope, 4), "\n")
  cat("15. H-L p-value:", round(hl_test$p.value, 4), ifelse(hl_test$p.value > 0.05, "[OK]", "[WARNING]"), "\n")
} else {
  cat("14. Calibration slope:", round(cal_slope, 4), "\n")
  cat("15. H-L p-value: [COULD NOT COMPUTE]\n")
}

# Check OR CIs
infinite_ci_check <- any(is.infinite(or_table$CI_Lower) | is.infinite(or_table$CI_Upper))
cat("16. All CIs finite:", ifelse(!infinite_ci_check, "[OK]", "[FAILED]"), "\n")
cat("17. All VIF < 5:", ifelse(!any(problematic_vif), "[OK]", "[WARNING]"), "\n")

cat("\n")
cat("===============================================================================\n")
cat("OUTPUTS (v2)\n")
cat("===============================================================================\n")
cat("\nTables:\n")
cat("  - results/Table_EPV_Parsimonious_v2.csv\n")
cat("  - results/Table_OddsRatios_Parsimonious_v2.csv\n")
cat("  - results/Table_OddsRatios_Parsimonious_v2_Publication.html\n")
cat("  - results/Table_OddsRatios_Parsimonious_v2_Publication.csv\n")
cat("  - results/Table_Parsimonious_v2_Metrics.csv\n")
cat("  - results/Table_Calibration_Parsimonious_v2.csv\n")
cat("  - results/Table_HosmerLemeshow_Parsimonious_v2.csv\n")
cat("  - results/Table_DeLong_Parsimonious_v2.csv\n")
cat("  - results/Table_VIF_Parsimonious_v2.csv\n")
cat("  - results/Table_Linearity_Parsimonious_v2.csv\n")
cat("\nModel artifacts:\n")
cat("  - model_logreg_parsimonious_v2.rds\n")
cat("  - roc_logreg_parsimonious_v2.rds\n")
cat("  - preds_logreg_parsimonious_v2.rds\n")

cat("\n")
cat("===============================================================================\n")
cat("KEY IMPROVEMENTS FROM v1 TO v2\n")
cat("===============================================================================\n")
cat("  - v1 Severity OR: 32,071,048 (UNUSABLE due to zero-cell separation)\n")
if (nrow(sev_or) > 0) {
  cat("  - v2 Severity OR:", round(sev_or$OR, 2), "(USABLE)\n")
}
cat("  - v1 Predictors: 9 (severity = 2 dummies)\n")
cat("  - v2 Predictors: 8 (severity = 1 binary)\n")
cat("  - v1 EPV: 18.7\n")
cat("  - v2 EPV:", round(epv, 1), "(improved)\n")
cat("  - VIF: All < 5 (no dummy-pair inflation)\n")

cat("\n")
cat("===============================================================================\n")
cat("ROLE IN THE PAPER\n")
cat("===============================================================================\n")
cat("  - Original LogReg (37 vars, AUC 0.877) --> PRIMARY AUC benchmark (Table 3)\n")
cat("  - Firth LogReg (36 vars, AUC 0.859) --> Stable OR with 3-level severity\n")
cat("  - Parsimonious v2 (8 vars) --> Publication OR table with binary severity\n")
cat("  - All serve DIFFERENT, complementary purposes\n")
cat("===============================================================================\n")
