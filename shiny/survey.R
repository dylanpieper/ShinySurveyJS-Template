# UI ----
surveyUI <- function(id = NULL, theme = "defaultV2") {
  css_file <- switch(theme,
                     "defaultV2" = paste0("https://unpkg.com/survey-core/defaultV2.fontless.css"),
                     "modern" = paste0("https://unpkg.com/survey-core/modern.css"))
  
  tagList(
    tags$head(
      tags$script(src = paste0("https://unpkg.com/survey-jquery/survey.jquery.min.js")),
      tags$link(rel = "stylesheet", href = css_file),
      tags$link(rel = "stylesheet", href = "_custom.css"),
      tags$script(src = "_survey.js")
    ),
    tags$div(id = "surveyContainer")
  )
}

# Server ----
surveyServer <- function(input = NULL, 
                         output = NULL, 
                         session = NULL, 
                         token_active = NULL, 
                         token_table = NULL,
                         db_ops = NULL,
                         session_id = NULL,
                         survey_table_name = NULL,
                         show_response = TRUE) {
  
  # Initialize reactive values for state management
  rv <- reactiveValues(
    survey_data = NULL,          # Final survey response data
    survey_config = NULL,        # Survey configuration from database
    dynamic_config = NULL,       # Parsed config_json for dynamic fields
    group_value = NULL,          # Current group value
    table_cache = new.env(),     # Cache for database tables
    token_data = NULL,           # Store token data
    display_data = NULL          # Processed data for display
  )
  
  # Observe token table changes
  observe({
    if (is.function(token_table)) {
      rv$token_data <- token_table()
    } else {
      rv$token_data <- token_table
    }
  })
  
  # Helper function to safely get and cache table data
  get_cached_table <- function(table_name) {
    if (!exists(table_name, envir = rv$table_cache)) {
      max_attempts <- 3
      attempt <- 1
      table_data <- NULL
      
      while (is.null(table_data) && attempt <= max_attempts) {
        table_data <- tryCatch({
          db_ops$read_table(table_name)
        }, error = function(e) {
          warning(sprintf("[Session %s] Attempt %d: Error reading table %s: %s", 
                          session_id, attempt, table_name, e$message))
          NULL
        })
        attempt <- attempt + 1
      }
      
      if (!is.null(table_data)) {
        assign(table_name, table_data, envir = rv$table_cache)
      }
    }
    get(table_name, envir = rv$table_cache)
  }
  
  # Helper function to update survey choices
  update_survey_choices <- function(question_name, choices) {
    if (!is.null(choices) && length(choices) > 0) {
      session$sendCustomMessage(
        "updateChoices",
        list(
          "targetQuestion" = question_name,
          "choices" = as.list(unique(choices))
        )
      )
    }
  }
  
  # Helper function to resolve token to object
  resolve_token <- function(token) {
    if (!token_active || is.null(token)) {
      warning(sprintf("[Session %s] Token resolution skipped - token_active: %s, token: %s", 
                      session_id, token_active, token))
      return(token)
    }
    
    token_df <- rv$token_data
    if (is.null(token_df)) {
      warning(sprintf("[Session %s] Token table is NULL - Check token_table parameter", session_id))
      return(token)
    }
    
    if (!("token" %in% names(token_df) && "object" %in% names(token_df))) {
      warning(sprintf("[Session %s] Token table missing required columns. Available columns: %s", 
                      session_id, paste(names(token_df), collapse=", ")))
      return(token)
    }
    
    matching_rows <- token_df[token_df$token == token, "object"]
    if (length(matching_rows) > 0) {
      return(matching_rows[1])
    }
    
    warning(sprintf("[Session %s] Token not found: %s", 
                    session_id, token))
    return(token)
  }
  
  # Helper function to handle group value resolution and storage
  handle_group_value <- function(group_param) {
    if (!is.null(group_param)) {
      group_val <- resolve_token(group_param)
      if (length(group_val) > 0) {
        rv$group_value <- group_val
        return(group_val)
      }
    }
    warning(sprintf("[Session %s] No valid group value found for parameter: %s", 
                    session_id, group_param))
    return(NULL)
  }
  
  # Initialize survey on startup
  observe({
    query <- parseQueryString(session$clientData$url_search)
    survey_param <- query$survey
    
    if (is.null(survey_param)) {
      warning(sprintf("[Session %s] No survey parameter in query: %s", 
                      session_id, paste(names(query), collapse=", ")))
      hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
      return()
    }
    
    # Debug log for survey parameter
    message(sprintf("[Session %s] Processing survey parameter: %s", session_id, survey_param))
    
    # Resolve survey name from token if needed
    survey_name <- resolve_token(survey_param)
    
    if (length(survey_name) == 0) {
      warning(sprintf("[Session %s] Invalid survey token: %s", session_id, survey_param))
      return()
    }
    
    # Debug log for database operation
    message(sprintf("[Session %s] Querying database for survey: %s", session_id, survey_name))
    
    # Query survey configuration from database with detailed error tracking
    survey_record <- tryCatch({
      
      result <- db_ops$read_table(survey_table_name) |> as.data.frame() |> dplyr::filter(survey_name == !!survey_name)
      
      # Debug log for query result
      message(sprintf("[Session %s] Loaded survey table (n = %s)", 
                      session_id, if(is.null(result)) "NULL" else nrow(result)))
      
      result
    }, error = function(e) {
      warning(sprintf("[Session %s] Error querying 'surveys' table: %s\nStack trace:\n%s", 
                      session_id, e$message, paste(sys.calls(), collapse = "\n")))
      return(NULL)
    })
    
    if (is.null(survey_record)) {
      warning(sprintf("[Session %s] Survey record is NULL for survey: %s", 
                      session_id, survey_name))
    }
    
    if (nrow(survey_record) == 0) {
      warning(sprintf("[Session %s] Survey not found in database: %s", 
                      session_id, survey_name))
      hide_and_show_message("waitingMessage", "surveyNotFoundMessage")
      return()
    }
    
    # Store survey configuration and JSON
    rv$survey_config <- survey_record
    
    # Parse config_json if present with detailed error handling
    if (!is.null(survey_record$config_json)) {
      tryCatch({
        message(sprintf("[Session %s] Parsing JSON config for survey: %s", 
                        session_id, survey_name))
        rv$dynamic_config <- jsonlite::fromJSON(survey_record$config_json)
      }, error = function(e) {
        warning(sprintf("[Session %s] Error parsing JSON config: %s\nJSON config content: %s", 
                        session_id, e$message, survey_record$config_json))
      })
    }
    
    # Load and send survey JSON to client with enhanced error handling
    tryCatch({
      message(sprintf("[Session %s] Loading survey JSON for survey: %s", 
                      session_id, survey_name))
      
      survey_json <- survey_record$json
      
      session$sendCustomMessage("loadSurvey", fromJSON(survey_json, simplifyVector = FALSE))
      
      shinyjs::hide("waitingMessage", anim = TRUE, animType = "fade", time = 1)
    }, error = function(e) {
      warning(sprintf("[Session %s] Error loading survey JSON: %s\nJSON content: %s", 
                      session_id, e$message, substr(survey_json, 1, 100)))
    })
  })
  
  # Handle dynamic field configurations
  observe({
    req(rv$dynamic_config)
    
    config <- rv$dynamic_config
    query <- parseQueryString(session$clientData$url_search)
    
    # Only proceed if we have necessary configuration
    if (is.null(config$table_name) || is.null(config$group_col)) {
      return()
    }
    
    # Get table data once for all cases
    table_data <- get_cached_table(config$table_name)
    
    # CASE 1: Assign group in URL query parameter, no selections for group or additional choices
    if (!config$select_group && is.null(config$choices_col)) {
      group_val <- handle_group_value(query[[config$group_col]])
      if (!is.null(group_val) && !group_val %in% table_data[[config$group_col]]) {
        warning(sprintf("[Session %s] Invalid group value: %s", session_id, group_val))
      }
    }
    
    # CASE 2: Select group, no additional choices
    else if (config$select_group && is.null(config$choices_col)) {
      if (config$group_col %in% names(table_data)) {
        update_survey_choices(config$group_col, table_data[[config$group_col]])
      }
    }
    
    # CASE 3: Assign group in URL query parameter, select from additional choices
    else if (!config$select_group && !is.null(config$choices_col)) {
      group_val <- handle_group_value(query[[config$group_col]])
      
      if (!is.null(group_val) && group_val %in% table_data[[config$group_col]]) {
        filtered_data <- table_data[table_data[[config$group_col]] == group_val, ]
        
        if (config$choices_col %in% names(filtered_data)) {
          update_survey_choices(config$choices_col, filtered_data[[config$choices_col]])
        }
      }
    }
    
    # CASE 4: Select group, select from additional choices
    else if (config$select_group && !is.null(config$choices_col)) {
      # Initialize group selection dropdown
      if (config$group_col %in% names(table_data)) {
        update_survey_choices(config$group_col, table_data[[config$group_col]])
      }
      
      # Handle any existing group selection
      selected_group <- query[[config$group_col]]
      if (!is.null(selected_group)) {
        group_val <- resolve_token(selected_group)
        if (length(group_val) > 0 && group_val %in% table_data[[config$group_col]]) {
          filtered_data <- table_data[table_data[[config$group_col]] == group_val, ]
          update_survey_choices(config$choices_col, filtered_data[[config$choices_col]])
        }
      }
    }
  })
  
  # Handle dynamic updates based on user selections
  observeEvent(input$selectedChoice, {
    req(rv$dynamic_config)
    selected <- input$selectedChoice
    
    # Only process relevant field changes
    if (is.null(selected$fieldName) || is.null(selected$selected)) {
      return()
    }
    
    config <- rv$dynamic_config
    
    # Check if this is a group selection that needs to update choices
    if (config$select_group && 
        !is.null(config$choices_col) && 
        selected$fieldName == config$group_col) {
      
      table_data <- get_cached_table(config$table_name)
      
      if (selected$selected %in% table_data[[config$group_col]]) {
        filtered_data <- table_data[table_data[[config$group_col]] == selected$selected, ]
        update_survey_choices(config$choices_col, filtered_data[[config$choices_col]])
      }
    }
  })
  
  # Handle survey completion and data processing
  observeEvent(input$surveyData, {
    tryCatch({
      # Parse the survey data
      data <- jsonlite::fromJSON(input$surveyData)
      
      # Add group value if it was set from URL
      if (!is.null(rv$group_value) && !is.null(rv$dynamic_config$group_col)) {
        data[[rv$dynamic_config$group_col]] <- rv$group_value
      }
      
      # Store raw survey data
      rv$survey_data <- data
      
      # Process data for display
      rv$display_data <- process_survey_data(data)
      
      # Show the data container if show_response is TRUE
      if (show_response) {
        shinyjs::show("surveyDataContainer")
      }
      
    }, error = function(e) {
      warning(sprintf("[Session %s] Error processing survey data: %s", 
                      session_id, e$message))
    })
  })
  
  # Helper function to process survey data for display
  process_survey_data <- function(data) {
    if (is.null(data)) return(NULL)
    
    # Convert data to data frame if it's not already
    if (!is.data.frame(data)) {
      data <- as.data.frame(data, stringsAsFactors = FALSE)
    }
    
    # Remove any empty columns
    data <- data[, colSums(is.na(data)) < nrow(data), drop = FALSE]
    
    # Reorder columns alphabetically
    data <- data[, sort(names(data)), drop = FALSE]
    
    return(data)
  }
  
  # Render the survey data table with paging
  output$surveyData <- DT::renderDT({
    req(rv$display_data)
    DT::datatable(
      rv$display_data,
      options = list(
        pageLength = 10,
        scrollX = TRUE,
        dom = 'tp'
      ),
      rownames = FALSE
    )
  })
  
  # Return reactive survey data (unchanged)
  return(reactive(rv$survey_data))
}
