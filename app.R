# R Shiny app to predict POC flux from PSD and depth
# Margaux Perhirin (14 September 2026) — Version NetCDF CF-1.8 & Modèle Pré-entraîné

# Librairies
library(shiny)
library(bslib)
library(xgboost)
library(terra)
library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)
library(maps)

# Use the same port for local and containerized launches.
options(shiny.port = 3838)

# Constants
R_EARTH <- 6371000 # Earth radius in meters
DAYS_IN_MONTH <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)

# Automatically download the model (not in the container because too heavy)
if (!file.exists("data/model_pack.rds")) {
  dir.create("data", showWarnings = FALSE)
  download.file(
    url = "https://minio.dive.edito.eu/oidc-margauxperhir1/data/model_pack.rds",
    destfile = "data/model_pack.rds",
    mode = "wb"
  )
}

MODEL_PACK <- readRDS("data/model_pack.rds")

# Read the NetCDF file
load_coefs_from_nc <- function(nc_path, months_sel, lat_range, lon_range) {
  terms <- c("Intercept", "Linear", "Quadratic")
  ext_user <- ext(lon_range[1], lon_range[2], lat_range[1], lat_range[2])
  
  # Read variable by variable via sub datasets (subds)
  r_list <- lapply(terms, function(t) {
    # Load the 3D variables (12 layers = 12 months)
    r_var <- rast(nc_path, subds = t)
    names(r_var) <- paste0(t, "_month_", 1:12)
    
    # Select for the required months
    keep_layers <- paste0(t, "_month_", months_sel)
    r_sub_m <- subset(r_var, keep_layers)
    
    # Spatial crop
    r_crop <- crop(r_sub_m, ext_user)
    return(r_crop)
  })
  
  # Merge everything in an unique SpatRaster
  r_combined <- do.call(c, r_list)
  
  # Convert it in a dataset
  df_raw <- as.data.frame(r_combined, xy = TRUE)
  if (nrow(df_raw) == 0) return(data.frame())
  
  colnames(df_raw)[1:2] <- c("longitude", "latitude")
  
  # Transform it in long format and remove missing values
  df_long <- df_raw %>%
    pivot_longer(cols = -c(longitude, latitude), names_to = "var_month", values_to = "predictedvalue") %>%
    filter(!is.na(predictedvalue) & predictedvalue != -9999) %>%
    mutate(term = sub("_month_.*", "", var_month),
           month = as.numeric(sub(".*_month_", "", var_month))) %>%
    dplyr::select(longitude, latitude, month, term, predictedvalue)
  
  return(df_long)
}

# Compute global POC flux [Pg C year-1]
calc_global_flux_bootstrap <- function(preds_log_matrix, df_spatial) {
  weights <- df_spatial %>%
    mutate(lat_rad = latitude * pi / 180,
           area_m2 = (R_EARTH^2) * (pi / 180)^2 * cos(lat_rad),
           n_days = DAYS_IN_MONTH[month],
           w_cell = (area_m2 * n_days) / 1e18) %>% # From mg C to Pg C
    pull(w_cell)
  
  preds_real_matrix <- exp(preds_log_matrix) # In mgC m-2 d-1
  global_flux_dist  <- colSums(preds_real_matrix * weights, na.rm = TRUE) # In PgC y-1
  
  data.frame(mean = mean(global_flux_dist),
             sd = sd(global_flux_dist),
             median = median(global_flux_dist),
             q2.5 = quantile(global_flux_dist, 0.025, names = FALSE),
             q97.5 = quantile(global_flux_dist, 0.975, names = FALSE))
}

# Fond de carte
map_bck <- ggplot() +
  geom_polygon(data = map_data("world"), aes(x = long, y = lat, group = group),
               fill = "#E8E8E8", color = "grey90", linewidth = 0.3) +
  theme_bw() +
  theme(panel.grid.major = element_line(color = "#D0D0D0", linetype = "dotted", linewidth = 0.4),
        panel.grid.minor = element_blank(),
        panel.background = element_blank(),
        axis.text = element_text(size = 10, color = "gray20"),
        axis.ticks = element_blank(),
        legend.position = "bottom")

