# SCRIPT MAESTRO: RANDOM FOREST (TRAINING, TUNING & OPTIMIZATION)

# Librerías base
library(tidymodels)
library(tidyverse)
library(doParallel)
library(probably)
library(vip)
library(patchwork)
library(themis)

# ==== LOAD PREPROCESSING OBJECTS (STANDALONE MODE) ====
if(!exists("df_training") || !exists("rf_recipe")) {
  if(file.exists("data_training.rds") && file.exists("rf_recipe_master.rds")) {
    df_training <- readRDS("data_training.rds")
    df_testing <- readRDS("data_testing.rds")
    data_split <- readRDS("data_split.rds")
    rf_recipe <- readRDS("rf_recipe_master.rds")
    cat("✓ Loaded preprocessing objects from RDS files\n")
  } else {
    cat("⚠ Preprocessing objects missing. Running full pipeline...\n")
    source("Data_Cleaning_Organization.R")
    source("Random_Forest_Preprocess.R")
    cat("✓ Preprocessing pipeline completed\n")
  }
} else {
  cat("✓ Using preprocessing objects from current R session\n")
}

# ==== 1. GRID SEARCH & SELECCIÓN DE MODELO (ENTRENAMIENTO) ====

# A. Preparación de Folds
set.seed(2026)
cv_folds <- vfold_cv(df_training, v = 5, strata = desenlace)

# B. Especificación del Modelo
rf_spec <- rand_forest(
  trees = 1000,
  mtry = tune(),
  min_n = tune()
) %>%
  set_engine("ranger", importance = "impurity") %>%
  set_mode("classification")

# C. Workflow
rf_workflow <- workflow() %>%
  add_recipe(rf_recipe) %>%
  add_model(rf_spec)

# D. Definición del Grid (ENHANCED FOR PUBLICATION - 50 combinations)
# Justification:
# - mtry expanded to 2-20 (3.6%-36% of features) to capture optimal feature sampling
# - min_n lowered to 5 to test typical RF optimums for classification
# - 50 combinations (10×5) provides thorough exploration without excessive computation
rf_grid <- grid_regular(
  mtry(range = c(2, 20)),      # Expanded from c(3,10) - test wider feature sampling
  min_n(range = c(5, 40)),     # Lowered from 10 - capture typical optimum 5-10
  levels = c(10, 5)            # 10 mtry levels × 5 min_n levels = 50 combinations
)

# E. Ejecución en Paralelo
all_cores <- detectCores(logical = FALSE)
cl <- makePSOCKcluster(all_cores - 1)
registerDoParallel(cl)

print(paste("Iniciando Tuning en", all_cores - 1, "núcleos..."))

set.seed(2026)
rf_res <- tune_grid(
  rf_workflow,
  resamples = cv_folds,
  grid = rf_grid,
  metrics = metric_set(roc_auc, sens, spec, kap, pr_auc),
  control = control_grid(save_pred = TRUE, verbose = TRUE)
)

# Apagar cluster
stopCluster(cl)
registerDoSEQ()

# F. Selección del Ganador
print(show_best(rf_res, metric = "roc_auc"))

best_rf <- select_best(rf_res, metric = "roc_auc")
final_rf_workflow <- finalize_workflow(rf_workflow, best_rf)

# ==== 2. FINAL FIT & EVALUACIÓN INICIAL (DEFAULT THRESHOLD 0.5) ====

set.seed(2026)
final_fit <- last_fit(final_rf_workflow, data_split)

# Métricas Globales (AUC)
print(collect_metrics(final_fit))

# Predicciones crudas
test_preds <- collect_predictions(final_fit)

# ==== 3. OPTIMIZACIÓN DE UMBRAL (EL "NUEVO CORTE" DE 31.8%) ====

# Definimos el umbral clínico optimizado por Youden (Hard-coded para consistencia)
# Este valor maximiza Sensibilidad (~90%) y NPV (~98%)
optimal_threshold <- 0.3183577

