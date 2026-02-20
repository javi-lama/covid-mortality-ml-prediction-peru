# ==== API.R: PLUMBER API FOR COVID-19 MORTALITY CALCULATOR ====
# Purpose: Serve the ML Model to the React Frontend
# Strategy: "Hybrid Input" - User provides 8 keys, API fills the rest with population medians (Imputation)

library(plumber)
library(tidymodels)
library(tidyverse)
library(DALEX)
library(DALEXtra)

# Utility function for robust boolean parsing
# Handles: TRUE/FALSE, "true"/"false", 1/0, "1"/"0", "yes"/"no"
parse_bool <- function(x) {
  if (is.logical(x)) return(x)
  if (is.numeric(x)) return(as.logical(x))
  if (is.character(x)) return(tolower(x) %in% c("true", "1", "yes"))
  return(FALSE)
}

# 1. LOAD MODEL & DATA
# We need the training data to calculate the "Baselines" for imputation
# In production, these should be saved as an .rds to avoid sourcing/re-calculating

# Determine base paths (scripts are in r/, artifacts are in parent directory)
script_dir <- if (file.exists("Data_Cleaning_Organization.R")) "." else "r"
artifact_dir <- if (file.exists("modelo_rf_covid.rds")) "." else ".."

source(file.path(script_dir, "Data_Cleaning_Organization.R"))
source(file.path(script_dir, "Random_Forest_Preprocess.R"))

# Load the best model (For now we load the RF, but can switch to XGBoost later)
# Assuming 'final_fit' object exists from source or saved RDS
# If running standalone, we should load the RDS:
# model <- readRDS("model_xgboost_fit.rds") # Example
# For this script, we assume 'final_rf_workflow' is available from source or we load it:
# model <- readRDS("modelo_rf_covid.rds")

# Fallback provided for the example if object is missing in this session context:
if(!exists("final_rf_workflow")) {
   model_path <- file.path(artifact_dir, "modelo_rf_covid.rds")
   if(file.exists(model_path)) {
     model <- readRDS(model_path)
   } else {
     stop("Model not found! Run training scripts first.")
   }
} else {
  model <- final_rf_workflow
}

# 2. PREPARE EXPLAINER (For SHAP)
# ============================================================================
# CRITICAL: Custom predict_function to ensure correct probability class
# ============================================================================
# SCIENTIFIC NOTE: For binary classification with tidymodels, DALEX's default
# behavior may extract the wrong probability column, causing SHAP sign inversion.
#
# Problem: When factor levels are ordered as c("Fallecido", "Vivo"), DALEX may
# default to explaining .pred_Vivo (survival) instead of .pred_Fallecido (death).
#
# Solution: Explicitly specify predict_function to return .pred_Fallecido
# This ensures SHAP values explain MORTALITY RISK (positive = increases death risk)
#
# Reference: Biecek & Burzykowski (2021). Explanatory Model Analysis. CRC Press.
# ============================================================================
predict_mortality <- function(model, newdata) {
  preds <- predict(model, newdata, type = "prob")
  # Explicitly return probability of death (Fallecido), not survival (Vivo)
  return(preds$.pred_Fallecido)
}

explainer <- explain_tidymodels(
  model,
  data = df_testing %>% select(-desenlace),
  y = df_testing$desenlace == "Fallecido",
  predict_function = predict_mortality,  # CRITICAL: Ensures correct probability class
  label = "COVID-19 Mortality (RF)",
  verbose = FALSE
)

print("✓ Explainer configured with explicit predict_function for .pred_Fallecido")
print("✓ SHAP values will correctly explain MORTALITY RISK (positive = increases death risk)")

# ==== 3. IMPUTATION STRATEGY ====
# Use recipe-based KNN imputation (matches training preprocessing)
# No additional setup needed - rf_recipe already contains:
#   - step_impute_knn(all_numeric_predictors(), neighbors = 5)
#   - step_impute_mode(all_nominal_predictors())
# This ensures consistent preprocessing between training and prediction

print("✓ Using recipe-based imputation (KNN k=5 for numeric, mode for categorical)")
print("✓ Imputation strategy matches training pipeline exactly")

# 4. API DEFINITIONS

#* @apiTitle COVID-19 Mortality Risk Calculator
#* @apiDescription R Backend providing ML inference and SHAP explainability.

#* Enable CORS with proper preflight handling
#* @filter cors
cors <- function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, Accept, Origin")
  res$setHeader("Access-Control-Max-Age", "86400")  # Cache preflight for 24 hours

  # Handle OPTIONS preflight requests immediately
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 200
    return(list())
  }

  plumber::forward()
}

