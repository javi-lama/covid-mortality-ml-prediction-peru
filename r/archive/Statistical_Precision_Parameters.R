# ==== CONFIDENCE INTERVAL FOR ROC-AUC ====

# Library:
library(pROC)

# A. Prepare objects ROC and pROC
roc_rf <- roc(response = df_testing$desenlace, 
              predictor = test_preds$.pred_Fallecido,
              levels = c("Vivo", "Fallecido"))

# B. Calculating IC 95% by Bootstrapinng x 2000
ci_rf <- ci.auc(roc_rf, method = "bootstrap", boot.n = 2000)

print(ci_rf) # 95% CI: 0.8168-0.9179

# Complete report:
auc_valor <- round(ci_rf[2], 3)
ci_lower <- round(ci_rf[1], 3)
ci_upper <- round(ci_rf[3], 3)

print(paste("AUC = ", auc_valor, " (95% CI: ", ci_lower, " - ", ci_upper, ")"))
# "AUC =  0.873  (95% CI:  0.817  -  0.918 )"

# ==== HYPOTHESIS TEST: ML vs. GLM ====

# A. Preparing ROC object of GLM
roc_glm <- roc(response = df_testing$desenlace, 
               predictor = glm_preds$.pred_Fallecido,
               levels = c("Vivo", "Fallecido"))

# B. DeLong test for comparing ROC between ML vs. GLM
test_delong <- roc.test(roc_rf, roc_glm, method = "delong")

print(test_delong)
# Z = 0.060913, p-value = 0.9514

# ==== IC 95% FOR DIAGNOSTIC PARAMETERS OF ML MODEL ====

# Security threshold
threshold_obj <- coords(roc_rf, x = "best", best.method = "youden", 
                        ret = c("threshold", "sensitivity", "specificity", "npv", "ppv"),
                        transpose = FALSE)

# Calculating CI 95% for parameters:
metrics_ci <- ci.coords(roc_rf, x = "best", best.method = "youden",
                        ret = c("sensitivity", "specificity", "npv", "ppv"),
                        boot.n = 2000)

print(metrics_ci)

# Youden cut-off for 90% sensibility:
best_coords <- coords(roc_rf, "best", best.method = "youden", 
                      ret = c("threshold", "sensitivity", "specificity", "npv"))

print(best_coords)

# ==== CALIBRATION PLOT ====

# Library:
library(probably)
library(tidyverse)

cal_plot <- test_preds %>%
  cal_plot_breaks(truth = desenlace, estimate = .pred_Fallecido, num_breaks = 10) +
  ggtitle("Curva de Calibración", subtitle = "Eje Ideal (Punteada) vs. Predicción Real (Línea)") +
  theme_minimal()

print(cal_plot)
