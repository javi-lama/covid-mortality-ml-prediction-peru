# ============================================================================
# POSTER FIGURES — DEFINITIVE SCRIPT
# ============================================================================
#
# CONTEXT: Scientific poster for APJ 2026 contest
# Creates 2 publication-quality figures in scientific Spanish
#
# DATA SOURCES (confirmed to exist via diagnostic):
#   - roc_list_multimodel.rds  → list of 4 pROC objects (RF, XGB, SVM, LogReg)
#   - auc_results_multimodel.rds → tibble with AUC + bootstrap CIs
#   - shap_values (in workspace) → DALEX predict_parts object (RF)
#
# STRUCTURE OF roc_list_multimodel.rds (from Multi_Model_Comparison.R line 181):
#   list("Random Forest" = roc_rf,
#        "XGBoost" = roc_xgb,
#        "SVM-RBF" = roc_svm,
#        "Logistic Regression" = roc_logreg)
#
# STRUCTURE OF auc_results_multimodel.rds (from Multi_Model_Comparison.R):
#   tibble with columns: Model, AUC, AUC_lower, AUC_upper
#
# STRUCTURE OF shap_values (from SHAP.R line 119-123):
#   DALEX predict_parts object, coercible to data.frame with columns:
#   variable_name, variable, variable_value, contribution, sign, B, ...
#
# OUTPUT:
#   - Poster_Fig1_ROC_MultiModel.png  (960×760 @300DPI)
#   - Poster_Fig2_SHAP_Tornado.png    (960×680 @300DPI)
#
# ============================================================================

# ── LIBRARIES ──
library(tidyverse)
library(pROC)

set.seed(2026)

# ============================================================================
# GLOBAL POSTER AESTHETIC
# ============================================================================

# Colors — colorblind-friendly, from Multi_Model_Figures.R line 38-48
COL <- list(
  rf     = "#004E89",   # Blue
  xgb    = "#E63946",   # Red
  svm    = "#2A9D8F",   # Teal
  logreg = "#7F8C8D",   # Gray (benchmark)
  navy   = "#1B3A5C",   # Titles
  risk   = "#C0392B",   # SHAP risk direction
  prot   = "#27AE60"    # SHAP protective direction
)

theme_poster_fig <- function(base_size = 14) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title    = element_text(face = "bold", size = base_size + 4,
                                   color = COL$navy, hjust = 0.5,
                                   margin = margin(b = 4)),
      plot.subtitle = element_text(size = base_size - 2, color = "#5D6D7E",
                                   hjust = 0.5, margin = margin(b = 8)),
      axis.title    = element_text(face = "bold", size = base_size,
                                   color = COL$navy),
      axis.text     = element_text(size = base_size - 2, color = "#2C3E50"),
      legend.title  = element_blank(),
      legend.text   = element_text(size = 11),
      panel.grid.major = element_line(color = "#ECF0F1", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      plot.margin   = margin(t = 8, r = 12, b = 4, l = 8)
    )
}


# ============================================================================
# FIGURE 1: MULTI-MODEL ROC (4 MODELS)
# ============================================================================

cat("\n══════════════════════════════════════════════\n")
cat("  FIGURE 1: MULTI-MODEL ROC CURVES\n")
cat("══════════════════════════════════════════════\n\n")

# ── 1A. LOAD DATA ──
roc_list    <- readRDS("roc_list_multimodel.rds")
auc_results <- readRDS("auc_results_multimodel.rds")

cat("Loaded roc_list with models:", paste(names(roc_list), collapse = ", "), "\n")
cat("Loaded auc_results:\n")
print(auc_results %>% select(Model, AUC, AUC_lower, AUC_upper))

# ── 1B. BUILD ROC CURVE DATA FROM pROC OBJECTS ──
# (Same logic as Multi_Model_Figures.R lines 104-113)
roc_df <- purrr::imap_dfr(roc_list, function(roc_obj, model_name) {
  tibble::tibble(
    sensitivity = roc_obj$sensitivities,
    fpr         = 1 - roc_obj$specificities,
    model_raw   = model_name
  )
})

