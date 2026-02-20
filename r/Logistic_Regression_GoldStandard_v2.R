# ==============================================================================
# GOLD-STANDARD LOGISTIC REGRESSION v2: FIRTH'S PENALIZED LIKELIHOOD
# ==============================================================================
#
# PURPOSE: Corrected implementation addressing three critical failures from v1:
#   1. Threshold scale mismatch → Compute and apply on PROBABILITY scale
#   2. Quasi-complete separation → Use logistf instead of glm()
#   3. Over-aggressive Lasso → Use Firth (keeps all predictors)
#
# ROLE: Provides stable OR estimates for publication; original LogReg remains
#       PRIMARY benchmark (AUC 0.877). This is SUPPLEMENTARY validation.
#
# AUTHOR: Gold-Standard Implementation v2
# DATE: 2026-02-17
# SEED: 2026
#
# ==============================================================================

# ==============================================================================
# SECTION 0: LIBRARY LOADING AND CONFIGURATION
# ==============================================================================

# Suppress package loading messages
suppressPackageStartupMessages({
  library(tidymodels)
  library(tidyverse)
  library(logistf)           # Firth's penalized logistic regression
  library(car)               # GVIF
  library(pROC)              # ROC, DeLong
  library(glmnet)            # Ridge comparison
  library(gtsummary)         # Publication tables
  library(ResourceSelection) # Hosmer-Lemeshow
  library(PRROC)             # PR-AUC
  library(broom)             # Tidy model output
})

# Configuration
set.seed(2026)
options(scipen = 999)
tidymodels::tidymodels_prefer()

cat("===============================================================================\n")
cat("GOLD-STANDARD LOGISTIC REGRESSION v2: FIRTH'S PENALIZED LIKELIHOOD\n")
cat("===============================================================================\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Seed: 2026\n")
cat("Purpose: Address separation, threshold scale, and OR estimation\n\n")

# Ensure results directory exists
if (!dir.exists("results")) {
  dir.create("results")
  cat("Created: results/ directory\n")
}

# ==============================================================================
# SECTION 1: LOAD DATA AND PREPROCESSING OBJECTS
# ==============================================================================

cat("--- SECTION 1: Loading Data and Preprocessing Objects ---\n")

# Load training and testing data (raw, pre-baked)
df_training <- readRDS("data_training.rds")
df_testing <- readRDS("data_testing.rds")

cat("Training dimensions:", nrow(df_training), "x", ncol(df_training), "\n")
cat("Testing dimensions:", nrow(df_testing), "x", ncol(df_testing), "\n")

# Load the master recipe (same as ML models)
rf_recipe_master <- readRDS("rf_recipe_master.rds")

# Create a NO-SMOTE version of the recipe for logistic regression
# This ensures feature engineering equity without oversampling
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
  # NO SMOTE - intentional for baseline comparison

# Prep and bake
logreg_prep <- recipes::prep(logreg_recipe, training = df_training)
train_baked <- recipes::bake(logreg_prep, new_data = NULL)
test_baked <- recipes::bake(logreg_prep, new_data = df_testing)

cat("Baked training dimensions:", nrow(train_baked), "x", ncol(train_baked), "\n")
cat("Baked testing dimensions:", nrow(test_baked), "x", ncol(test_baked), "\n")

# Verify outcome variable
cat("Outcome levels:", levels(train_baked$desenlace), "\n")
cat("Training outcome distribution:\n")
print(table(train_baked$desenlace))

# ==============================================================================
# SECTION 2: EPV ANALYSIS (DIAGNOSTIC ONLY)
# ==============================================================================

cat("\n--- SECTION 2: Events Per Variable (EPV) Analysis ---\n")

n_events <- sum(train_baked$desenlace == "Fallecido")
n_predictors <- ncol(train_baked) - 1  # Exclude outcome
epv <- n_events / n_predictors

cat("Events (deaths) in training:", n_events, "\n")
cat("Predictors after preprocessing:", n_predictors, "\n")
cat("EPV (Events Per Variable):", round(epv, 2), "\n")

if (epv < 10) {
  cat("WARNING: EPV < 10. Standard logistic regression may be unreliable.\n")
  cat("         Firth's penalization addresses small-sample bias.\n")
} else {
  cat("OK: EPV >= 10 satisfies the rule of thumb.\n")
}