# 1. USER INTERFACE (UI) ===========
ui <- fluidPage(
  theme = bs_theme(bootswatch = "flatly", primary = "#2C3E50"),
  
  tags$head(
    tags$style(HTML("
      .nav-tabs .nav-link, .nav-tabs > li > a { color: #8fb9e5 !important; font-weight: 600; }
      .nav-tabs .nav-link.active, .nav-tabs > li.active > a { color: #2C3E50 !important; border-bottom: 3px solid #8fb9e5 !important; }
      #btn_download { background-color: #8fb9e5 !important; border-color: #8fb9e5 !important; color: white !important; }
      .metric-box { background-color: #f8f9fa; border-left: 5px solid #2C3E50; padding: 15px; margin-bottom: 15px; border-radius: 4px; }
    "))
  ),
  
  # En-tête
  fluidRow(
    style = "padding: 15px 0px; align-items: center;",
    column(7,
           h2("Particulate Organic Carbon (POC) flux prediction from Particle Size Distribution (PSD)", style = "color: #3d547c; font-weight: bold; margin-bottom: 5px;"),
           h5("Margaux Perhirin, Virginie Sonnet, Hervé Claustre, Jean-Olivier Irisson, Corentin Clerc, Simon Ramondenc, Lionel Guidi", style = "color: #5d83c2; margin-top: 0px;")
    ),
    column(5,
           div(style = "display: flex; justify-content: flex-end; align-items: center; gap: 15px;",
               tags$img(src = "LogoDTO-BioflowPositivesmall.png", style = "max-height: 100px; max-width: 48%; object-fit: contain;"),
               tags$img(src = "DUC7_newIcon.jpg", style = "max-height: 75px; max-width: 48%; object-fit: contain;"))
    )
  ),
  
  hr(),
  
  sidebarLayout(
    sidebarPanel(
      width = 3,
      h4("1. Prediction parameters"),
      
      selectizeInput("selected_months", "Select months (1-12):", choices = 1:12, selected = 1:12, multiple = TRUE),
      numericInput("target_depth", "Target depth (m):", value = 150, min = 100, max = 1500, step = 10),
      numericInput("n_boot", "Bootstrap iterations:", value = 30, min = 10, max = 200, step = 5),
      
      hr(),
      h4("2. Spatial Bounding Box"),
      sliderInput("lat_range", "Latitude range (°N):", min = -90, max = 90, value = c(-90, 90), step = 5),
      sliderInput("lon_range", "Longitude range (°E):", min = -180, max = 180, value = c(-180, 180), step = 5),
      
      hr(),
      h4("3. Display options"),
      radioButtons("display_mode", "Representation:", choices = c("Annual mean" = "annual", "Per month" = "monthly"), selected = "annual"),
      
      hr(),
      actionButton("btn_run", "Run the model", class = "btn-primary", width = "100%", icon = icon("play")),
      
      hr(),
      downloadButton("btn_download", "Download results (CSV)", style = "width: 100%;")
    ),
    
    mainPanel(
      width = 9,
      tabsetPanel(
        # Tab 1: Global Flux + Carte
        tabPanel("Global POC Flux", icon = icon("globe"), br(),
                 wellPanel(uiOutput("box_integrated_flux"),
                           hr(),
                           h4(textOutput("map_title")),
                           h5(textOutput("map_subtitle"), class = "text-muted"),
                           plotOutput("plot_map", height = "550px"))
        ),
        
        # Tab 2: PSD coefficients 
        tabPanel("PSD coefficients", icon = icon("sliders"), br(),
                 wellPanel(
                   fluidRow(
                     column(4, selectInput("psd_term", "Select PSD coefficient:", choices = c("Intercept", "Linear", "Quadratic"), selected = "Linear"))
                   ),
                   h4(textOutput("psd_map_title")),
                   h5(textOutput("psd_map_subtitle"), class = "text-muted"),
                   plotOutput("plot_psd_map", height = "550px")
                 )
        ),
        
        # Tab 3: Performances
        tabPanel("Performances & Importance", icon = icon("chart-line"), br(),
                 fluidRow(
                   column(6, wellPanel(h4("Performances of XGBoost (test set)"), tableOutput("table_metrics"))),
                   column(6, wellPanel(h4("Best parameters"), tableOutput("table_params")))
                 ),
                 fluidRow(
                   style = "margin-top: 20px;",
                   column(6, wellPanel(h4("Observed vs predicted (test set)"), plotOutput("plot_obs_vs_pred", height = "300px"))),
                   column(6, wellPanel(h4("Predictor importance"), plotOutput("plot_importance", height = "300px")))
                 )
        ),
        
        # Tab 4: Results preview
        tabPanel("Result preview", icon = icon("table"), br(),
                 wellPanel(
                   h4("Variable descriptions & units"),
                   div(
                     style = "line-height: 1.6; margin-bottom: 20px; color: #2C3E50;",
                     p("This table displays the first 10 rows of the dataset generated by the model according to your selected months, depth, and spatial bounds:"),
                     tags$ul(
                       tags$li(tags$b("latitude"), " [°N] : Geographic latitude coordinate (-90° to 90°)."),
                       tags$li(tags$b("longitude"), " [°E] : Geographic longitude coordinate (-180° to 180°)."),
                       tags$li(tags$b("month"), " [1-12] : Month of the year."),
                       tags$li(tags$b("depth"), " [m] : Selected target depth in the water column."),
                       tags$li(tags$b("flux_pred"), " [mg C m⁻² d⁻¹] : Predicted gravitational Particulate Organic Carbon (POC) flux at the selected depth."),
                       tags$li(tags$b("flux_sd"), " [mg C m⁻² d⁻¹] : Standard deviation (uncertainty) of the predicted gravitational POC flux at the selected depth, derived from bootstrap iterations.")
                     )
                   ),
                   hr(),
                   h4("Top of predicted data"),
                   tableOutput("table_preview")
                 )
        )
      )
    )
  ),
  
  hr(style = "margin-top: 40px;"),
  div(
    style = "font-size: 0.82em; color: #666666; text-align: center; margin-top: 15px; margin-bottom: 25px; line-height: 1.4;",
    p("This study and this application were produced by the DTO-BioFlow project (GA No. 101112823), which received funding from the European Union’s Horizon Programme call HORIZON-MISS-2022-OCEAN-01."),
    p("The content of this document does not represent the opinion of the European Commission, and the European Commission is not responsible for any use that might be made of such content.")
  )
)

# 2. SERVER ==========
server <- function(input, output, session) {
  
  model_res <- eventReactive(input$btn_run, {
    req(input$selected_months)
    validate(need(input$target_depth >= 100 && input$target_depth <= 1500, "Target depth must be between 100 and 1500 m."),
             need(input$n_boot >= 10, "Bootstrap iterations must be >= 10."))
    
    sel_months <- as.numeric(input$selected_months)
    
    withProgress(message = "Reading NetCDF coefficients...", value = 0.2, {
      
      # 1. Download coefficients from the NetCDF file
      coefs_df <- load_coefs_from_nc(nc_path = "data/argoecokiko_predictions.nc",
                                     months_sel = sel_months,
                                     lat_range = input$lat_range,
                                     lon_range = input$lon_range)
      
      validate(need(nrow(coefs_df) > 0, "No data available in the selected spatial region and months."))
      
      incProgress(0.3, detail = "Formatting prediction data...")
      
      target_depth_val <- input$target_depth
      psd_base <- coefs_df %>%
        filter(!is.na(term)) %>%
        pivot_wider(names_from = "term", values_from = predictedvalue) %>%
        drop_na(Intercept, Linear, Quadratic) %>%
        mutate(depth = target_depth_val)
      
      feats <- c("Intercept", "Linear", "Quadratic", "depth")
      df_target <- psd_base %>% dplyr::select(all_of(feats)) %>% as.matrix()
      
      incProgress(0.3, detail = "Predicting with pre-trained XGBoost...")
      
      # Ponctual prediction
      psd_base$flux_pred <- exp(predict(MODEL_PACK$final_model, df_target))
      
      # Bootstrap
      B_iter <- min(input$n_boot, length(MODEL_PACK$boot_models))
      preds_log_matrix <- matrix(NA_real_, nrow = nrow(df_target), ncol = B_iter)
      
      for (b in seq_len(B_iter)) {
        preds_log_matrix[, b] <- predict(MODEL_PACK$boot_models[[b]], df_target)
      }
      
      sd_log <- apply(preds_log_matrix, 1, sd)
      mean_log <- apply(preds_log_matrix, 1, mean)
      psd_base$flux_sd <- exp(mean_log + sd_log) - exp(mean_log)
      
      # 2. Compute global POC flux [Pg C y-1]
      global_flux_summary <- calc_global_flux_bootstrap(preds_log_matrix, psd_base)
      
      setProgress(1, detail = "Done !")
      
      list(predictions = psd_base,
           coefs_data = coefs_df,
           global_flux_summary = global_flux_summary,
           target_depth = target_depth_val,
           selected_months = sel_months,
           lat_range = input$lat_range,
           lon_range = input$lon_range)
    })
  })
  
  subtitle_txt <- function() {
    res <- model_res()
    months_str <- paste(sort(res$selected_months), collapse = ", ")
    mode_str <- if (input$display_mode == "annual") "Annual mean" else "Per month"
    paste0(mode_str, " on months n°", months_str, " | Lat: [", res$lat_range[1], "°, ", res$lat_range[2], "°] | Lon: [", res$lon_range[1], "°, ", res$lon_range[2], "°]")
  }
  
  # Stat summary of global POC flux
  output$box_integrated_flux <- renderUI({
    res <- model_res()
    s <- res$global_flux_summary
    
    div(class = "metric-box",
        h4(style = "color: #2C3E50; margin-top: 0;", "Integrated POC Flux in the selected area, at the selected depth and over the selected period"),
        p(style = "font-size: 1.25em; font-weight: bold; margin-bottom: 5px;",
          sprintf("Mean ± standard deviation: %.3f ± %.3f Pg C y⁻¹", s$mean, s$sd)
        ),
        p(style = "color: #555; margin-bottom: 0;",
          sprintf("Median: %.3f Pg C y⁻¹ | 95%% CI: [%.3f ; %.3f] Pg C y⁻¹", s$median, s$q2.5, s$q97.5)
        )
    )
  })
  
  # Map of POC flux
  output$map_title <- renderText({ paste0("Global POC flux map at ", model_res()$target_depth, " m") })
  output$map_subtitle <- renderText(subtitle_txt())
  
  output$plot_map <- renderPlot({
    res <- model_res()
    pred_df <- res$predictions
    
    if (input$display_mode == "annual") {
      d <- pred_df %>% 
        group_by(latitude, longitude) %>% 
        summarise(flux = mean(flux_pred, na.rm = TRUE), .groups = "drop")
    } else {
      d <- pred_df %>% rename(flux = flux_pred)
    }
    
    p <- map_bck +
      geom_raster(data = d, aes(x = longitude, y = latitude, fill = flux)) +
      scale_fill_viridis_c(name = "POC [mg m⁻² d⁻¹]", na.value = "white", limits = c(0, NA)) +
      scale_x_continuous(limits = res$lon_range, expand = expansion(0, 0)) +
      scale_y_continuous(limits = res$lat_range, expand = expansion(0, 0)) +
      labs(x = "Longitude [°E]", y = "Latitude [°N]") +
      coord_equal()
    
    if (input$display_mode == "annual") {
      p + theme_bw(base_size = 15) + 
        theme(legend.position = "right", 
              legend.key.height = unit(15, "mm"),
              legend.title = element_text(angle = 90, hjust = 0.5),
              legend.title.position = 'left')
    } else {
      p + facet_wrap(~month, ncol = 3) + 
        theme_bw(base_size = 15) + 
        theme(legend.position = "right",
              legend.key.height = unit(15, "mm"),
              legend.title = element_text(angle = 90, hjust = 0.5, size = 22),
              strip.background = element_rect(fill = "transparent", colour = "transparent"),
              strip.text.x = element_text(size = 20), 
              legend.title.position = 'left')
    }
  })
  
  # PSD Coefficients
  output$psd_map_title <- renderText({ paste0("PSD coefficient: ", input$psd_term) })
  output$psd_map_subtitle <- renderText(subtitle_txt())
  
  output$plot_psd_map <- renderPlot({
    res <- model_res()
    coefs_df <- res$coefs_data
    termtoplot <- input$psd_term
    d <- coefs_df %>% filter(term == termtoplot)
    
    if (input$display_mode == "annual") {
      d <- d %>% 
        group_by(latitude, longitude) %>%
        summarise(value = mean(predictedvalue, na.rm = TRUE), .groups = "drop")
    } else {
      d <- d %>% rename(value = predictedvalue)
    }
    
    p <- map_bck +
      geom_raster(data = d, aes(x = longitude, y = latitude, fill = value)) +
      scale_fill_viridis_c(name = termtoplot) +
      scale_x_continuous(limits = res$lon_range, expand = expansion(0, 0)) +
      scale_y_continuous(limits = res$lat_range, expand = expansion(0, 0)) +
      labs(x = "Longitude [°E]", y = "Latitude [°N]") + 
      coord_equal()
    
    if (input$display_mode == "annual") {
      p + theme_bw(base_size = 15) + 
        theme(legend.position = "right", 
              legend.key.height = unit(15, "mm"),
              legend.title = element_text(angle = 90, hjust = 0.5),
              legend.title.position = 'left')
    } else {
      p + facet_wrap(~month, ncol = 3) + 
        theme_bw(base_size = 15) + 
        theme(legend.position = "right",
              legend.key.height = unit(15, "mm"),
              legend.title = element_text(angle = 90, hjust = 0.5, size = 22),
              strip.background = element_rect(fill = "transparent", colour = "transparent"),
              strip.text.x = element_text(size = 20),
              legend.title.position = 'left')
    }
  })
  
  # Performances & Importance
  output$table_metrics <- renderTable({ MODEL_PACK$metrics }, striped = TRUE, hover = TRUE, digits = 4)
  output$table_params  <- renderTable({
    p <- MODEL_PACK$best_params
    data.frame(
      Parameter = c("eta", "max_depth", "min_child_weight", "best_iteration"),
      Value     = c(p$eta, p$max_depth, p$min_child_weight, p$best_iteration)
    )
  }, striped = TRUE, hover = TRUE)
  
  output$plot_importance <- renderPlot({
    ggplot(MODEL_PACK$importance, aes(x = reorder(Feature, Gain), y = Gain)) +
      geom_col(fill = "black", colour = "white") + coord_flip() + theme_bw(base_size = 15) +
      labs(x = "Predictors", y = "Gain")
  })
  
  output$plot_obs_vs_pred <- renderPlot({
    ggplot(MODEL_PACK$test_results, aes(x = observed, y = predicted)) +
      geom_point(alpha = 0.25, color = "black") +
      geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "grey") +
      scale_x_log10() + scale_y_log10() + theme_bw(base_size = 15) + coord_fixed(ratio = 1)
  })
  
  # Aperçu
  output$table_preview <- renderTable({
    model_res()$predictions %>%
      dplyr::select(latitude, longitude, month, depth, flux_pred, flux_sd) %>%
      head(10)
  }, striped = TRUE, hover = TRUE)
  
  # Téléchargement
  output$btn_download <- downloadHandler(
    filename = function() {
      paste0("POC_flux_predictions_", model_res()$target_depth, "m_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write_csv(model_res()$predictions %>% dplyr::select(latitude, longitude, month, depth, flux_pred, flux_sd), file)
    }
  )
}

shinyApp(ui = ui, server = server)
