# EXPERIMENTO DE ABLACIÓN (CORREGIDO)
# Hipótesis: ¿Puede el modelo predecir sin la "muleta" de la severidad clínica?

library(vip)

# 1. DEFINIR LA RECETA DE ABLACIÓN DESDE CERO
# (Es más seguro que intentar modificar la anterior)
rf_recipe_nosev <- recipe(desenlace ~ ., data = df_training) %>%
  
  # PASO CRÍTICO: ELIMINAR SEVERIDAD PRIMERO
  step_rm(severidad_sars) %>% 

# AHORA COPIAMOS LOS MISMOS PASOS DE TU RECETA MAESTRA
# A. Imputación
step_impute_knn(all_numeric_predictors(), neighbors = 5) %>%
  step_impute_mode(all_nominal_predictors(), -all_outcomes()) %>%
  
  # B. Ratios
  step_mutate(
    ratio_hepatico = bilirrtotal / (albumina + 0.1),
    log_plaquetas = log(plaquetas + 1)
  ) %>%
  
  # C. Limpieza
  step_corr(all_numeric_predictors(), threshold = 0.60) %>% 
  step_nzv(all_predictors()) %>%
  
  # D. Normalización (SMOTE prep)
  step_YeoJohnson(all_numeric_predictors()) %>%
  step_normalize(all_numeric_predictors()) %>%
  
  # E. Encoding
  step_dummy(all_nominal_predictors(), -all_outcomes()) %>%
  
  # F. SMOTE
  step_smote(desenlace, over_ratio = 1, neighbors = 5)

# 2. ACTUALIZAR EL WORKFLOW
rf_workflow_nosev <- workflow() %>%
  add_recipe(rf_recipe_nosev) %>%
  add_model(rf_spec %>% finalize_model(best_rf)) # Usamos la misma config ganadora

# 3. ENTRENAMIENTO RÁPIDO (LAST FIT)
set.seed(2026)
fit_nosev <- last_fit(rf_workflow_nosev, data_split)

# 4. COMPARAR RESULTADOS
metrics_nosev <- collect_metrics(fit_nosev)
print(metrics_nosev)

# 5. NUEVO GRÁFICO DE IMPORTANCIA
# ¿Quién toma el trono ahora que no está la severidad?
model_obj_nosev <- extract_fit_parsnip(fit_nosev)

vip_nosev <- vip(model_obj_nosev, num_features = 15, geom = "col", aesthetics = list(fill = "#d35400")) +
  labs(
    title = "Factores Predictivos (Modelo SIN Severidad)",
    subtitle = "¿Qué variables biomédicas toman el control?",
    y = "Importancia Relativa"
  ) +
  theme_minimal()

print(vip_nosev)