# Save EPV analysis
epv_df <- data.frame(
  Metric = c("Events (deaths)", "Predictors", "EPV"),
  Value = c(n_events, n_predictors, round(epv, 2)),
  Status = c(NA, NA, ifelse(epv < 10, "WARNING: < 10", "OK: >= 10"))
)
utils::write.csv(epv_df, "results/Table_EPV_Analysis.csv", row.names = FALSE)
cat("Saved: results/Table_EPV_Analysis.csv\n")

# ==============================================================================
# SECTION 3: ASSUMPTION TESTING (DIAGNOSTIC APPENDIX)
# ==============================================================================

cat("\n--- SECTION 3: Assumption Testing ---\n")

# ------------------------------------------------------------------------------
# 3A. Multicollinearity — GVIF (Generalized VIF)
# ------------------------------------------------------------------------------

cat("\n3A. Multicollinearity (GVIF) Analysis...\n")

# Fit standard GLM for diagnostics (ignore convergence warnings)
glm_diagnostic <- suppressWarnings(
  stats::glm(desenlace ~ ., data = train_baked, family = stats::binomial())
)

# Calculate GVIF using car::vif()
# For factors, car::vif() returns GVIF, Df, and GVIF^(1/(2*Df))
vif_results <- tryCatch({
  car::vif(glm_diagnostic)
}, error = function(e) {
  cat("WARNING: VIF calculation failed:", e$message, "\n")
  NULL
})

if (!is.null(vif_results)) {
  # Convert to data frame
  if (is.matrix(vif_results)) {
    # For models with factors (returns matrix)
    vif_df <- data.frame(
      Variable = rownames(vif_results),
      GVIF = vif_results[, "GVIF"],
      Df = vif_results[, "Df"],
      GVIF_adj = vif_results[, "GVIF^(1/(2*Df))"],
      stringsAsFactors = FALSE
    )
  } else {
    # For models without factors (returns vector)
    vif_df <- data.frame(
      Variable = names(vif_results),
      GVIF = vif_results,
      Df = 1,
      GVIF_adj = sqrt(vif_results),
      stringsAsFactors = FALSE
    )
  }

  # Flag concerning values (GVIF^(1/(2*Df)) > 2 ~ VIF > 4)
  vif_df$Concern <- ifelse(vif_df$GVIF_adj > 2, "YES", "")
  vif_df <- vif_df[order(-vif_df$GVIF_adj), ]

  cat("Top 10 GVIF values:\n")
  print(head(vif_df, 10))

  n_concerning <- sum(vif_df$GVIF_adj > 2)
  cat("Variables with GVIF^(1/2Df) > 2:", n_concerning, "\n")

  # Save
  utils::write.csv(vif_df, "results/Table_GVIF_Analysis.csv", row.names = FALSE)
  cat("Saved: results/Table_GVIF_Analysis.csv\n")
} else {
  cat("GVIF analysis skipped due to errors.\n")
}

# ------------------------------------------------------------------------------
# 3B. Linearity — Box-Tidwell / Quadratic Terms Test
# ------------------------------------------------------------------------------

cat("\n3B. Linearity Assumption Testing...\n")

# Identify continuous predictors
continuous_vars <- names(train_baked)[sapply(train_baked, is.numeric)]
continuous_vars <- setdiff(continuous_vars, "desenlace")

# Test linearity using quadratic terms (safer than Box-Tidwell with separation)
linearity_results <- data.frame(
  Variable = character(),
  Quadratic_Coef = numeric(),
  Quadratic_SE = numeric(),
  Quadratic_P = numeric(),
  Interpretation = character(),
  stringsAsFactors = FALSE
)

# Test a subset of key continuous variables
key_continuous <- c("edad", "albumina", "bilirrtotal", "plaquetas",
                    "ratio_hepatico", "log_plaquetas")
key_continuous <- intersect(key_continuous, continuous_vars)