print(paste("--- APLICANDO UMBRAL CLÍNICO OPTIMIZADO:", round(optimal_threshold, 4), "---"))

# Generamos las predicciones y matriz con este nuevo corte
test_preds_opt <- test_preds %>%
  mutate(
    pred_opt = if_else(.pred_Fallecido >= optimal_threshold, "Fallecido", "Vivo"),
    pred_opt = factor(pred_opt, levels = levels(df_training$desenlace))
  )

# Matriz de Confusión Optimizada (Objeto clave para scripts posteriores)
conf_mat_opt <- conf_mat(test_preds_opt, truth = desenlace, estimate = pred_opt)
print(conf_mat_opt)

# Visualización de la Matriz Final
plot_cm <- autoplot(conf_mat_opt, type = "heatmap") +
  labs(
    title = "Matriz de Confusión Optimizada (Test Set)",
    subtitle = paste("Estrategia de Alta Sensibilidad | Umbral >", round(optimal_threshold, 3))
  )
print(plot_cm)

# Métricas Finales Detalladas
metricas_finales <- summary(conf_mat_opt, event_level = "first") %>%
  filter(.metric %in% c("sens", "spec", "ppv", "npv", "accuracy", "kap")) %>%
  select(.metric, .estimate)

print("--- MÉTRICAS CLÍNICAS FINALES ---")
print(metricas_finales)

# Guardar Gráfico
ggsave("Figure1_ConfusionMatrix_Opt.png", plot_cm, width = 6, height = 5, dpi = 300)

# ==== 4. EXPLICABILIDAD (VIP PLOT) ====

final_model_obj <- extract_fit_parsnip(final_fit)

vip_plot <- vip(final_model_obj, num_features = 15, geom = "col", aesthetics = list(fill = "#2c3e50")) +
  labs(
    title = "Top 15 Predictores de Mortalidad COVID-19",
    subtitle = "Importancia basada en Random Forest (Gini Impurity)",
    y = "Importancia Relativa",
    x = "Variable"
  ) +
  theme_minimal()

print(vip_plot)
ggsave("Figure2_VariableImportance.png", vip_plot, width = 8, height = 6, dpi = 300)

# 5. ==== ANÁLISIS DE ERRORES ====

# A. Visualización de Probabilidades
p1 <- test_preds %>%
  filter(desenlace == "Fallecido") %>%
  ggplot(aes(x = .pred_Fallecido)) +
  geom_histogram(bins = 20, fill = "#c0392b", alpha = 0.7) +
  geom_vline(xintercept = optimal_threshold, linetype = "dashed", color = "black") + # Mostramos el nuevo corte
  annotate("text", x = optimal_threshold + 0.05, y = 5, label = "Corte 31%", angle = 90) +
  labs(
    title = "Distribución de Riesgo en FALLECIDOS",
    subtitle = "La línea punteada indica el umbral optimizado para capturar el riesgo bajo",
    x = "Probabilidad Predicha"
  ) +
  theme_minimal()

p2 <- test_preds %>%
  ggplot(aes(x = .pred_Fallecido, fill = desenlace)) +
  geom_density(alpha = 0.5) +
  geom_vline(xintercept = optimal_threshold, linetype = "dashed") +
  labs(
    title = "Densidad de Probabilidades (Vivo vs Fallecido)",
    subtitle = "Separación de clases con el nuevo umbral clínico"
  ) +
  theme_minimal()

print(p1 / p2)
print(p2)

# B. Extracción de Falsos Negativos Extremos (Aun con el nuevo corte)
# (Pacientes que murieron pero tienen < 20% de riesgo, los "invisibles")
falsos_negativos_extremos <- test_preds %>%
  bind_cols(df_testing %>% select(-desenlace)) %>% 
  filter(desenlace == "Fallecido" & .pred_Fallecido < 0.20) %>%
  select(edad, sexo, severidad_sars, bilirrtotal, albumina, plaquetas, .pred_Fallecido)

print(falsos_negativos_extremos)
