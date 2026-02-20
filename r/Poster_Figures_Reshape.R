# ============================================================================
# POSTER FIGURE RESHAPING SCRIPT
# Generates 2 poster-optimized figures for APJ 2026 contest
# 
# Poster dimensions: 1080w × 1920h px (portrait/vertical)
# Figure area: ~50% of poster = each figure ~480w × 340h px
# Generate at 2x resolution (960×680) for crisp rendering at 300 DPI
#
# FIGURE 1: Multi-Model ROC Curve (4 models, Spanish labels)
# FIGURE 2: SHAP Directional Impact Tornado (Top 10 variables, Spanish)
# ============================================================================

library(tidyverse)
library(yardstick)
library(pROC)

# ==============================================================================
# GLOBAL POSTER AESTHETIC SETTINGS
# ==============================================================================

# Color palette (matches poster design)
col_navy    <- "#1B3A5C"   # Primary / axes / titles
col_teal    <- "#2E86AB"   # Random Forest / ML accent
col_coral   <- "#E74C3C"   # XGBoost / risk
col_gray    <- "#7F8C8D"   # Logistic Regression (benchmark)
col_green   <- "#27AE60"   # SVM / protective
col_orange  <- "#E67E22"   # XGBoost alternative
col_light   <- "#BDC3C7"   # Grid lines
col_protect <- "#27AE60"   # Protective direction (SHAP)
col_risk    <- "#C0392B"   # Risk direction (SHAP)

