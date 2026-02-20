# ==== CONFIGURACIÓN ESTÉTICA GLOBAL (EJECUTAR PRIMERO) ====

library(tidyverse)

# Definimos la paleta y el tema una sola vez para asegurar hegemonía absoluta
col_modelo <- "#004E89"  # Azul Institucional (Tu modelo)
col_rival  <- "#7F8C8D"  # Gris (Modelos rivales/Logística)
col_riesgo <- "#C0392B"  # Rojo (Peligro/Muerte)
col_prot   <- "#27AE60"  # Verde (Protección/Vida)

# Tema base unificado
theme_poster <- function() {
  theme_minimal(base_size = 14) + # Subimos la base de 12 a 14
    theme(
      plot.title = element_text(face = "bold", size = 18, color = "#2C3E50"),
      plot.subtitle = element_text(size = 14, color = "#7F8C8D", margin = margin(b = 15)),
      axis.title = element_text(face = "bold", size = 15, color = "#34495E"),
      axis.text = element_text(size = 14, color = "black"), # Texto ejes negro y grande
      legend.position = "bottom",
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "grey92")
    )
}

# ==== 1.1 ROC CURVE (VALIDACIÓN DISCRIMINANTE) ====

benchmark_df_esp <- benchmark_df %>%
  mutate(modelo = case_when(
    modelo == "Random Forest (Proposed)" ~ "Modelo basado en ML",
    modelo == "Regresión Logística (Standard)" ~ "Regresión Logística Multivariada",
    TRUE ~ modelo
  ))

fig_roc <- benchmark_df_esp %>%
  group_by(modelo) %>%
  roc_curve(desenlace, .pred_Fallecido) %>%
  ggplot(aes(x = 1 - specificity, y = sensitivity, color = modelo)) +
  
  # A. ZONA DE SCORES CLÍNICOS
  annotate("rect", xmin=0, xmax=0.4, ymin=0.4, ymax=0.75, 
           alpha=0.1, fill="grey50") +
  annotate("text", x=0.25, y=0.55, label="Modelos Tradicionales\n(AUC promedio = 0.695)", 
           color="grey40", size=5, fontface="italic") +
  
  # B. LÍNEAS
  geom_path(linewidth = 1.5, alpha = 0.8) +
  geom_abline(lty = 3, color = "grey") +
  
  # C. COLORES
  scale_color_manual(values = c("Modelo basado en ML" = col_modelo, 
                                "Regresión Logística Multivariada" = col_rival)) +
  
  # D. TÍTULOS 
  labs(title = "1A. Validación de Capacidad de Discriminación (ROC)",
       subtitle = "Superioridad frente a estándares clínicos y paridad estadística con regresión logística",
       x = "1 - Especificidad (Falsos Positivos)",
       y = "Sensibilidad (Verdaderos Positivos)") +
  
  theme_poster() +
  theme(legend.position = c(0.7, 0.2), 
        legend.background = element_rect(fill = "white", color = NA),
        legend.text = element_text(size = 15),
        legend.title = element_blank())

print(fig_roc)

# Guardar
ggsave("Poster_1_ROC_Final.png", fig_roc, width = 12, height = 8, dpi = 300)

# ==== 1.2 DECISION CURVE ANALYSIS (DCA) ====

dca_final_esp <- dca_calculado %>%
  mutate(label = case_when(
    label == "Random Forest" ~ "Modelo basado en ML",
    label == "Treat All" ~ "Estrategia: Tratar a Todos",
    label == "Treat None" ~ "Estrategia: No Tratar",
    TRUE ~ label
  ))

fig_dca <- ggplot(dca_final_esp, aes(x = threshold, y = net_benefit, color = label)) +
  
  # A. ZONA DE UTILIDAD
  annotate("rect", xmin=0.10, xmax=0.45, ymin=-0.05, ymax=0.15, 
           fill=col_modelo, alpha=0.05) +
  
  # B. LÍNEAS
  geom_line(linewidth = 1.2) +
  
  # C. COLORES
  scale_color_manual(values = c("Modelo basado en ML" = col_modelo, 
                                "Estrategia: Tratar a Todos" = col_riesgo, 
                                "Estrategia: No Tratar" = col_rival)) +
  
  scale_x_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 0.5)) +
  coord_cartesian(ylim = c(-0.05, 0.18)) +
  
  # D. TÍTULOS (Sin "1B")
  labs(title = "Beneficio Clínico Neto (DCA)",
       subtitle = "El modelo ofrece mayor beneficio neto en el rango de triaje crítico (10-45%)",
       x = "Umbral de Riesgo", 
       y = "Beneficio Neto Clínico") +
  
  theme_poster() +
  theme(legend.position = c(0.75, 0.85),
        legend.background = element_rect(fill = "white", color = "grey90"),
        legend.text = element_text(size = 15),
        legend.title = element_blank())

