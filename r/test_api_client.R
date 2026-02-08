library(httr)
library(jsonlite)

print("Sending request to API...")
response <- POST(
  "http://localhost:8000/predict",
  body = list(
    edad = 65,
    sexo = "hombre",
    severidad_sars = "Severo",
    albumina = 3.2,
    plaquetas = 150000,
    bilirrtotal = 1.2,
    sxingr_disnea = TRUE,
    sxingr_cefalea = FALSE
  ),
  encode = "json"
)

if (status_code(response) == 200) {
  result <- content(response)
  print("--- API RESPONSE ---")
  print(paste("Risk Score:", result$risk_percentage, "%"))
  print(paste("Risk Level:", result$risk_level))
  print(paste("Threshold Note:", result$threshold_info$note))
  print(paste("Imputation Method:", result$imputation_diagnostics$method))
  print("Parameters Used:")
  print(names(result$explanation))
} else {
  print(paste("Error:", status_code(response)))
  print(content(response, "text"))
}