# Poster-optimized theme
theme_poster <- function(base_size = 16) {
  theme_minimal(base_size = base_size) +
    theme(
      # Titles
      plot.title = element_text(
        face = "bold", size = base_size + 4, color = col_navy,
        hjust = 0.5, margin = margin(b = 4)
      ),
      plot.subtitle = element_text(
        size = base_size - 2, color = "#5D6D7E",
        hjust = 0.5, margin = margin(b = 8)
      ),
      # Axes
      axis.title = element_text(
        face = "bold", size = base_size, color = col_navy
      ),
      axis.text = element_text(
        size = base_size - 2, color = "#2C3E50"
      ),
      # Legend
      legend.position = "bottom",
      legend.text = element_text(size = base_size - 3),
      legend.title = element_blank(),
      legend.key.size = unit(0.8, "lines"),
      legend.margin = margin(t = -5),
      # Grid
      panel.grid.major = element_line(color = "#ECF0F1", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      # Plot margins (tight for poster embedding)
      plot.margin = margin(t = 8, r = 8, b = 4, l = 8)
    )
}

# ==============================================================================
# FIGURE 1: MULTI-MODEL ROC CURVE (4 models, Spanish)
# ==============================================================================
# Requirements:
#   - Load benchmark_df from Multi_Model_Comparison.R output
#   - Or load individual model predictions
# 
# Adjust the data loading section below to match your workspace
# ==============================================================================

generate_poster_roc <- function(benchmark_df) {
  
  # Define model colors and Spanish labels
  model_labels <- c(
    "Logistic Regression" = "Reg. Logística: AUC 0.877 (0.815–0.924)",
    "Random Forest"       = "Random Forest: AUC 0.860 (0.797–0.910)",
    "SVM-RBF"             = "SVM-RBF: AUC 0.856 (0.791–0.907)",
    "XGBoost"             = "XGBoost: AUC 0.814 (0.731–0.877)"
  )
  
  model_colors <- c(
    "Logistic Regression" = col_gray,
    "Random Forest"       = col_teal,
    "SVM-RBF"             = col_green,
    "XGBoost"             = col_orange
  )
  
  model_linetypes <- c(
    "Logistic Regression" = "dashed",
    "Random Forest"       = "solid",
    "SVM-RBF"             = "solid",
    "XGBoost"             = "solid"
  )
  
  # Rename models for legend
  benchmark_plot <- benchmark_df %>%
    mutate(modelo = factor(modelo,
      levels = c("Logistic Regression", "Random Forest", "SVM-RBF", "XGBoost")
    ))
  
  # Generate ROC curve data
  roc_data <- benchmark_plot %>%
    group_by(modelo) %>%
    roc_curve(desenlace, .pred_Fallecido)
  
  fig_roc <- roc_data %>%
    ggplot(aes(x = 1 - specificity, y = sensitivity, 
               color = modelo, linetype = modelo)) +
    # Diagonal reference
    geom_abline(slope = 1, intercept = 0, 
                linetype = "dotted", color = "#BDC3C7", linewidth = 0.5) +
    # ROC curves
    geom_path(linewidth = 1.2, alpha = 0.85) +
    # Colors and linetypes
    scale_color_manual(values = model_colors, labels = model_labels) +
    scale_linetype_manual(values = model_linetypes, labels = model_labels) +
    # DeLong annotation
    annotate("text", x = 0.55, y = 0.15,
             label = "RF vs Reg. Logística:\nΔAUC = −0.018, p = 0.39 (NS)",
             size = 4, color = col_navy, fontface = "italic",
             hjust = 0, lineheight = 0.9) +
    # Labels
    labs(
      title = "Comparación de Curvas ROC",
      subtitle = "Conjunto de validación interna (n = 263)",
      x = "1 − Especificidad (Falsos Positivos)",
      y = "Sensibilidad (Verdaderos Positivos)"
    ) +
    coord_equal() +
    theme_poster(base_size = 14) +
    theme(
      legend.position = "bottom",
      legend.direction = "vertical",
      legend.text = element_text(size = 11),
      legend.key.width = unit(1.5, "lines")
    ) +
    guides(color = guide_legend(ncol = 1), linetype = guide_legend(ncol = 1))
  
  # Save at 2x poster resolution
  ggsave(
    "Poster_Fig1_ROC_MultiModel.png",
    fig_roc,
    width  = 960 / 150,   # 6.4 inches at 150 DPI
    height = 760 / 150,   # 5.07 inches at 150 DPI
    dpi    = 300,          # Render at 300 DPI for crispness
    bg     = "white"
  )
  
  cat("✅ Saved: Poster_Fig1_ROC_MultiModel.png (960×760 @300DPI)\n")
  return(fig_roc)
}


# ==============================================================================
# FIGURE 2: SHAP DIRECTIONAL TORNADO (Spanish, poster-optimized)
# ==============================================================================
# This creates a clean tornado/diverging bar chart showing SHAP direction
# Uses the Top 10 variables from cross-model SHAP consensus
# ==============================================================================

generate_poster_shap_tornado <- function() {
  
  # Top 10 SHAP variables with directional impact

  # Data source: SHAP.R output (cross-model average)
  # Positive = increases mortality risk (red)
  # Negative = decreases mortality risk (green/protective)
  shap_data <- tibble(
    variable = c(
      "Severidad Clínica",
      "Disnea",
      "Fiebre",
      "Albúmina Sérica",
      "Náuseas/Vómitos",
      "Cefalea",
      "TGP (ALT)",
      "Automedicación",
      "Edad",
      "Plaquetas"
    ),
    # Average SHAP values (signed): positive = ↑mortality, negative = ↓mortality
    # These values come from Poster_5_Tornado_Promedio data
    shap_risk    = c(0.130, 0.045, 0.000, 0.000, 0.012, 0.000, 0.008, 0.000, 0.010, 0.004),
    shap_protect = c(0.000, -0.008, -0.015, -0.015, 0.000, -0.012, 0.000, -0.010, 0.000, -0.005)
  ) %>%
    mutate(variable = fct_inorder(variable) %>% fct_rev())
  
  # Reshape for diverging bar chart
  shap_long <- shap_data %>%
    pivot_longer(cols = c(shap_risk, shap_protect),
                 names_to = "direction", values_to = "impact") %>%
    filter(impact != 0) %>%
    mutate(
      direction_label = ifelse(direction == "shap_risk",
                               "Aumenta Riesgo ↑", "Disminuye Riesgo ↓"),
      direction_label = factor(direction_label,
                               levels = c("Aumenta Riesgo ↑", "Disminuye Riesgo ↓"))
    )
  
  fig_shap <- ggplot(shap_long, aes(x = impact, y = variable, fill = direction_label)) +
    geom_col(width = 0.7, alpha = 0.9) +
    geom_vline(xintercept = 0, color = col_navy, linewidth = 0.5) +
    # Colors
    scale_fill_manual(values = c(
      "Aumenta Riesgo ↑"    = col_risk,
      "Disminuye Riesgo ↓"  = col_protect
    )) +
    # Labels
    labs(
      title = "Interpretabilidad: Impacto de Variables",
      subtitle = "Contribución promedio SHAP hacia mortalidad o supervivencia",
      x = "Impacto Medio en Probabilidad (SHAP)",
      y = NULL
    ) +
    theme_poster(base_size = 14) +
    theme(
      legend.position = "bottom",
      legend.direction = "horizontal",
      legend.text = element_text(size = 12, face = "bold"),
      axis.text.y = element_text(size = 13, face = "bold"),
      panel.grid.major.y = element_blank()
    )
  
  # Save at 2x poster resolution
  ggsave(
    "Poster_Fig2_SHAP_Tornado.png",
    fig_shap,
    width  = 960 / 150,
    height = 680 / 150,
    dpi    = 300,
    bg     = "white"
  )
  
  cat("✅ Saved: Poster_Fig2_SHAP_Tornado.png (960×680 @300DPI)\n")
  return(fig_shap)
}


# ==============================================================================
# EXECUTION
# ==============================================================================

# NOTE: Uncomment and adjust the data loading to match your workspace

# --- Load your benchmark_df ---
load("~/Documents/Research/Predicción Mortalidad COVID-19 ML/COVID-19_Mortality_Prediction_ML/.RData")  # or source the comparison script
fig1 <- generate_poster_roc(benchmark_df)

# --- Generate SHAP tornado (self-contained data) ---
fig2 <- generate_poster_shap_tornado()

cat("\n")
cat("════════════════════════════════════════════════════════════════\n")
cat("  POSTER FIGURE SPECIFICATIONS\n")
cat("════════════════════════════════════════════════════════════════\n")
cat("\n")
cat("  Poster dimensions: 1080w × 1920h px (portrait)\n")
cat("\n")
cat("  Figure 1 (ROC): 960 × 760 px @ 300 DPI\n")
cat("    → Generates: Poster_Fig1_ROC_MultiModel.png\n")
cat("    → Content: 4-model ROC overlay + DeLong annotation\n")
cat("    → Key: LogReg shown as dashed line (benchmark)\n")
cat("\n")
cat("  Figure 2 (SHAP): 960 × 680 px @ 300 DPI\n")
cat("    → Generates: Poster_Fig2_SHAP_Tornado.png\n")
cat("    → Content: Directional tornado chart, Top 10 variables\n")
cat("    → Key: Red = ↑mortality, Green = ↓mortality\n")
cat("\n")
cat("  INSTRUCTIONS:\n")
cat("    1. Source this script in your R session with loaded workspace\n")
cat("    2. Run generate_poster_roc(benchmark_df)\n")
cat("    3. Run generate_poster_shap_tornado()\n")
cat("    4. Copy output PNGs to poster working directory\n")
cat("════════════════════════════════════════════════════════════════\n")

print(fig1)