for (var in key_continuous) {
  tryCatch({
    # Create formula with quadratic term
    quad_formula <- stats::as.formula(
      paste0("desenlace ~ ", var, " + I(", var, "^2)")
    )
    quad_model <- suppressWarnings(
      stats::glm(quad_formula, data = train_baked, family = stats::binomial())
    )
    quad_coef <- stats::coef(summary(quad_model))

    if (nrow(quad_coef) >= 3) {
      quad_row <- quad_coef[3, ]  # Quadratic term is 3rd row
      linearity_results <- rbind(linearity_results, data.frame(
        Variable = var,
        Quadratic_Coef = round(quad_row["Estimate"], 4),
        Quadratic_SE = round(quad_row["Std. Error"], 4),
        Quadratic_P = round(quad_row["Pr(>|z|)"], 4),
        Interpretation = ifelse(quad_row["Pr(>|z|)"] < 0.05,
                                "Non-linear (p < 0.05)",
                                "Linear (p >= 0.05)"),
        stringsAsFactors = FALSE
      ))
    }
  }, error = function(e) {
    cat("  Skipping", var, ":", e$message, "\n")
  })
}

if (nrow(linearity_results) > 0) {
  print(linearity_results)
  utils::write.csv(linearity_results, "results/Table_Linearity_Tests.csv", row.names = FALSE)
  cat("Saved: results/Table_Linearity_Tests.csv\n")
}

# ------------------------------------------------------------------------------
# 3C. Independence Assumption
# ------------------------------------------------------------------------------

cat("\n3C. Independence Assumption...\n")
cat("LIMITATION: Hospital ID not available in dataset.\n")
cat("            Cannot fit mixed-effects model to account for clustering.\n")
cat("            Assumption of independence between observations may be violated.\n")

# ==============================================================================
# SECTION 4: PRIMARY MODEL — FIRTH'S PENALIZED LOGISTIC REGRESSION
# ==============================================================================

cat("\n--- SECTION 4: Firth's Penalized Logistic Regression ---\n")

# Convert outcome to binary for logistf
# logistf expects 0/1 or factor
train_baked_firth <- train_baked
train_baked_firth$desenlace <- factor(train_baked_firth$desenlace,
                                       levels = c("Vivo", "Fallecido"))

cat("Fitting Firth's penalized logistic regression...\n")
cat("(This may take 1-2 minutes due to profile likelihood CI calculation)\n")

# Fit Firth's penalized logistic regression
firth_model <- logistf::logistf(
  desenlace ~ .,
  data = train_baked_firth,
  control = logistf::logistf.control(maxit = 250)
)

cat("Model converged:", firth_model$converged, "\n")
cat("Iterations:", firth_model$iter, "\n")

# Extract coefficients
firth_coefs <- stats::coef(firth_model)
cat("\nNumber of coefficients (including intercept):", length(firth_coefs), "\n")

# Extract confidence intervals (profile likelihood)
cat("Calculating profile likelihood confidence intervals...\n")
firth_ci <- stats::confint(firth_model)

# Create Odds Ratios table
firth_or <- data.frame(
  Variable = names(firth_coefs)[-1],  # Exclude intercept
  Coefficient = firth_coefs[-1],
  OR = exp(firth_coefs[-1]),
  CI_Lower = exp(firth_ci[-1, 1]),
  CI_Upper = exp(firth_ci[-1, 2]),
  p_value = firth_model$prob[-1],
  stringsAsFactors = FALSE
)
rownames(firth_or) <- NULL

# Sort by p-value
firth_or <- firth_or[order(firth_or$p_value), ]

# Add significance stars
firth_or$Significance <- ifelse(firth_or$p_value < 0.001, "***",
                         ifelse(firth_or$p_value < 0.01, "**",
                         ifelse(firth_or$p_value < 0.05, "*",
                         ifelse(firth_or$p_value < 0.10, ".", ""))))

cat("\n=== TOP 15 PREDICTORS BY P-VALUE ===\n")
print(head(firth_or[, c("Variable", "OR", "CI_Lower", "CI_Upper", "p_value", "Significance")], 15))

# CRITICAL VERIFICATION: Check severity OR
severity_vars <- firth_or[grepl("severidad", firth_or$Variable, ignore.case = TRUE), ]
if (nrow(severity_vars) > 0) {
  cat("\n=== CRITICAL CHECK: SEVERITY OR ===\n")
  print(severity_vars[, c("Variable", "OR", "CI_Lower", "CI_Upper", "p_value")])

  max_or <- max(severity_vars$OR)
  if (max_or > 1e6) {
    cat("FAILURE: Severity OR still extremely large (", max_or, ")!\n")
    cat("         Firth penalization may not be sufficient.\n")
  } else if (max_or > 100) {
    cat("WARNING: Severity OR > 100. May still indicate separation issues.\n")
  } else {
    cat("OK: Severity OR appears clinically plausible (OR <= 100).\n")
  }
}

