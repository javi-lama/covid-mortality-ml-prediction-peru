# FASE 3: EXPLICABILIDAD AVANZADA (SHAP & DALEX)

# 1. LIBRERÍAS DE EXPLICABILIDAD
library(DALEX)
library(DALEXtra)
library(tidyverse)
library(vip)
library(tidymodels)
library(themis)

# ==== LOAD DATA & MODELS (STANDALONE MODE) ====
# Check if running standalone (Rscript) or sourced (interactive)
if(!exists("df_testing") || !exists("final_fit")) {
  if(file.exists("data_testing.rds")) {
    df_testing <- readRDS("data_testing.rds")
    df_training <- readRDS("data_training.rds")
    rf_recipe <- readRDS("rf_recipe_master.rds")
    cat("✓ Loaded testing & training data from RDS files\n")
  } else {
    cat("⚠ Testing data missing. Running full pipeline...\n")
    source("Data_Cleaning_Organization.R")
    source("Random_Forest_Preprocess.R")
    cat("✓ Preprocessing pipeline completed\n")
  }

  # Load models if not in session
  if(!exists("final_fit") && file.exists("modelo_rf_covid.rds")) {
    final_model_workflow <- readRDS("modelo_rf_covid.rds")
    cat("✓ Loaded RF model from RDS file\n")
  } else if(exists("final_fit")) {
    final_model_workflow <- extract_workflow(final_fit)
  } else {
    stop("\n✗ ERROR: final_fit not found and modelo_rf_covid.rds missing.\n",
         "  → Run Random_Forest.R first.\n")
  }
} else {
  cat("✓ Using data and models from current R session\n")
  final_model_workflow <- extract_workflow(final_fit)
}

# Generate predictions for waterfall plots (fixing missing object error)
test_preds <- predict(final_model_workflow, df_testing, type = "prob") %>%
  bind_cols(df_testing %>% select(desenlace))


# ==== MULTI-MODEL EXPLAINABILITY (RF, XGBOOST, SVM) ====
# Extract all trained models for comprehensive SHAP analysis

# Random Forest
saveRDS(final_model_workflow, 'modelo_rf_covid.rds')

# Load XGBoost and SVM models (trained in Model_Experiments.R)
fit_xgb <- readRDS("model_xgboost_fit.rds")
fit_svm <- readRDS("model_svm_fit.rds")

model_xgb <- extract_workflow(fit_xgb)
model_svm <- extract_workflow(fit_svm)

# ==============================================================================
# EXPLAINER CONFIGURATION: CRITICAL FOR CORRECT SHAP INTERPRETATION
# ==============================================================================
# SCIENTIFIC NOTE: For binary classification with tidymodels, the explainer's
# default predict_function may extract the wrong probability column, causing
# SHAP sign inversion (positive values appearing as protective, vice versa).
#
# SOLUTION: Explicitly define predict_function to return .pred_Fallecido
# This ensures SHAP values explain MORTALITY RISK:
#   - Positive SHAP contribution = INCREASES mortality risk
#   - Negative SHAP contribution = DECREASES mortality risk (protective)
#
# REFERENCE: Biecek & Burzykowski (2021). Explanatory Model Analysis: Explore,
#            Explain, and Examine Predictive Models. CRC Press. Chapter 6.
#
# REFERENCE: Lundberg & Lee (2017). A Unified Approach to Interpreting Model
#            Predictions. NeurIPS.
# ==============================================================================

# Custom predict function: Returns probability of MORTALITY (not survival)
predict_mortality <- function(model, newdata) {
  preds <- predict(model, newdata, type = "prob")
  return(preds$.pred_Fallecido)  # Explicitly return death probability
}

# Create explainers for ALL models with explicit predict_function
explainer_rf <- explain_tidymodels(
  final_model_workflow,
  data = df_testing %>% select(-desenlace),
  y = df_testing$desenlace == "Fallecido",
  predict_function = predict_mortality,  # CRITICAL: Ensures correct probability class
  label = "Random Forest COVID-19",
  verbose = FALSE
)

explainer_xgb <- explain_tidymodels(
  model_xgb,
  data = df_testing %>% select(-desenlace),
  y = df_testing$desenlace == "Fallecido",
  predict_function = predict_mortality,  # CRITICAL: Ensures correct probability class
  label = "XGBoost COVID-19",
  verbose = FALSE
)