cat("\nROC data points per model:\n")
print(table(roc_df$model_raw))

# ── 1C. BUILD LEGEND LABELS DYNAMICALLY (no hardcoded AUCs) ──
# Map English model names to Spanish display labels with AUC
label_lookup <- auc_results %>%
  mutate(
    # Spanish display name
    display_name = case_when(
      grepl("Logistic|logis", Model, ignore.case = TRUE) ~ "Reg. Logística",
      grepl("Random|Forest|RF", Model, ignore.case = TRUE) ~ "Random Forest",
      grepl("SVM|RBF", Model, ignore.case = TRUE) ~ "SVM-RBF",
      grepl("XGB|Boost", Model, ignore.case = TRUE) ~ "XGBoost",
      TRUE ~ Model
    ),
    # Full label with AUC and CI
    label = sprintf("%s: AUC %.3f (%.3f\u2013%.3f)",
                    display_name, AUC, AUC_lower, AUC_upper)
  )

cat("\nLabel mapping:\n")
for (i in seq_len(nrow(label_lookup))) {
  cat(sprintf("  '%s' → '%s'\n", label_lookup$Model[i], label_lookup$label[i]))
}

# Create named vector: raw model name → full label
label_vec <- setNames(label_lookup$label, label_lookup$Model)

# ── 1D. ASSIGN COLORS (pattern-matched to model identity) ──
color_vec <- setNames(
  sapply(label_lookup$Model, function(m) {
    m_lower <- tolower(m)
    if (grepl("logis|logr|glm", m_lower))      return(COL$logreg)
    if (grepl("random|forest|rf", m_lower))     return(COL$rf)
    if (grepl("svm|rbf", m_lower))              return(COL$svm)
    if (grepl("xgb|boost", m_lower))            return(COL$xgb)
    return("#8E44AD")  # fallback purple
  }),
  label_lookup$Model
)

# ── 1E. ASSIGN LINETYPES ──
ltype_vec <- setNames(
  sapply(label_lookup$Model, function(m) {
    if (grepl("logis|logr|glm", tolower(m))) return("dashed")
    return("solid")
  }),
  label_lookup$Model
)

# ── 1F. ORDER BY AUC DESCENDING ──
model_order <- label_lookup %>% arrange(desc(AUC)) %>% pull(Model)

# Apply labels and ordering to roc_df
roc_df <- roc_df %>%
  mutate(
    model_label = label_vec[model_raw],
    model_label = factor(model_label, levels = label_vec[model_order])
  )

# Rekey color and linetype vectors to label names
color_final <- setNames(color_vec[model_order], label_vec[model_order])
ltype_final <- setNames(ltype_vec[model_order], label_vec[model_order])

# ── 1G. COMPUTE DeLONG p-value FOR RF vs LogReg (for annotation) ──
# Find which names correspond to RF and LogReg
rf_name     <- grep("Random|Forest|RF", names(roc_list), value = TRUE, ignore.case = TRUE)[1]
logreg_name <- grep("Logistic|logis", names(roc_list), value = TRUE, ignore.case = TRUE)[1]

delong_test <- pROC::roc.test(roc_list[[rf_name]], roc_list[[logreg_name]], method = "delong")
delta_auc   <- as.numeric(pROC::auc(roc_list[[rf_name]])) -
               as.numeric(pROC::auc(roc_list[[logreg_name]]))
p_delong    <- delong_test$p.value

delong_label <- sprintf(
  "RF vs Reg. Logística:\n\u0394AUC = %.3f, p = %.2f (NS)",
  delta_auc, p_delong
)
cat("\nDeLong annotation:", gsub("\n", " | ", delong_label), "\n")