# Save OR table
utils::write.csv(firth_or, "results/Table_OddsRatios_Firth.csv", row.names = FALSE)
cat("\nSaved: results/Table_OddsRatios_Firth.csv\n")

# Save model object
saveRDS(firth_model, "model_firth.rds")
cat("Saved: model_firth.rds\n")

# ==============================================================================
# SECTION 5: PREDICTIONS ON TEST SET
# ==============================================================================

cat("\n--- SECTION 5: Predictions on Test Set ---\n")

# Prepare test data for prediction
test_baked_firth <- test_baked
test_baked_firth$desenlace <- factor(test_baked_firth$desenlace,
                                      levels = c("Vivo", "Fallecido"))

# logistf predict gives LINEAR PREDICTOR by default
# MUST convert to probability using plogis()
firth_lp <- predict(firth_model, newdata = test_baked_firth)
firth_probs <- stats::plogis(firth_lp)

# CRITICAL VERIFICATION: Probabilities must be on [0, 1]
cat("Prediction range: [", round(min(firth_probs), 4), ", ",
    round(max(firth_probs), 4), "]\n", sep = "")

if (any(firth_probs < 0) | any(firth_probs > 1)) {
  stop("CRITICAL ERROR: Predictions outside [0, 1] range!")
}
stopifnot(all(firth_probs >= 0 & firth_probs <= 1))
cat("VERIFIED: All predictions on probability scale [0, 1].\n")

# Save predictions
preds_firth <- data.frame(
  actual = test_baked_firth$desenlace,
  probability = firth_probs,
  linear_predictor = firth_lp
)
saveRDS(preds_firth, "preds_firth.rds")
cat("Saved: preds_firth.rds\n")

# ==============================================================================
# SECTION 6: THRESHOLD OPTIMIZATION — PROBABILITY SCALE
# ==============================================================================

cat("\n--- SECTION 6: Threshold Optimization (Probability Scale) ---\n")

# Create ROC object
# Direction "<" means: lower predictor values = "Vivo", higher = "Fallecido"
roc_firth <- pROC::roc(
  response = test_baked_firth$desenlace,
  predictor = firth_probs,
  levels = c("Vivo", "Fallecido"),
  direction = "<",
  quiet = TRUE
)

cat("AUC:", round(pROC::auc(roc_firth), 4), "\n")