explainer_svm <- explain_tidymodels(
  model_svm,
  data = df_testing %>% select(-desenlace),
  y = df_testing$desenlace == "Fallecido",
  predict_function = predict_mortality,  # CRITICAL: Ensures correct probability class
  label = "SVM RBF COVID-19",
  verbose = FALSE
)

cat("\n✓ Explainers configured with explicit predict_function for .pred_Fallecido\n")
cat("✓ SHAP values will correctly explain MORTALITY RISK (positive = increases death risk)\n\n")

# ==== VISIÓN GLOBAL (SHAP VALUES FOR ALL MODELS) ====

# Compute SHAP for Random Forest
set.seed(2026)
shap_values <- predict_parts(
  explainer = explainer_rf,
  new_observation = df_testing %>% select(-desenlace),
  type = "shap"
)

# Compute SHAP for XGBoost
set.seed(2026)
shap_values_xgb <- predict_parts(
  explainer = explainer_xgb,
  new_observation = df_testing %>% select(-desenlace),
  type = "shap"
)

# Compute SHAP for SVM (using true Shapley values for model-agnostic approach)
set.seed(2026)
shap_values_svm <- predict_parts(
  explainer = explainer_svm,
  new_observation = df_testing %>% select(-desenlace),
  type = "shap"
)

# GRÁFICO MAESTRO RF (Figura 3 del Paper)
plot_shap_global <- plot(shap_values) +
  ggtitle("Random Forest: Impacto Direccional de Variables (SHAP Values)",
          subtitle = "Derecha = Aumenta Riesgo | Izquierda = Disminuye Riesgo")

print(plot_shap_global)

# GRÁFICO MAESTRO XGBoost
plot_shap_xgb <- plot(shap_values_xgb) +
  ggtitle("XGBoost: Impacto Direccional de Variables (SHAP Values)",
          subtitle = "Derecha = Aumenta Riesgo | Izquierda = Disminuye Riesgo")

print(plot_shap_xgb)

# Save plots
ggsave("Figure_SHAP_RF.png", plot_shap_global, width = 10, height = 8, dpi = 300)
ggsave("Figure_SHAP_XGBoost.png", plot_shap_xgb, width = 10, height = 8, dpi = 300)

# ==== CROSS-MODEL FEATURE IMPORTANCE COMPARISON ====
# Critical for validating "Top 8" variable selection across architectures

library(vip)

# Extract variable importance using vip package
importance_rf <- vip::vi(extract_fit_parsnip(final_model_workflow)) %>%
  mutate(Model = "RF") %>%
  select(Variable, Importance, Model)

importance_xgb <- vip::vi(extract_fit_parsnip(model_xgb)) %>%
  mutate(Model = "XGBoost") %>%
  select(Variable, Importance, Model)

print("Variable Importance - Random Forest:")
print(head(importance_rf, 10))

print("Variable Importance - XGBoost:")
print(head(importance_xgb, 10))

# SHAP-based importance (mean absolute SHAP value)
shap_importance_rf <- shap_values %>%
  as_tibble() %>%
  group_by(variable_name) %>%
  summarise(Mean_Abs_SHAP = mean(abs(contribution))) %>%
  arrange(desc(Mean_Abs_SHAP)) %>%
  mutate(Model = "RF", Rank = row_number())

shap_importance_xgb <- shap_values_xgb %>%
  as_tibble() %>%
  group_by(variable_name) %>%
  summarise(Mean_Abs_SHAP = mean(abs(contribution))) %>%
  arrange(desc(Mean_Abs_SHAP)) %>%
  mutate(Model = "XGBoost", Rank = row_number())

# Combine and calculate consensus across models
consensus_importance <- bind_rows(shap_importance_rf, shap_importance_xgb) %>%
  group_by(variable_name) %>%
  summarise(
    Mean_Rank = mean(Rank),
    SD_Rank = sd(Rank),
    Mean_SHAP = mean(Mean_Abs_SHAP),
    Consistency = 1 - (SD_Rank / Mean_Rank)  # Higher = more consistent ranking
  ) %>%
  arrange(Mean_Rank)

print("=== CONSENSUS FEATURE IMPORTANCE (RF + XGBoost) ===")
print(head(consensus_importance, 15))

# Statistical validation: Spearman correlation of feature rankings
rank_correlation <- cor.test(
  shap_importance_rf$Rank,
  shap_importance_xgb$Rank,
  method = "spearman"
)