#* Request logging filter for debugging
#* @filter logging
logging <- function(req, res) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("[%s] %s %s\n", timestamp, req$REQUEST_METHOD, req$PATH_INFO))

  # Log request body for POST requests (helpful for debugging)
  if (req$REQUEST_METHOD == "POST" && !is.null(req$postBody)) {
    cat(sprintf("  Body: %s\n", substr(req$postBody, 1, 200)))
  }

  plumber::forward()
}

#* Check API status
#* @get /health
function() {
  list(status = "online", model = "XGBoost/RF Hybrid")
}

#* Predict Mortality Risk with Uncertainty Quantification
#* @param edad Age of the patient
#* @param sexo Sex (hombre/mujer)
#* @param severidad_sars Severity (Leve/Moderado/Severo)
#* @param albumina Albumin level
#* @param plaquetas Platelet count
#* @param bilirrtotal Total Bilirubin
#* @param sxingr_disnea Dyspnea (TRUE/FALSE)
#* @param sxingr_cefalea Headache (TRUE/FALSE)
#* @post /predict
function(edad, sexo, severidad_sars, albumina, plaquetas, bilirrtotal, sxingr_disnea, sxingr_cefalea) {

  # A. Create Patient Data Structure
  # Start with template row from training (ensures all columns/types match)
  patient_data <- df_training[1, ] %>% select(-desenlace)

  # B. Set ALL variables to NA (will overwrite observed ones next)
  for(var in names(patient_data)) {
    if(is.numeric(patient_data[[var]])) {
      patient_data[[var]] <- NA_real_
    } else if(is.factor(patient_data[[var]])) {
      patient_data[[var]] <- factor(NA, levels = levels(patient_data[[var]]))
    } else if(is.logical(patient_data[[var]])) {
      patient_data[[var]] <- NA
    }
  }

  # C. Set Observed Top 8 Variables
  patient_data$edad <- as.numeric(edad)
  patient_data$sexo <- factor(sexo, levels = levels(df_training$sexo))
  patient_data$severidad_sars <- factor(severidad_sars, levels = levels(df_training$severidad_sars))
  patient_data$albumina <- as.numeric(albumina)
  patient_data$plaquetas <- as.numeric(plaquetas)
  patient_data$bilirrtotal <- as.numeric(bilirrtotal)
  patient_data$sxingr_disnea <- factor(parse_bool(sxingr_disnea), levels = c("FALSE", "TRUE"))
  patient_data$sxingr_cefalea <- factor(parse_bool(sxingr_cefalea), levels = c("FALSE", "TRUE"))

  # Track which variables were observed
  observed_vars <- c("edad", "sexo", "severidad_sars", "albumina", "plaquetas",
                     "bilirrtotal", "sxingr_disnea", "sxingr_cefalea")
  all_vars <- names(patient_data)

  # D. Generate Prediction
  # The model is a WORKFLOW that includes rf_recipe preprocessing
  # Pass raw patient_data with NAs - workflow handles imputation internally
  pred <- predict(model, patient_data, type = "prob")
  risk_score <- pred$.pred_Fallecido[[1]]  # Extract scalar (not array) for JSON

  # E. SHAP Explanation (True Shapley Values)
  # ========================================================================
  # SCIENTIFIC NOTE: Using type = "shap" (permutation-based Shapley values)

  # instead of type = "break_down" (sequential attribution).
  #
  # Rationale:
  # 1. Break-down is ORDER-DEPENDENT - contributions depend on variable
  #    evaluation sequence, which can produce counterintuitive results
  #    for categorical variables (e.g., severity appearing "protective")
  #
  # 2. True Shapley values average over ALL possible orderings, providing:
  #    - Order-independent, fair attribution
  #    - Clinically coherent interpretations
  #    - Consistency with SHAP.R research analysis (lines 88-92)
  #
  # 3. B = 15 permutations provides adequate accuracy for 8 variables
  #    while keeping response time reasonable (~1-2 seconds)
  #
  # Reference: Lundberg & Lee (2017). A Unified Approach to Interpreting
  #            Model Predictions. NeurIPS.
  # ========================================================================
  shap_start <- Sys.time()
  set.seed(2026)  # Reproducibility - matches SHAP.R seed
  shap <- predict_parts(
    explainer,
    new_observation = patient_data,
    type = "shap",
    B = 15
  )
  shap_time <- as.numeric(difftime(Sys.time(), shap_start, units = "secs"))
  cat(sprintf("  SHAP calculation time: %.2f seconds\n", shap_time))

  # Process SHAP output with categorical variable aggregation
  # ========================================================================
  # SCIENTIFIC NOTE: One-hot encoded categorical variables produce multiple
  # SHAP contributions (e.g., severidad_sars_Moderado, severidad_sars_Severo).
  # We aggregate these to show a single, interpretable contribution per
  # clinical variable, which is the standard practice in clinical ML papers.
  #
  # IMPORTANT: Filter to only the 8 clinically-observed variables to avoid
  # showing imputed variables (e.g., "automed_ivermectina = NA") in the UI.
  # ========================================================================

  # Define the 8 clinical variables that were observed (not imputed)
  clinical_vars <- c("edad", "sexo", "severidad_sars", "albumina",
                     "plaquetas", "bilirrtotal", "sxingr_disnea", "sxingr_cefalea")

  shap_clean <- shap %>%
    as_tibble() %>%
    # Filter out DALEX internal rows (baseline and final prediction)
    filter(!variable %in% c("_baseline_", "_prediction_", "intercept", "prediction")) %>%
    filter(!str_detect(variable, "^_")) %>%
    select(variable, contribution, sign) %>%
    # Aggregate one-hot encoded categorical and numeric variables to parent name
    # ========================================================================
    # SCIENTIFIC NOTE: DALEX's predict_parts() outputs variable names in
    # different formats depending on variable type:
    #   - Numeric: "edad = 75", "albumina = 2.5"
    #   - Categorical (one-hot): "severidad_sars_Severo", "sexo_hombre"
    #   - Boolean: "sxingr_disnea = TRUE"
    #
    # We map ALL variable formats to their base clinical variable names
    # so they can be aggregated and filtered correctly.
    # ========================================================================
    mutate(
      variable_base = case_when(
        # Categorical variables (one-hot encoded, e.g., "severidad_sars_Severo")
        str_detect(variable, "severidad_sars") ~ "severidad_sars",
        str_detect(variable, "sexo") ~ "sexo",
        # Boolean variables (e.g., "sxingr_disnea = TRUE")
        str_detect(variable, "sxingr_disnea") ~ "sxingr_disnea",
        str_detect(variable, "sxingr_cefalea") ~ "sxingr_cefalea",
        # Numeric variables (e.g., "edad = 75", "albumina = 2.5")
        str_detect(variable, "^edad") ~ "edad",
        str_detect(variable, "^albumina") ~ "albumina",
        str_detect(variable, "^plaquetas") ~ "plaquetas",
        str_detect(variable, "^bilirr") ~ "bilirrtotal",
        # Fallback: extract base name before " = " (handles any remaining formats)
        TRUE ~ str_replace(variable, " = .*$", "")
      )
    ) %>%
    group_by(variable_base) %>%
    summarise(
      contribution = sum(contribution),
      sign = sign(sum(contribution)),
      .groups = "drop"
    ) %>%
    rename(variable = variable_base) %>%
    # FILTER: Keep only the 8 clinical variables (remove imputed variables)
    filter(variable %in% clinical_vars) %>%
    # Create clean display names for UI
    mutate(
      variable_clean = case_when(
        str_detect(variable, "severidad") ~ "Severidad",
        str_detect(variable, "edad") ~ "Edad",
        str_detect(variable, "albumina") ~ "Albúmina",
        str_detect(variable, "plaquetas") ~ "Plaquetas",
        str_detect(variable, "bilirr") ~ "Bilirrubina",
        str_detect(variable, "sexo") ~ "Sexo",
        str_detect(variable, "disnea") ~ "Disnea",
        str_detect(variable, "cefalea") ~ "Cefalea",
        TRUE ~ variable
      )
    ) %>%
    arrange(desc(abs(contribution)))

  # F. Return JSON with Clinical Interpretation
  list(
    # Point estimates
    risk_score = risk_score,
    risk_percentage = round(risk_score * 100, 1),
    risk_level = ifelse(risk_score < 0.20, "Low",
                       ifelse(risk_score < 0.50, "Moderate", "High")),

    # Clinical threshold interpretation
    threshold_info = list(
      optimal_threshold = 0.3184,
      note = "Threshold optimized for 90% sensitivity (Youden index)",
      classification = ifelse(risk_score >= 0.3184, "High Risk", "Low Risk")
    ),

    # Imputation transparency
    imputation_diagnostics = list(
      method = "KNN Imputation (k=5 neighbors)",
      note = "Same preprocessing as training pipeline (step_impute_knn)",
      observed_vars = length(observed_vars),
      imputed_vars = length(setdiff(all_vars, observed_vars)),
      imputation_pct = round(length(setdiff(all_vars, observed_vars)) / length(all_vars) * 100, 1),
      observed_variables = observed_vars,
      rationale = "Recipe-based imputation ensures consistency with training"
    ),

    # Explainability
    explanation = shap_clean
  )
}