# Youden threshold (PROBABILITY SCALE)
youden_coords <- pROC::coords(
  roc_firth,
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

# Also compute sensitivity >= 90% threshold
sens90_coords <- pROC::coords(
  roc_firth,
  x = 0.90,
  input = "sensitivity",
  ret = c("threshold", "sensitivity", "specificity"),
  transpose = FALSE
)

cat("\nSensitivity >= 90% threshold:", round(sens90_coords$threshold[1], 4), "\n")
cat("Actual sensitivity:", round(sens90_coords$sensitivity[1], 4), "\n")
cat("Specificity:", round(sens90_coords$specificity[1], 4), "\n")

# Save ROC object
saveRDS(roc_firth, "roc_firth.rds")
cat("\nSaved: roc_firth.rds\n")

# ==============================================================================
# SECTION 7: CLASSIFICATION METRICS AT YOUDEN THRESHOLD
# ==============================================================================

cat("\n--- SECTION 7: Classification Metrics ---\n")

# Apply threshold
predicted_class <- ifelse(firth_probs >= youden_threshold, "Fallecido", "Vivo")
predicted_class <- factor(predicted_class, levels = c("Fallecido", "Vivo"))

# Confusion matrix
actual_class <- test_baked_firth$desenlace
cm <- table(Predicted = predicted_class, Actual = actual_class)

cat("\nConfusion Matrix:\n")
print(cm)

# CRITICAL VERIFICATION: Both classes must be predicted
if (any(rowSums(cm) == 0)) {
  cat("\nWARNING: Not all predicted classes used!\n")
  cat("Row sums:", rowSums(cm), "\n")
} else {
  cat("\nVERIFIED: Both predicted classes used.\n")
}

# Calculate metrics
TP <- cm["Fallecido", "Fallecido"]
TN <- cm["Vivo", "Vivo"]
FP <- cm["Fallecido", "Vivo"]
FN <- cm["Vivo", "Fallecido"]

sensitivity <- TP / (TP + FN)
specificity <- TN / (TN + FP)
ppv <- TP / (TP + FP)
npv <- TN / (TN + FN)
accuracy <- (TP + TN) / sum(cm)

# Kappa
observed_agreement <- accuracy
expected_agreement <- ((TP + FP) * (TP + FN) + (TN + FN) * (TN + FP)) / sum(cm)^2
kappa <- (observed_agreement - expected_agreement) / (1 - expected_agreement)

# Brier Score
actual_binary <- as.numeric(actual_class == "Fallecido")
brier_score <- mean((firth_probs - actual_binary)^2)

# AUC with bootstrap CI
cat("\nCalculating bootstrap 95% CI for AUC (2000 iterations)...\n")
auc_ci <- pROC::ci.auc(roc_firth, method = "bootstrap", boot.n = 2000,
                       progress = "none", parallel = FALSE)

# PR-AUC
pr_obj <- PRROC::pr.curve(
  scores.class0 = firth_probs[actual_class == "Fallecido"],
  scores.class1 = firth_probs[actual_class == "Vivo"],
  curve = FALSE
)
pr_auc <- pr_obj$auc.integral

# Compile metrics
metrics_df <- data.frame(
  Metric = c("AUC", "AUC_Lower", "AUC_Upper",
             "PR_AUC", "Brier_Score",
             "Threshold", "Sensitivity", "Specificity",
             "PPV", "NPV", "Accuracy", "Kappa"),
  Value = c(
    round(pROC::auc(roc_firth), 4),
    round(auc_ci[1], 4),
    round(auc_ci[3], 4),
    round(pr_auc, 4),
    round(brier_score, 4),
    round(youden_threshold, 4),
    round(sensitivity, 4),
    round(specificity, 4),
    round(ppv, 4),
    round(npv, 4),
    round(accuracy, 4),
    round(kappa, 4)
  ),
  stringsAsFactors = FALSE
)

cat("\n=== PERFORMANCE METRICS ===\n")
print(metrics_df)

# Verify NPV is not NaN
if (is.nan(npv)) {
  cat("\nWARNING: NPV is NaN! This indicates no true negatives.\n")
} else {
  cat("\nVERIFIED: NPV is not NaN.\n")
}

# Save metrics
utils::write.csv(metrics_df, "results/Table_Firth_Metrics.csv", row.names = FALSE)
cat("Saved: results/Table_Firth_Metrics.csv\n")

# ==============================================================================
# SECTION 8: CALIBRATION ASSESSMENT
# ==============================================================================

cat("\n--- SECTION 8: Calibration Assessment ---\n")

# Calibration model: logit(observed) = alpha + beta * logit(predicted)
# Need to handle edge cases where predicted = 0 or 1
firth_probs_cal <- pmax(pmin(firth_probs, 1 - 1e-10), 1e-10)

cal_model <- stats::glm(
  actual_binary ~ stats::qlogis(firth_probs_cal),
  family = stats::binomial()
)

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
  Metric = c("Intercept", "Slope"),
  Value = c(round(cal_intercept, 4), round(cal_slope, 4)),
  Ideal = c(0, 1),
  Interpretation = c(
    ifelse(abs(cal_intercept) < 0.5, "Good", "Poor"),
    ifelse(cal_slope > 0.8 & cal_slope < 1.2, "Good", "Poor")
  )
)
utils::write.csv(cal_df, "results/Table_Calibration_Firth.csv", row.names = FALSE)
cat("Saved: results/Table_Calibration_Firth.csv\n")

# ==============================================================================
# SECTION 9: HOSMER-LEMESHOW TEST
# ==============================================================================

cat("\n--- SECTION 9: Hosmer-Lemeshow Goodness-of-Fit Test ---\n")