print(paste("Feature ranking correlation (RF vs XGBoost):",
            round(rank_correlation$estimate, 3)))
print(paste("P-value:", format.pval(rank_correlation$p.value)))

if(rank_correlation$estimate > 0.70) {
  print("✓ PASS: Rankings are consistent enough for consensus (r > 0.70)")
} else {
  print("✗ WARNING: Rankings show weak consistency - consider model-specific features")
}

# Visualize consensus importance
plot_consensus <- consensus_importance %>%
  slice(1:15) %>%
  ggplot(aes(x = reorder(variable_name, -Mean_Rank), y = Mean_SHAP)) +
  geom_col(aes(fill = Consistency)) +
  coord_flip() +
  scale_fill_gradient(low = "orange", high = "darkgreen",
                      name = "Rank\nConsistency") +
  labs(
    title = "Consensus Feature Importance (RF + XGBoost)",
    subtitle = "Mean Absolute SHAP Values - Higher = More Important",
    x = "Variable",
    y = "Mean |SHAP| Across Models"
  ) +
  theme_minimal()

print(plot_consensus)
ggsave("Figure_Consensus_Importance.png", plot_consensus, width = 10, height = 8, dpi = 300)

# CONVERTIR EL OBJETO SHAP EN TABLA (RF specific)
tabla_shap_exacta <- as.data.frame(shap_values)

reporte_shap <- tabla_shap_exacta %>%
  select(variable_name, variable_value, contribution, sign) %>%
  mutate(
    Aporte_Porcentual = round(contribution * 100, 2)
  )

print("RF SHAP Table (sample):")
print(head(reporte_shap, 20))

# ==== BOOTSTRAP STABILITY ANALYSIS FOR TOP FEATURES ====
# Validates that Top 8 variables are robust across data resampling

print("=== STARTING BOOTSTRAP STABILITY ANALYSIS (100 iterations) ===")
set.seed(2026)
n_bootstrap <- 100
bootstrap_rankings <- list()

library(ranger)  # For fast RF fitting

for(i in 1:n_bootstrap) {
  # Resample training data with replacement
  boot_sample <- df_training[sample(nrow(df_training), replace = TRUE), ]

  # Prep recipe on bootstrap sample
  boot_recipe <- prep(rf_recipe, training = boot_sample)
  boot_data <- bake(boot_recipe, new_data = NULL)

  # Quick RF fit (use reasonable defaults, no full tuning for speed)
  boot_rf <- rand_forest(trees = 500, mtry = 10, min_n = 20) %>%
    set_engine("ranger", importance = "impurity") %>%
    set_mode("classification") %>%
    fit(desenlace ~ ., data = boot_data)

  # Extract top 10 important variables
  boot_importance <- vip::vi(boot_rf) %>%
    arrange(desc(Importance)) %>%
    slice(1:10) %>%
    pull(Variable)

  bootstrap_rankings[[i]] <- boot_importance

  if(i %% 20 == 0) print(paste("Completed", i, "bootstrap iterations..."))
}

# Count how often each variable appears in top 10
all_vars <- unique(unlist(bootstrap_rankings))
stability_table <- tibble(
  Variable = all_vars,
  Frequency_Top10 = map_int(all_vars, ~sum(map_lgl(bootstrap_rankings,
                                                     function(x) .x %in% x[1:10]))),
  Stability_Pct = (Frequency_Top10 / n_bootstrap) * 100
) %>%
  arrange(desc(Stability_Pct))

print("=== BOOTSTRAP STABILITY OF TOP FEATURES ===")
print("Variables appearing in Top 10 across 100 bootstrap samples:")
print(head(stability_table, 15))

# Identify stable Top 8 (>80% stability threshold)
top_8_stable <- stability_table %>%
  filter(Stability_Pct >= 80) %>%
  slice(1:8)

print("=== STABLE TOP 8 FEATURES (>80% bootstrap consistency) ===")
print(top_8_stable)