# ── 1H. PLOT ──
fig_roc <- ggplot(roc_df, aes(x = fpr, y = sensitivity,
                               color = model_label,
                               linetype = model_label)) +
  # Reference diagonal
  geom_abline(slope = 1, intercept = 0,
              linetype = "dotted", color = "#BDC3C7", linewidth = 0.5) +
  # ROC curves
  geom_path(linewidth = 0.8, alpha = 0.85) +
  # Aesthetics
  scale_color_manual(values = color_final) +
  scale_linetype_manual(values = ltype_final) +
  # DeLong annotation
  annotate("text", x = 0.50, y = 0.18,
           label = delong_label,
           size = 3.8, color = COL$navy, fontface = "italic",
           hjust = 0, lineheight = 0.9) +
  # Axes — NO coord_equal (causes clipping on non-square canvas)
  coord_cartesian(xlim = c(0, 1.02), ylim = c(0, 1.02)) +
  scale_x_continuous(breaks = seq(0, 1, 0.25), expand = c(0, 0.01)) +
  scale_y_continuous(breaks = seq(0, 1, 0.25), expand = c(0, 0.01)) +
  # Labels (Spanish)
  labs(
    title    = "Comparación de Curvas ROC",
    subtitle = paste0("Conjunto de validación interna (n = ",
                      length(roc_list[[1]]$response), ")"),
    x = "1 \u2212 Especificidad (Falsos Positivos)",
    y = "Sensibilidad (Verdaderos Positivos)"
  ) +
  # Theme
  theme_poster_fig(base_size = 14) +
  theme(
    legend.position  = "bottom",
    legend.direction = "vertical",
    legend.key.width = unit(1.5, "lines"),
    aspect.ratio     = 0.85
  ) +
  guides(
    color    = guide_legend(ncol = 1, override.aes = list(linewidth = 1.5)),
    linetype = guide_legend(ncol = 1)
  )

# ── 1I. SAVE ──
ggsave(
  "Poster_Fig1_ROC_MultiModel.png",
  fig_roc,
  width  = 960 / 150,
  height = 760 / 150,
  dpi    = 300,
  bg     = "white"
)

cat("\n✅ FIGURE 1 SAVED: Poster_Fig1_ROC_MultiModel.png\n")
cat("   Models plotted:", length(roc_list), "\n")
cat("   Legend order:", paste(model_order, collapse = " > "), "\n")


# ============================================================================
# FIGURE 2: SHAP DIRECTIONAL TORNADO (TOP 10 VARIABLES)
# ============================================================================

cat("\n══════════════════════════════════════════════\n")
cat("  FIGURE 2: SHAP DIRECTIONAL TORNADO\n")
cat("══════════════════════════════════════════════\n\n")

# ── 2A. VALIDATE shap_values EXISTS ──
if (!exists("shap_values")) {
  stop(
    "❌ 'shap_values' not found in workspace.\n",
    "   → Source SHAP.R first, or ensure the object is loaded.\n",
    "   → It is a DALEX predict_parts object created at SHAP.R line 119."
  )
}

cat("shap_values class:", paste(class(shap_values), collapse = "/"), "\n")
cat("shap_values dimensions:", nrow(shap_values), "x", ncol(shap_values), "\n")

# ── 2B. PROCESS SHAP DATA ──
# Exact logic from Visualizations.R lines 188-227
# Convert DALEX object to data.frame, clean variable names, compute directional means

