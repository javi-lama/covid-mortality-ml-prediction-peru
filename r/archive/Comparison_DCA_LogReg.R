# ==== DCA ====

library(dcurves)

# Preparamos la data: DCA necesita 0/1 numérico, no factores
df_dca <- df_testing %>%
  mutate(
    desenlace_num = ifelse(desenlace == "Fallecido", 1, 0),
    pred_rf = test_preds$.pred_Fallecido # Probabilidad del RF
  )

# Calculamos DCA
dca_plot <- dca(desenlace_num ~ pred_rf, 
                data = df_dca,
                thresholds = seq(0, 0.5, by = 0.01),
                label = list(pred_rf = "Random Forest")) %>%
  plot(smooth = TRUE) +
  ggtitle("Decision Curve Analysis (DCA)")

print(dca_plot)

# ==== LOG REGRESSION ====

library(tidymodels)
library(tidyverse)

# A. Especificar modelo simple (GLM)
glm_spec <- logistic_reg() %>%
  set_engine("glm") %>%
  set_mode("classification")

# B. Crear receta simple para GLM (GLM no maneja bien muchos NAs, así que imputamos igual)
# Usamos la misma lógica de imputación para ser justos, pero sin SMOTE (para ver baseline puro)
glm_recipe <- recipe(desenlace ~ ., data = df_training) %>%
  step_impute_knn(all_numeric_predictors(), neighbors = 5) %>%
  step_impute_mode(all_nominal_predictors(), -all_outcomes()) %>%
  step_dummy(all_nominal_predictors(), -all_outcomes()) %>%
  step_normalize(all_numeric_predictors()) # GLM se beneficia de esto

# C. Workflow y Ajuste
glm_workflow <- workflow() %>%
  add_recipe(glm_recipe) %>%
  add_model(glm_spec)

set.seed(2026)
glm_fit <- fit(glm_workflow, data = df_training)

# Predicciones GLM en Test Set
glm_preds <- predict(glm_fit, df_testing, type = "prob") %>%
  bind_cols(df_testing %>% select(desenlace)) %>%
  mutate(modelo = "Regresión Logística (Standard)")

# Recuperamos las predicciones del Random Forest (que ya tenías en test_preds)
# Asegúrate de agregarle la columna 'modelo' para poder graficar junto
rf_preds_clean <- test_preds %>% 
  select(.pred_Fallecido, desenlace) %>%
  mutate(modelo = "Random Forest (Proposed)")

# Unimos ambas para el gráfico
benchmark_df <- bind_rows(rf_preds_clean, glm_preds)

# Calcular curvas
roc_curves <- benchmark_df %>%
  group_by(modelo) %>%
  roc_curve(desenlace, .pred_Fallecido)

# Graficar
plot_benchmark <- autoplot(roc_curves) +
  ggtitle("Comparación de Rendimiento: Machine Learning vs. Estadística Clásica",
          subtitle = "Random Forest demuestra mayor discriminación global") +
  theme_minimal() +
  scale_color_manual(values = c("Random Forest (Proposed)" = "#2980b9", # Azul fuerte
                                "Regresión Logística (Standard)" = "#95a5a6")) # Gris

print(plot_benchmark)

auc_stats <- benchmark_df %>%
  group_by(modelo) %>%
  roc_auc(desenlace, .pred_Fallecido)

print(auc_stats)

# Guardar la evidencia
ggsave("Figure5_BenchmarkROC.png", plot_benchmark, width = 7, height = 5, dpi = 300)