print(fig_dca)

# Guardar
ggsave("Poster_2_DCA_Final.png", fig_dca, width = 12, height = 8, dpi = 300)

# ==== 1.3 CALIBRATION CURVE (SEGURIDAD) ====

# Nota: Asumimos que 'cal_plot' viene de 'probably' y es un ggplot base
fig_cal <- cal_plot +
  labs(title = "Seguridad del Modelo (Calibración)",
       subtitle = "Alta concordancia (línea ideal) en zona de bajo riesgo, ideal para descarte",
       x = "Probabilidad Predicha", y = "Tasa de Eventos Observada") +
  
  annotate("rect", xmin = 0, xmax = 0.30, ymin = 0, ymax = 1, 
           fill = col_prot, alpha = 0.15) +
  
  annotate("text", x = 0.15, y = 0.85, 
           label = "ZONA DE\nALTA FIABILIDAD\n(Alta Segura)", 
           color = "#1E8449", fontface = "bold", size = 5, lineheight = 0.9) +
  
  theme_poster() +
  theme(panel.grid.major = element_line(color = "grey92"))

print(fig_cal)

# Guardar
ggsave("Poster_3_Calibration_FINAL.png", fig_cal, width = 12, height = 8, dpi = 300)


# ==== 1.4 SHAP GLOBAL IMPORTANCE (RANKING) ====

df_importancia <- vip_plot$data 
df_importancia_esp <- df_importancia %>%
  mutate(Variable = case_when(
    Variable == "severidad_sars_Severo" ~ "Severidad Clínica: Severo",
    Variable == "severidad_sars_Moderado" ~ "Severidad Clínica: Moderado",
    Variable == "automed_paracetamol_TRUE." ~ "Automedicación con Paracetamol",
    Variable == "albumina" ~ "Albúmina Sérica",
    Variable == "edad" ~ "Edad",
    Variable == "inr" ~ "INR",
    Variable == "sxingr_disnea_TRUE." ~ "Disnea",
    Variable == "sxingr_tos_TRUE." ~ "Tos",
    Variable == "ant_dm_TRUE." ~ "Diabetes Mellitus",
    Variable == "imc" ~ "IMC",
    Variable == "log_plaquetas" ~ "Conteo de Plaquetas",
    Variable == "sxingr_cefalea_TRUE." ~ "Cefalea",
    Variable == "sxingr_odinofagia_TRUE." ~ "Odinofagia",
    Variable == "sxingr_dolorgarganta_TRUE." ~ "Dolor de garganta",
    Variable == "sexo_mujer" ~ "Sexo",
    TRUE ~ Variable 
  ))

fig_shap_global <- ggplot(df_importancia_esp, aes(x = Importance, y = reorder(Variable, Importance))) +
  
  geom_col(fill = col_modelo, alpha = 0.85, width = 0.7) + 
  
  geom_text(aes(label = round(Importance, 3)), 
            hjust = -0.2, size = 5, color = "grey30") + # Size 5 para que se lea bien
  
  labs(title = "Interpretabilidad: Predictores de Mortalidad",
       subtitle = "Ranking de variables con mayor impacto predictivo",
       x = "Importancia Relativa", 
       y = "") +
  
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  
  theme_poster() +
  theme(
    axis.text.y = element_text(face = "bold", size = 15, color = "#2C3E50"), 
    panel.grid.major.y = element_blank()
  )

print(fig_shap_global)

# Guardar (Ancho 13 para dar espacio a nombres largos)
ggsave("Poster_4_SHAPGlobal_FINAL.png", fig_shap_global, width = 13, height = 8, dpi = 300)

# ==== 1.5 SHAP DIRECTIONAL (TORNADO) ====

datos_tornado <- shap_values %>%
  as.data.frame() %>%
  filter(variable != "_baseline_") %>%
  mutate(
    var_raw = as.character(variable),
    var_clean = case_when(
      var_raw == "severidad_sars = Moderado" ~ "Severidad Clínica",
      var_raw == "sxingr_disnea = FALSE" ~ "Disnea",
      var_raw == "sxingr_fiebre = FALSE" ~ "Fiebre",
      var_raw == "albumina = 2.71" ~ "Albúmina",
      var_raw == "sxingr_nauseavomito = TRUE" ~ "Náuseas/Vómitos",
      var_raw == "automed_paracetamol = FALSE" ~ "Automedicación",
      var_raw == "edad = 54" ~ "Edad",
      var_raw == "plaquetas = 458000" ~ "Plaquetas",
      var_raw == "sxingr_cefalea = FALSE" ~ "Cefalea",
      var_raw == "tgp = 101" ~ "TGP (ALT)",
      
      
      TRUE ~ str_to_title(str_replace_all(var_raw, "_", " "))
    )
  ) %>%
  group_by(var_clean) %>%
  summarise(
    mean_risk = mean(contribution[contribution > 0], na.rm = TRUE),
    mean_prot = mean(contribution[contribution < 0], na.rm = TRUE),
    total_importance = mean(abs(contribution))
  ) %>%
  mutate(
    mean_risk = ifelse(is.na(mean_risk), 0, mean_risk),
    mean_prot = ifelse(is.na(mean_prot), 0, mean_prot)
  ) %>%
  arrange(desc(total_importance)) %>%
  slice_head(n = 10) %>%
  tidyr::pivot_longer(cols = c(mean_risk, mean_prot), 
                      names_to = "Tipo", 
                      values_to = "Impacto_Medio") %>%
  mutate(
    Direccion = ifelse(Tipo == "mean_risk", "Aumenta Riesgo", "Disminuye Riesgo"),
    var_clean = fct_reorder(var_clean, total_importance)
  )