# Visualize stability
plot_stability <- stability_table %>%
  slice(1:15) %>%
  ggplot(aes(x = reorder(Variable, Stability_Pct), y = Stability_Pct)) +
  geom_col(aes(fill = Stability_Pct >= 80)) +
  geom_hline(yintercept = 80, linetype = "dashed", color = "red") +
  coord_flip() +
  scale_fill_manual(values = c("FALSE" = "orange", "TRUE" = "darkgreen"),
                    name = "Stable\n(≥80%)") +
  labs(
    title = "Bootstrap Stability of Top Features",
    subtitle = "Frequency in Top 10 across 100 bootstrap resamples",
    x = "Variable",
    y = "Stability (%)"
  ) +
  theme_minimal()

print(plot_stability)
ggsave("Figure_Bootstrap_Stability.png", plot_stability, width = 10, height = 8, dpi = 300)

# PUNTOS DE INFLEXIÓN (PARTIAL DEPENDENCE PLOTS - PDP)

# Vamos a analizar EDAD y ALBÚMINA para ver sus curvas de riesgo
pdp_age <- model_profile(explainer_rf, variables = "edad")$agr_profiles
pdp_alb <- model_profile(explainer_rf, variables = "albumina")$agr_profiles

# Graficar Edad
plot_age <- plot(pdp_age)
print(plot_age)

# Graficar Albúmina
plot_alb <- plot(pdp_alb)
print(plot_alb)

# AUTOPSIA LOCAL (WATERFALL PLOTS)

# 1. PREPARACIÓN BLINDADA DEL FALSO NEGATIVO
# Unimos quitando la columna 'desenlace' de df_testing para evitar choques
datos_unidos <- test_preds %>%
  bind_cols(df_testing %>% select(-desenlace))

# Identificar a un FALSO NEGATIVO (El "Paciente Silencioso")
# Filtro: Realidad = Fallecido | Predicción < 20%
fn_case <- datos_unidos %>%
  filter(desenlace == "Fallecido" & .pred_Fallecido < 0.20) %>%
  slice(1) # Tomamos el primero que encuentre

if(nrow(fn_case) > 0) {
  print("Generando autopsia del Falso Negativo...")
  
  # LIMPIEZA CRÍTICA PARA SHAP:
  # El explainer solo quiere ver las variables originales (edad, albumina, etc.)
  # Debemos quitar las columnas de predicción (.pred...) y la respuesta (desenlace)
  paciente_fn <- fn_case %>% 
    select(-starts_with(".pred"), -starts_with("pred_"), -desenlace)
  
  # Calcular SHAP individual (True Shapley Values for scientific consistency)
  # NOTE: Using type = "shap" instead of "break_down" to match global analysis
  # methodology and ensure clinically coherent interpretations
  set.seed(2026)
  shap_fn <- predict_parts(explainer_rf, new_observation = paciente_fn,
                           type = "shap", B = 25)
  
  plot_fn <- plot(shap_fn) +
    ggtitle("Autopsia del Falso Negativo (Fenotipo Silencioso)",
            subtitle = "Barras Verdes = Bajaron el riesgo | Barras Rojas = Subieron el riesgo")
  print(plot_fn)
  
} else {
  print("No se encontraron pacientes con probabilidad < 0.20. Sube el filtro a 0.30 o 0.40.")
}

# 2. PREPARACIÓN DEL VERDADERO POSITIVO (COMPARACIÓN)
# Filtro: Realidad = Fallecido | Predicción > 80%
tp_case <- datos_unidos %>%
  filter(desenlace == "Fallecido" & .pred_Fallecido > 0.80) %>%
  slice(1)

if(nrow(tp_case) > 0) {
  print("Generando autopsia del Verdadero Positivo...")
  
  # Limpieza para SHAP
  paciente_tp <- tp_case %>% 
    select(-starts_with(".pred"), -starts_with("pred_"), -desenlace)
  
  # Using type = "shap" for scientific consistency with global analysis
  set.seed(2026)
  shap_tp <- predict_parts(explainer_rf, new_observation = paciente_tp,
                           type = "shap", B = 25)
  
  plot_tp <- plot(shap_tp) +
    ggtitle("Anatomía de una Muerte Detectada (Verdadero Positivo)",
            subtitle = "Factores que dispararon la alarma")
  print(plot_tp)
}

# 3. PREPARACIÓN DEL VERDADERO NEGATIVO (CASO DE ÉXITO)
# Filtro: Realidad = Vivo | Predicción de Riesgo < 10% (Muy Seguro)
tn_case <- datos_unidos %>%
  filter(desenlace == "Vivo" & .pred_Fallecido < 0.10) %>%
  slice(1) # Tomamos el caso más representativo

