# ==== RANDOM FOREST PRE-PROCESS ====

# Libraries:
library(tidymodels)
library(tidyverse)
library(themis)
library(corrr)
library(gt)

# Configuración de preferencias para evitar notación científica
options(scipen = 999)
tidymodels_prefer()

# ==== LOAD DATA (STANDALONE MODE) ====
# Check if running standalone (Rscript) or sourced (interactive)
if(!exists("df_clean")) {
  if(file.exists("data_cleaned.rds")) {
    df_clean <- readRDS("data_cleaned.rds")
    cat("✓ Loaded cleaned data from: data_cleaned.rds\n")
  } else {
    stop("\n✗ ERROR: df_clean not found and data_cleaned.rds missing.\n",
         "  → Run Data_Cleaning_Organization.R first.\n")
  }
} else {
  cat("✓ Using df_clean from current R session\n")
}

# ==== 1. CLEAN DATAFRAME OPTIMIZATION AND LEVEL CONFIGURATION ====

glimpse(df_clean)

df_model <- df_clean %>%
  select(- id, # De-select useless (no predicting columns)
         - dias_hospitalizado,
         - starts_with('med_'),
         - endo_colono_cpre) %>%
  mutate(
    desenlace = if_else(fallecido == TRUE, "Fallecido", "Vivo"), # Re-name fallecido column as desenlace and change lgl to chr
    desenlace = factor(desenlace, levels = c("Fallecido", "Vivo")), # Change desenlace column to fct and state the initial level to "Fallecido"
    across(where(is.logical), as.factor),
    sexo = factor(sexo, levels = c('hombre', 'mujer')),
    severidad_sars = factor(severidad_sars, levels = c('Leve', 'Moderado', 'Severo'))
  ) %>%
  select(- fallecido)

# Checking results:
glimpse(df_model)
ncol(df_model) # [1] 55
nrow(df_model) # [1] 1313
print(levels(df_model$desenlace)) # [1] "Fallecido" "Vivo"   

# ==== 2. STRATIFIED SPLIT ====

set.seed(2026)
data_split <- initial_split(df_model, prop = 0.80, strata = desenlace) # Keep desenlace equal in both testing and training dataframes
df_training <- training(data_split)
df_testing  <- testing(data_split)

# Checking results:
print(paste("Dimensiones Training:", nrow(df_training), "| Dimensiones Testing:", nrow(df_testing)))
# [1] "Dimensiones Training: 1050 | Dimensiones Testing: 263"

# Checking proportions:

prop.table(table(df_model$desenlace)) # ORIGINAL dataframe
# Fallecido      Vivo 
# 0.1599391   0.8400609 

prop.table(table(df_training$desenlace)) # TRAINING dataframe
# Fallecido      Vivo 
#   0.16         0.84 

prop.table(table(df_testing$desenlace)) # TESTING dataframe
# Fallecido      Vivo 
# 0.1596958    0.8403042 

# ==== 3. COLINEALITY CHECK ====

# Selecting only numerical data:
correlation_check <- df_training %>%
  select(where(is.numeric)) %>%
  correlate(method = "spearman", quiet = TRUE) %>%
  shave()

# Filtering high correlations with threshold r > 60:
correlation_check %>%
  stretch() %>%
  filter(abs(r) > 0.60) # Treshold for correlation: r > 60

# Results:
#    x     y      r
# 1 peso  imc   0.885
# 2 tgo   tgp   0.811

# ==== 4. RECIPE: FEATURE ENGINEEIRING + SMOTE ====

rf_recipe <- recipe(desenlace ~ ., data = df_training) %>%
  
  # A. Imputation for NA
  step_impute_knn(all_numeric_predictors(), neighbors = 5) %>% # KNN for num variables
  step_impute_mode(all_nominal_predictors(), - all_outcomes()) %>% # Mode input for fct variables
  
  # B. Laboratory ratios
  step_mutate(
    ratio_hepatico = bilirrtotal / (albumina + 0.1), # Ratio TB:A for hepatic function
    log_plaquetas = log(plaquetas + 1), # Log-scale for plaquetas
  ) %>%
  
  # C. Colineality cleaning (threshold = 0.60)
  step_corr(all_numeric_predictors(), threshold = 0.60) %>% 
  step_nzv(all_predictors()) %>%
  
  # D. SMOTE preparation
  step_YeoJohnson(all_numeric_predictors()) %>%
  step_normalize(all_numeric_predictors()) %>%
  
  # E. Encoding (chr -> num)
  step_dummy(all_nominal_predictors(), -all_outcomes()) %>%
  
  # F. SMOTE (Current: 1.0 | Optimal: 0.8 per compare_smote_ratios.R)
  # Note: Ratio 0.8 provides +0.24% AUC improvement (0.8703 vs 0.8679)
  # Current models use 1.0 for consistency; future retraining should use 0.8
  step_smote(desenlace, over_ratio = 1, neighbors = 5)

# ==== 5. BAKE CHECK ====

# Prep Training:
rf_prep <- prep(rf_recipe, training = df_training)

# Baked recipe:
df_training_baked <- bake(rf_prep, new_data = NULL)

# Checking results:
ncol(df_training_baked) # [1] 37
print(table(df_training_baked$desenlace))
# Fallecido      Vivo 
#   882          882 

# Checking affected columns by collineality:
names(df_training_baked)
# imc and tgp column are inside. No peso and tgo

# Saving:
saveRDS(rf_recipe, "rf_recipe_master.rds")

# ==== SAVE PREPROCESSING OBJECTS FOR PIPELINE ====
saveRDS(df_model, "data_model_ready.rds")
saveRDS(df_training, "data_training.rds")
saveRDS(df_testing, "data_testing.rds")
saveRDS(data_split, "data_split.rds")
# Note: rf_recipe already saved as "rf_recipe_master.rds" above

cat("\n✓ Preprocessing objects saved:\n")
cat("  - data_model_ready.rds (", nrow(df_model), " rows)\n", sep="")
cat("  - data_training.rds (", nrow(df_training), " rows)\n", sep="")
cat("  - data_testing.rds (", nrow(df_testing), " rows)\n", sep="")
cat("  - data_split.rds\n")
cat("  - rf_recipe_master.rds\n\n")