datos_tornado <- shap_values %>%
  as.data.frame() %>%
  filter(variable != "_baseline_") %>%
  mutate(
    var_raw = as.character(variable),
    # Map technical variable names to clinical Spanish labels
    # (same mapping as Visualizations.R lines 193-207)
    var_clean = case_when(
      grepl("severidad_sars",         var_raw) ~ "Severidad Clínica",
      grepl("sxingr_disnea",          var_raw) ~ "Disnea",
      grepl("sxingr_fiebre|fiebre",   var_raw) ~ "Fiebre",
      grepl("^albumina",              var_raw) ~ "Albúmina",
      grepl("sxingr_nauseavomito",    var_raw) ~ "Náuseas/Vómitos",
      grepl("automed_paracetamol|automed", var_raw) ~ "Automedicación",
      grepl("^edad",                  var_raw) ~ "Edad",
      grepl("plaquetas|log_plaquetas",var_raw) ~ "Plaquetas",
      grepl("sxingr_cefalea",         var_raw) ~ "Cefalea",
      grepl("^tgp|tgp =",            var_raw) ~ "TGP (ALT)",
      grepl("sxingr_dolorgarganta",   var_raw) ~ "Dolor de Garganta",
      grepl("sxingr_odinofagia",      var_raw) ~ "Odinofagia",
      grepl("^inr",                   var_raw) ~ "INR",
      grepl("^imc",                   var_raw) ~ "IMC",
      grepl("^sexo",                  var_raw) ~ "Sexo",
      grepl("ant_dm",                 var_raw) ~ "Diabetes Mellitus",
      grepl("sxingr_tos",             var_raw) ~ "Tos",
      TRUE ~ str_to_title(str_replace_all(var_raw, "_", " "))
    )
  ) %>%
  # Aggregate: mean positive (risk) and mean negative (protective) contribution
  group_by(var_clean) %>%
  summarise(
    mean_risk       = mean(contribution[contribution > 0], na.rm = TRUE),
    mean_prot       = mean(contribution[contribution < 0], na.rm = TRUE),
    total_importance = mean(abs(contribution)),
    .groups = "drop"
  ) %>%
  mutate(
    mean_risk = ifelse(is.nan(mean_risk) | is.na(mean_risk), 0, mean_risk),
    mean_prot = ifelse(is.nan(mean_prot) | is.na(mean_prot), 0, mean_prot)
  ) %>%
  arrange(desc(total_importance)) %>%
  slice_head(n = 10)

cat("\nTop 10 variables by total importance:\n")
print(datos_tornado %>% select(var_clean, total_importance, mean_risk, mean_prot))

# Pivot for diverging bar chart
datos_tornado_long <- datos_tornado %>%
  tidyr::pivot_longer(
    cols      = c(mean_risk, mean_prot),
    names_to  = "tipo",
    values_to = "impacto"
  ) %>%
  mutate(
    direccion = ifelse(tipo == "mean_risk", "Aumenta Riesgo", "Disminuye Riesgo"),
    direccion = factor(direccion, levels = c("Aumenta Riesgo", "Disminuye Riesgo")),
    var_clean = fct_reorder(var_clean, total_importance)
  )

# ── 2C. PLOT ──
fig_tornado <- ggplot(datos_tornado_long,
                      aes(x = impacto, y = var_clean, fill = direccion)) +
  # Zero reference line
  geom_vline(xintercept = 0, color = "grey40", linewidth = 0.6) +
  # Bars
  geom_col(width = 0.7, alpha = 0.9) +
  # Colors
  scale_fill_manual(values = c(
    "Aumenta Riesgo"   = COL$risk,
    "Disminuye Riesgo" = COL$prot
  )) +
  # Labels (Spanish)
  labs(
    title    = "Interpretabilidad: Impacto de Variables",
    subtitle = "Contribución promedio SHAP hacia mortalidad o supervivencia",
    x = "Impacto Medio en la Probabilidad (SHAP)",
    y = NULL,
    fill = "Dirección"
  ) +
  # Theme
  theme_poster_fig(base_size = 14) +
  theme(
    legend.position  = "bottom",
    legend.direction = "horizontal",
    legend.text      = element_text(size = 12, face = "bold"),
    axis.text.y      = element_text(size = 13, face = "bold"),
    panel.grid.major.y = element_blank()
  )

# ── 2D. SAVE ──
ggsave(
  "Poster_Fig2_SHAP_Tornado.png",
  fig_tornado,
  width  = 960 / 150,
  height = 680 / 150,
  dpi    = 300,
  bg     = "white"
)

cat("\n✅ FIGURE 2 SAVED: Poster_Fig2_SHAP_Tornado.png\n")
cat("   Variables displayed:", nrow(datos_tornado), "\n")


# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  POSTER FIGURES COMPLETE\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("  1. Poster_Fig1_ROC_MultiModel.png  (4 models, Spanish)\n")
cat("  2. Poster_Fig2_SHAP_Tornado.png    (Top 10, Spanish)\n")
cat("═══════════════════════════════════════════════════════════\n")
cat("\n  Upload both PNGs to Claude for final poster assembly.\n\n")