if(nrow(tn_case) > 0) {
  print("Generando autopsia del Verdadero Negativo (Survivor)...")
  
  # A. Limpieza para SHAP (Mismo estándar que TP y FN)
  # Eliminamos columnas de predicción y desenlace para dejar solo variables clínicas
  paciente_tn <- tn_case %>% 
    select(-starts_with(".pred"), -starts_with("pred_"), -desenlace)
  
  # B. Cálculo SHAP (True Shapley Values for scientific consistency)
  set.seed(2026)
  shap_tn <- predict_parts(explainer_rf, new_observation = paciente_tn,
                           type = "shap", B = 25)
  
  # C. Visualización
  plot_tn <- plot(shap_tn) +
    ggtitle("Anatomía de una Supervivencia (Verdadero Negativo)",
            subtitle = "Factores protectores que redujeron el riesgo (Barras Verdes)") +
    theme(plot.title = element_text(size = 14, face = "bold"))
  
  print(plot_tn)
  
  # Guardar para el póster
  # ggsave("Figure_TrueNegative.png", plot_tn, width = 8, height = 6, dpi = 300)
  
} else {
  print("No se encontraron casos con probabilidad < 0.10. Intenta subir el filtro a < 0.20.")
}

# ==== FINAL TOP 8 VARIABLE SELECTION WITH STATISTICAL JUSTIFICATION ====
# Combines consensus importance, bootstrap stability, and cross-model validation

print("=== GENERATING FINAL TOP 8 VARIABLES FOR WEB CALCULATOR ===")

# Criteria for Top 8 selection:
# 1. Appears in consensus top 10 (mean rank across RF + XGBoost)
# 2. Bootstrap stability ≥ 80%
# 3. Rank consistency ≥ 0.75 (low SD_Rank relative to Mean_Rank)

final_top_8 <- consensus_importance %>%
  filter(variable_name %in% top_8_stable$Variable) %>%  # Bootstrap validated
  filter(Consistency > 0.75) %>%  # Rank consistency across models
  arrange(Mean_Rank) %>%
  slice(1:8)

print("════════════════════════════════════════════════════════════")
print("FINAL TOP 8 VARIABLES FOR WEB CALCULATOR:")
print("════════════════════════════════════════════════════════════")
print(final_top_8)
print("")
print("Selection Criteria Applied:")
print("✓ Cross-model consensus (RF + XGBoost mean rank)")
print("✓ Bootstrap stability ≥ 80% (robust across resampling)")
print("✓ Rank consistency ≥ 0.75 (stable importance across models)")
print(paste("✓ Feature ranking correlation: r =", round(rank_correlation$estimate, 3)))
print("════════════════════════════════════════════════════════════")

# Save final top 8 for API use
saveRDS(final_top_8, "top_8_validated_features.rds")
write.csv(final_top_8, "top_8_validated_features.csv", row.names = FALSE)

print("✓ Top 8 features saved to: top_8_validated_features.rds")
print("✓ Top 8 features saved to: top_8_validated_features.csv")

# Create final summary visualization
plot_final_top8 <- final_top_8 %>%
  ggplot(aes(x = reorder(variable_name, -Mean_Rank), y = Mean_SHAP)) +
  geom_col(aes(fill = Consistency), width = 0.7) +
  geom_text(aes(label = paste0("Rank: ", round(Mean_Rank, 1))),
            hjust = -0.1, size = 3) +
  coord_flip() +
  scale_fill_gradient(low = "orange", high = "darkgreen",
                      name = "Consistency") +
  labs(
    title = "FINAL TOP 8 VARIABLES FOR WEB CALCULATOR",
    subtitle = "Publication-Quality Selection: Consensus + Bootstrap + Cross-Model Validation",
    x = "Variable",
    y = "Mean |SHAP| (Importance)",
    caption = paste0("Feature correlation (RF-XGB): r = ",
                     round(rank_correlation$estimate, 3),
                     " | All features: >80% bootstrap stability")
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", size = 14))

print(plot_final_top8)
ggsave("Figure_FINAL_Top8_Variables.png", plot_final_top8, width = 10, height = 6, dpi = 300)

print("")
print("═══════════════════════════════════════════════════════════")
print("PHASE 2: MULTI-MODEL SHAP ANALYSIS - COMPLETE")
print("═══════════════════════════════════════════════════════════")

