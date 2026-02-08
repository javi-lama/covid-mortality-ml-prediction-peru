# APP INTERACTIVA: COVID-19 MORTALITY PREDICTOR (en SHINY)

library(shiny)
library(tidymodels)
library(ranger)
library(shinythemes)

# 2. INTERFAZ DE USUARIO (UI)
ui <- fluidPage(
  theme = shinytheme("flatly"), # Tema médico/limpio
  
  titlePanel("Predictor de Mortalidad Intrahospitalaria COVID-19 para población peruna"),
  
  sidebarLayout(
    sidebarPanel(
      h4("Datos del Paciente al Ingreso"),
      helpText("Ingrese los valores fisiológicos y clínicos."),
      
      # INPUTS (Variables clave del modelo)
      numericInput("edad", "Edad (años):", value = 57, min = 18, max = 100),
      selectInput("sexo", "Sexo:", choices = c("hombre", "mujer")),
      selectInput("severidad_sars", "Severidad Clínica:", 
                  choices = c("Leve", "Moderado", "Severo"), selected = "Moderado"),
      
      hr(),
      h5("Biomarcadores"),
      numericInput("albumina", "Albúmina (g/dL):", value = 3.5, step = 0.1),
      numericInput("plaquetas", "Plaquetas:", value = 250000),
      numericInput("bilirrtotal", "Bilirrubina Total:", value = 0.8, step = 0.1),
      
      hr(),
      h5("Síntomas Clave"),
      checkboxInput("sxingr_disnea", "¿Presenta Disnea?", value = TRUE),
      checkboxInput("sxingr_cefalea", "¿Presenta Cefalea?", value = FALSE),
      
      br(),
      actionButton("predecir", "CALCULAR RIESGO", class = "btn-primary btn-lg", width = "100%")
    ),
    
    mainPanel(
      # RESULTADOS
      div(style = "text-align: center; margin-top: 50px;",
          h2("Resultado del Análisis"),
          hr(),
          uiOutput("resultado_texto"),
          br(),
          uiOutput("barra_progreso"),
          br(),
          div(style = "background-color: #f8f9fa; padding: 20px; border-radius: 10px;",
              h4("Interpretación del Modelo:"),
              p("Este modelo prioriza el Valor Predictivo Negativo (92%)."), 
              p("Riesgo < 20% sugiere alta probabilidad de supervivencia (Candidato a Alta Segura)."),
              small("Nota: Herramienta de investigación. No sustituye el juicio médico.")
          )
      )
    )
  )
)

# 3. LÓGICA DEL SERVIDOR
server <- function(input, output) {
  
  observeEvent(input$predecir, {
    
    # A. Crear Dataframe con los inputs (Igual estructura que tu df_training)
    # Nota: Aquí debes asegurarte de crear TODAS las columnas que el modelo espera.
    # Rellenamos las no-críticas con valores moda/media para que no falle.
    
    new_patient <- tibble(
      edad = input$edad,
      sexo = input$sexo,
      severidad_sars = input$severidad_sars,
      albumina = input$albumina,
      plaquetas = input$plaquetas,
      bilirrtotal = input$bilirrtotal,
      
      # Lógicos convertidos a factores o lógicos según tu entrenamiento original
      # Ajusta esto según cómo quedó tu df_training final
      sxingr_disnea = input$sxingr_disnea, 
      sxingr_cefalea = input$sxingr_cefalea,
      
      # Relleno de variables secundarias (Asumimos moda/negativo para simplificar demo)
      automed_paracetamol = FALSE,
      ant_dm = FALSE,
      inr = 1.0, 
      # ... agrega aquí el resto de columnas necesarias con valores default ...
      # TRUCO: Si usaste receta, la receta manejará transformaciones (log, ratios)
    )
    
    # B. Predecir
    pred_prob <- predict(final_model_workflow, new_patient, type = "prob")$.pred_Fallecido
    riesgo_porcentaje <- round(pred_prob * 100, 1)
    
    # C. Renderizar Salida
    output$resultado_texto <- renderUI({
      color <- if(riesgo_porcentaje < 20) "green" else if(riesgo_porcentaje < 50) "orange" else "red"
      mensaje <- if(riesgo_porcentaje < 20) "BAJO RIESGO (Alta Segura Probable)" else "RIESGO ELEVADO"
      
      h1(paste0(riesgo_porcentaje, "%"), style = paste0("color: ", color, "; font-weight: bold; font-size: 60px;"))
    })
    
    output$barra_progreso <- renderUI({
      color_bar <- if(riesgo_porcentaje < 20) "success" else if(riesgo_porcentaje < 50) "warning" else "danger"
      HTML(paste0(
        '<div class="progress" style="height: 30px;">
           <div class="progress-bar bg-', color_bar, '" role="progressbar" style="width: ', riesgo_porcentaje, '%;" 
           aria-valuenow="', riesgo_porcentaje, '" aria-valuemin="0" aria-valuemax="100"></div>
         </div>'
      ))
    })
  })
}

shinyApp(ui = ui, server = server)