fig_tornado <- ggplot(datos_tornado, aes(x = Impacto_Medio, y = var_clean, fill = Direccion)) +
  
  geom_vline(xintercept = 0, color = "grey40", linewidth = 1) +
  geom_vline(xintercept = -0.05, color = "grey92", linetype = "dashed") +
  
  geom_col(width = 0.7, alpha = 0.9) +
  
  scale_fill_manual(values = c("Aumenta Riesgo"   = col_riesgo, 
                               "Disminuye Riesgo" = col_prot)) +
  
  labs(title = "Impacto Direccional de Variables",
       subtitle = "Contribución media hacia mortalidad (rojo) o supervivencia (verde)",
       x = "Impacto Medio en la Probabilidad (SHAP)",
       y = "") +
  
  scale_x_continuous(labels = function(x) sprintf("%.2f", abs(x))) +
  
  theme_poster() +
  theme(
    legend.position = "bottom",
    axis.text.y = element_text(size = 15, face = "bold", color = "#2C3E50"), 
    plot.margin = margin(10, 20, 10, 10)
  )

print(fig_tornado)

# Guardar
ggsave("Poster_5_Tornado_Promedio.png", fig_tornado, width = 13, height = 8, dpi = 300)

# ==== 2. PANELS ====

library(ggplot2)
library(cowplot)
library(magick)

# 1. CARGAR LAS IMÁGENES GENERADAS
# Panel 1 (Validación)
img_roc <- "Poster_1_ROC_Final.png"
img_dca <- "Poster_2_DCA_Final.png"
img_cal <- "Poster_3_Calibration_FINAL.png"

# Panel 2 (Explicabilidad)
img_global <- "Poster_4_SHAPGlobal_FINAL.png"
img_local  <- "Poster_5_Tornado_Promedio.png"

# Función de lectura
leer <- function(ruta) ggdraw() + draw_image(ruta, scale = 1)

# Leemos las imágenes
p_roc <- leer(img_roc)
p_dca <- leer(img_dca)
p_cal <- leer(img_cal)
p_global <- leer(img_global)
p_local  <- leer(img_local)

# FIGURA 1: VALIDACIÓN MULTIDIMENSIONAL

library(cowplot)

panel_1_final <- plot_grid(
  p_roc, p_dca,
  ncol = 1, 
  labels = c('1A', "1B"), 
  label_size = 12,
  label_fontfamily = "sans",
  label_x = 0.05,  # Mueve la etiqueta un 2% hacia la derecha (acercándola al gráfico)
  label_y = 1,  # La baja un 2% para que no corte el margen superior
  hjust = 0,       # Justificación izquierda (para que el texto empiece en esa posición)
  align = "v",     # Alinea verticalmente los gráficos (vital si tienen ejes de distinto ancho)
  axis = "l"       # Alinea basado en el eje izquierdo
)

print(panel_1_final)

# Guardar Figura 1
ggsave("FIGURA_1_VALIDACION_FINAL.png", panel_1_final, 
       width = 8, height = 10, dpi = 300)

# FIGURA 2: EXPLICABILIDAD (XAI)

panel_2_final <- plot_grid(
  p_global, p_local,
  ncol = 1,
  labels = c("2A", "2B"),   # A = Tornado, B = Waterfall
  label_size = 12,
  label_fontfamily = "sans",
  rel_heights = c(1, 1),
  label_x = 0.18,  # Mueve la etiqueta un 2% hacia la derecha (acercándola al gráfico)
  label_y = 1,  # La baja un 2% para que no corte el margen superior
  hjust = 0,       # Justificación izquierda (para que el texto empiece en esa posición)
  align = "v",     # Alinea verticalmente los gráficos (vital si tienen ejes de distinto ancho)
  axis = "l"# Waterfall un poco más alto para que quepan las etiquetas
)

print(panel_2_final)

# Guardar Figura 2
ggsave("FIGURA_2_XAI_FINAL.png", panel_2_final, 
       width = 12, height = 10, dpi = 300)