# Try with g = 10 groups first
hl_test <- tryCatch({
  ResourceSelection::hoslem.test(
    x = actual_binary,
    y = firth_probs,
    g = 10
  )
}, error = function(e) {
  cat("WARNING: H-L test with g=10 failed. Trying g=8...\n")
  tryCatch({
    ResourceSelection::hoslem.test(x = actual_binary, y = firth_probs, g = 8)
  }, error = function(e2) {
    cat("WARNING: H-L test with g=8 failed. Trying g=5...\n")
    tryCatch({
      ResourceSelection::hoslem.test(x = actual_binary, y = firth_probs, g = 5)
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
      "Good fit (fail to reject H0)", "Poor fit (reject H0)"), "\n")

  # VERIFY: H-L p-value is not NaN
  if (is.nan(hl_test$p.value)) {
    cat("WARNING: H-L p-value is NaN!\n")
  } else {
    cat("VERIFIED: H-L p-value is not NaN.\n")
  }

  # Save
  hl_df <- data.frame(
    Statistic = c("Chi_Square", "df", "p_value"),
    Value = c(round(hl_test$statistic, 4), hl_test$parameter, round(hl_test$p.value, 4))
  )
  utils::write.csv(hl_df, "results/Table_HosmerLemeshow_Firth.csv", row.names = FALSE)
  cat("Saved: results/Table_HosmerLemeshow_Firth.csv\n")
} else {
  cat("Hosmer-Lemeshow test could not be computed.\n")
}

# ==============================================================================
# SECTION 10: DELONG COMPARISON VS ML MODELS
# ==============================================================================

cat("\n--- SECTION 10: DeLong Comparison vs Other Models ---\n")

# Try to load existing ROC objects from multi-model comparison
roc_files <- c(
  "roc_logreg.rds",           # Original LogReg
  "roc_rf.rds",               # Random Forest
  "roc_xgb.rds",              # XGBoost
  "roc_list_multimodel.rds"   # Combined list
)

delong_results <- data.frame(
  Comparison = character(),
  AUC_Firth = numeric(),
  AUC_Other = numeric(),
  Delta_AUC = numeric(),
  DeLong_Z = numeric(),
  DeLong_P = numeric(),
  stringsAsFactors = FALSE
)

for (roc_file in roc_files) {
  if (file.exists(roc_file)) {
    cat("\nLoading:", roc_file, "\n")
    roc_other <- readRDS(roc_file)

    if (inherits(roc_other, "roc")) {
      # Single ROC object
      model_name <- gsub("roc_|\\.rds", "", roc_file)
      tryCatch({
        delong <- pROC::roc.test(roc_firth, roc_other, method = "delong")
        delong_results <- rbind(delong_results, data.frame(
          Comparison = paste0("Firth vs ", model_name),
          AUC_Firth = round(pROC::auc(roc_firth), 4),
          AUC_Other = round(pROC::auc(roc_other), 4),
          Delta_AUC = round(pROC::auc(roc_firth) - pROC::auc(roc_other), 4),
          DeLong_Z = round(delong$statistic, 4),
          DeLong_P = round(delong$p.value, 4),
          stringsAsFactors = FALSE
        ))
        cat("  Firth vs", model_name, ": Delta AUC =",
            round(pROC::auc(roc_firth) - pROC::auc(roc_other), 4),
            ", p =", round(delong$p.value, 4), "\n")
      }, error = function(e) {
        cat("  Error comparing to", model_name, ":", e$message, "\n")
      })
    } else if (is.list(roc_other)) {
      # List of ROC objects
      for (model_name in names(roc_other)) {
        tryCatch({
          delong <- pROC::roc.test(roc_firth, roc_other[[model_name]], method = "delong")
          delong_results <- rbind(delong_results, data.frame(
            Comparison = paste0("Firth vs ", model_name),
            AUC_Firth = round(pROC::auc(roc_firth), 4),
            AUC_Other = round(pROC::auc(roc_other[[model_name]]), 4),
            Delta_AUC = round(pROC::auc(roc_firth) - pROC::auc(roc_other[[model_name]]), 4),
            DeLong_Z = round(delong$statistic, 4),
            DeLong_P = round(delong$p.value, 4),
            stringsAsFactors = FALSE
          ))
          cat("  Firth vs", model_name, ": Delta AUC =",
              round(pROC::auc(roc_firth) - pROC::auc(roc_other[[model_name]]), 4),
              ", p =", round(delong$p.value, 4), "\n")
        }, error = function(e) {
          cat("  Error comparing to", model_name, ":", e$message, "\n")
        })
      }
    }
  }
}

if (nrow(delong_results) > 0) {
  cat("\n=== DELONG COMPARISON SUMMARY ===\n")
  print(delong_results)
  utils::write.csv(delong_results, "results/Table_DeLong_Firth.csv", row.names = FALSE)
  cat("Saved: results/Table_DeLong_Firth.csv\n")
} else {
  cat("No ROC objects found for comparison.\n")
}

# ==============================================================================
# SECTION 11: SUPPLEMENTARY — RIDGE REGRESSION COMPARISON
# ==============================================================================

cat("\n--- SECTION 11: Ridge Regression Comparison ---\n")

# Prepare matrices for glmnet
x_train <- as.matrix(train_baked[, -which(names(train_baked) == "desenlace")])
y_train <- as.numeric(train_baked$desenlace == "Fallecido")
x_test <- as.matrix(test_baked[, -which(names(test_baked) == "desenlace")])

cat("Fitting Ridge regression (alpha = 0)...\n")
set.seed(2026)

ridge_cv <- glmnet::cv.glmnet(
  x = x_train,
  y = y_train,
  family = "binomial",
  alpha = 0,  # Ridge
  nfolds = 5,
  type.measure = "auc"
)

cat("Optimal lambda (min):", round(ridge_cv$lambda.min, 6), "\n")
cat("Optimal lambda (1se):", round(ridge_cv$lambda.1se, 6), "\n")
cat("CV AUC at lambda.min:", round(max(ridge_cv$cvm), 4), "\n")

# Predictions at lambda.min
ridge_probs <- predict(ridge_cv, newx = x_test, s = "lambda.min", type = "response")[, 1]

# Ridge ROC
roc_ridge <- pROC::roc(
  response = test_baked$desenlace,
  predictor = ridge_probs,
  levels = c("Vivo", "Fallecido"),
  direction = "<",
  quiet = TRUE
)

cat("Ridge test AUC:", round(pROC::auc(roc_ridge), 4), "\n")

# Non-zero coefficients (Ridge should keep all)
ridge_coefs <- stats::coef(ridge_cv, s = "lambda.min")
n_nonzero <- sum(ridge_coefs[-1, 1] != 0)
cat("Non-zero coefficients:", n_nonzero, "of", length(ridge_coefs) - 1, "\n")

# Compare Firth vs Ridge
delong_vs_ridge <- pROC::roc.test(roc_firth, roc_ridge, method = "delong")
cat("\nFirth vs Ridge: Delta AUC =",
    round(pROC::auc(roc_firth) - pROC::auc(roc_ridge), 4),
    ", p =", round(delong_vs_ridge$p.value, 4), "\n")

# Save Ridge ROC
saveRDS(roc_ridge, "roc_ridge.rds")
cat("Saved: roc_ridge.rds\n")

# ==============================================================================
# SECTION 12: PUBLICATION-QUALITY OR TABLE
# ==============================================================================

cat("\n--- SECTION 12: Publication-Quality OR Table ---\n")

# Create gtsummary-compatible model using the Firth results
# Since gtsummary doesn't directly support logistf, we create a custom table

# Format OR with CI
firth_or$OR_CI <- paste0(
  round(firth_or$OR, 2), " (",
  round(firth_or$CI_Lower, 2), "-",
  round(firth_or$CI_Upper, 2), ")"
)

firth_or$p_formatted <- ifelse(
  firth_or$p_value < 0.001, "<0.001",
  round(firth_or$p_value, 3)
)

# Select columns for publication
firth_or_pub <- firth_or[, c("Variable", "OR_CI", "p_formatted", "Significance")]
names(firth_or_pub) <- c("Predictor", "OR (95% CI)", "P-value", "Sig.")

# Save as CSV
utils::write.csv(firth_or_pub, "results/Table_OddsRatios_Firth_Publication.csv",
                 row.names = FALSE)
cat("Saved: results/Table_OddsRatios_Firth_Publication.csv\n")

# Create HTML version using gt if available
tryCatch({
  if (requireNamespace("gt", quietly = TRUE)) {
    gt_table <- gt::gt(firth_or_pub) %>%
      gt::tab_header(
        title = "Odds Ratios from Firth's Penalized Logistic Regression",
        subtitle = "COVID-19 Mortality Prediction"
      ) %>%
      gt::tab_footnote(
        footnote = "Profile likelihood 95% CI. *** p<0.001, ** p<0.01, * p<0.05, . p<0.10"
      )
    gt::gtsave(gt_table, "results/Table_OddsRatios_Firth_Publication.html")
    cat("Saved: results/Table_OddsRatios_Firth_Publication.html\n")
  }
}, error = function(e) {
  cat("Note: gt table creation skipped:", e$message, "\n")
})

# ==============================================================================
# SECTION 13: FINAL VERIFICATION CHECKLIST
# ==============================================================================

cat("\n")
cat("===============================================================================\n")
cat("=== GOLD-STANDARD LOGREG v2: VERIFICATION CHECKLIST ===\n")
cat("===============================================================================\n")

# Check 1: Separation handling
cat("\n1. Separation handling: Firth penalization [YES]\n")

# Check 2: OR for severity
severity_or <- firth_or[grepl("severidad", firth_or$Variable, ignore.case = TRUE), ]
if (nrow(severity_or) > 0) {
  max_sev_or <- max(severity_or$OR)
  cat("2. OR for severity: ", round(max_sev_or, 2))
  if (max_sev_or < 1000) {
    cat(" [FINITE AND PLAUSIBLE]\n")
  } else {
    cat(" [WARNING: VERY LARGE]\n")
  }
} else {
  cat("2. OR for severity: N/A (no severity variables found)\n")
}

# Check 3: Threshold scale
cat("3. Threshold scale: ", round(youden_threshold, 4))
if (youden_threshold >= 0 & youden_threshold <= 1) {
  cat(" [PROBABILITY SCALE OK]\n")
} else {
  cat(" [ERROR: NOT PROBABILITY SCALE]\n")
}

# Check 4: Confusion matrix
cat("4. Confusion matrix: ")
if (all(rowSums(cm) > 0)) {
  cat("Both classes predicted [OK]\n")
} else {
  cat("[WARNING: Not all classes predicted]\n")
}

# Check 5: Specificity > 0
cat("5. Specificity > 0: ", round(specificity, 4))
if (specificity > 0) {
  cat(" [OK]\n")
} else {
  cat(" [FAILED]\n")
}

# Check 6: NPV not NaN
cat("6. NPV not NaN: ", round(npv, 4))
if (!is.nan(npv)) {
  cat(" [OK]\n")
} else {
  cat(" [FAILED]\n")
}

# Check 7: Hosmer-Lemeshow not NaN
if (!is.null(hl_test) && !is.nan(hl_test$p.value)) {
  cat("7. Hosmer-Lemeshow: p = ", round(hl_test$p.value, 4), " [OK]\n")
} else {
  cat("7. Hosmer-Lemeshow: [COULD NOT COMPUTE]\n")
}

# Check 8: EPV after Firth
cat("8. EPV after Firth: N/A (Firth does not require variable selection)\n")

# Check 9: AUC comparison
cat("9. Firth AUC: ", round(pROC::auc(roc_firth), 4), "\n")

cat("\n")
cat("===============================================================================\n")
cat("GOLD-STANDARD LOGISTIC REGRESSION v2 COMPLETE\n")
cat("===============================================================================\n")
cat("\nOutputs saved to results/ directory:\n")
cat("  - Table_EPV_Analysis.csv\n")
cat("  - Table_GVIF_Analysis.csv\n")
cat("  - Table_Linearity_Tests.csv\n")
cat("  - Table_OddsRatios_Firth.csv\n")
cat("  - Table_OddsRatios_Firth_Publication.csv\n")
cat("  - Table_Firth_Metrics.csv\n")
cat("  - Table_Calibration_Firth.csv\n")
cat("  - Table_HosmerLemeshow_Firth.csv\n")
cat("  - Table_DeLong_Firth.csv (if other models exist)\n")
cat("\nModel artifacts saved to root:\n")
cat("  - model_firth.rds\n")
cat("  - roc_firth.rds\n")
cat("  - preds_firth.rds\n")
cat("  - roc_ridge.rds\n")
cat("\n")
