# Define the survey UI
surveyUI <- function(id = NULL, theme = "defaultV2") {
  
  css_file <- switch(theme,
                     "defaultV2" = paste0("https://unpkg.com/survey-core/defaultV2.fontless.css"),
                     "modern" = paste0("https://unpkg.com/survey-core/modern.css")
  )
  
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

# Define the server function for handling survey data and dynamic field configurations
surveyServer <- function(input = NULL, 
                         output = NULL, 
                         session = NULL, 
                         token_active = NULL, 
                         token_table = NULL,
                         pool = NULL,
                         session_id = NULL) {
  
  # Initialize reactive values for state management
  survey_data <- reactiveVal(NULL)         # Stores the final survey response data
  group_lookup <- reactiveVal(NULL)        # Stores group lookup values for token resolution
  group_value <- reactiveVal(NULL)         # Stores the actual group value (not token)
  current_field_config <- reactiveVal(NULL)# Stores current field configuration
  survey_config <- reactiveVal(NULL)       # Stores survey configuration details
  config_cache <- reactiveVal(NULL)        # Caches the configuration file
  table_cache <- reactiveValues()          # Caches table data for performance
  field_updates <- reactiveVal(new.env())  # Stores field update events
  
  # Helper function to safely retrieve and cache table data
  get_table_data <- function(table_name) {
    if (is.null(table_cache[[table_name]])) {
      table_cache[[table_name]] <- read_table(pool, table_name, session_id)
    }
    return(table_cache[[table_name]])
  }
  
  # Load and cache configuration file on initialization
  observe({
    if (is.null(config_cache())) {
      config_cache(read_yaml("dynamic_fields.yml"))
    }
  }, priority = 1000)
  
  # Handle initial survey setup and JSON loading
  observe({
    # Extract survey parameter from URL query
    query <- parseQueryString(session$clientData$url_search)
    survey <- query$survey
    
    if (is.null(survey)) {
      warning(sprintf("[Session %s] No survey parameter in query", session_id))
      return()
    }
    
    # Resolve survey identifier based on token status
    survey_identifier <- if (token_active) {
      token_table[token_table$token == survey, "object"]
    } else {
      survey
    }
    
    # Validate token resolution
    if (token_active && length(survey_identifier) == 0) {
      warning(sprintf("[Session %s] Survey lookup returned no results", session_id))
      return()
    }
    
    # Load and validate survey JSON configuration
    survey_json_path <- file.path("www", paste0(survey_identifier, ".json"))
    if (!file.exists(survey_json_path)) {
      warning(sprintf("[Session %s] Survey JSON file not found: %s", session_id, survey_json_path))
      return()
    }
    
    # Load survey JSON and send to client
    survey_json <- fromJSON(survey_json_path, simplifyVector = FALSE)
    session$sendCustomMessage("loadSurvey", survey_json)
    
    # Store survey configuration
    survey_config(list(
      survey = survey,
      survey_identifier = survey_identifier,
      query = query
    ))
  })
  
  # Handle dynamic field configurations
  observe({
    req(survey_config())
    req(config_cache())
    
    isolate({
      config <- config_cache()
      survey_identifier <- survey_config()$survey_identifier
      query <- survey_config()$query
      
      # Process each field configuration
      for (field in seq_along(config$fields)) {
        field_config <- config$fields[[field]]
        
        # Check if field configuration applies to current survey
        if (!is.null(survey_identifier) && survey_identifier %in% field_config$surveys) {
          table_name <- field_config$table_name
          table_data <- get_table_data(table_name)
          
          # Cache first relevant field configuration
          if (is.null(current_field_config())) {
            current_field_config(field_config)
          }
          
          # CASE 1: Assign group in URL query parameter, no selections for group or additional choices
          if (!any(names(field_config) == "choices_col") && !field_config$select_group) {
            group_col <- field_config$group_col
            if (!is.null(group_col) && !is.null(query[[group_col]])) {
              group_val <- query[[group_col]]
              if(token_active) {
                token_object <- token_table[token_table$token == group_val, "object"]
                group_lookup(token_object)
                group_value(token_object)  # Store actual value
              } else {
                group_lookup(group_val)
                group_value(group_val)  # Store actual value
              }
            }
          }
          
          # CASE 2: Select group, no additional choices
          if (!any(names(field_config) == "choices_col") && field_config$select_group) {
            group_col <- field_config$group_col
            if (!is.null(group_col) && group_col %in% names(table_data)) {
              session$sendCustomMessage(
                "updateChoices",
                list(
                  "targetQuestion" = group_col,
                  "choices" = as.list(unique(table_data[[group_col]]))
                )
              )
            }
          }
          
          # CASE 3: Assign group in URL query parameter, select from additional choices
          if (any(names(field_config) == "choices_col") && !field_config$select_group) {
            group_col <- field_config$group_col
            if (!is.null(group_col) && !is.null(query[[group_col]])) {
              group_val <- query[[group_col]]
              
              # Store both the lookup value and actual value
              current_group <- if(token_active) {
                token_object <- token_table[token_table$token == group_val, "object"]
                group_lookup(token_object)
                group_value(token_object)  # Store actual value
                token_object
              } else {
                group_lookup(group_val)
                group_value(group_val)  # Store actual value
                group_val
              }
              
              if (length(current_group) > 0 && current_group %in% table_data[[group_col]]) {
                choices_col <- field_config$choices_col
                filtered_data <- table_data[table_data[[group_col]] == current_group, ]
                
                if (!is.null(choices_col) && choices_col %in% names(filtered_data)) {
                  session$sendCustomMessage(
                    "updateChoices",
                    list(
                      "targetQuestion" = choices_col,
                      "choices" = as.list(unique(filtered_data[[choices_col]]))
                    )
                  )
                }
              }
            }
          }
          
          # CASE 4: Select group, select from additional choices
          if (any(names(field_config) == "choices_col") && field_config$select_group) {
            group_col <- field_config$group_col
            if (!is.null(group_col) && group_col %in% names(table_data)) {
              session$sendCustomMessage(
                "updateChoices",
                list(
                  "targetQuestion" = group_col,
                  "choices" = as.list(unique(table_data[[group_col]]))
                )
              )
            }
          }
        }
      }
    })
  })
  
  # Handle dynamic choice updates based on user selection
  observeEvent(input$selectedChoice, {
    req(config_cache())
    
    if (length(input$selectedChoice$selected) > 0) {
      config <- config_cache()
      field_name <- input$selectedChoice$fieldName
      selected_group <- input$selectedChoice$selected
      
      # Find and process relevant field configuration
      for (field_config in config$fields) {
        if (any(names(field_config) == "choices_col") && 
            field_config$select_group && 
            !is.null(field_config$group_col) && 
            field_config$group_col == field_name) {
          
          table_name <- field_config$table_name
          table_data <- get_table_data(table_name)
          
          # Update choices based on selected group
          if (length(selected_group) > 0 && selected_group %in% table_data[[field_config$group_col]]) {
            choices_col <- field_config$choices_col
            filtered_data <- table_data[table_data[[field_config$group_col]] == selected_group, ]
            
            if (!is.null(choices_col) && choices_col %in% names(filtered_data)) {
              session$sendCustomMessage(
                "updateChoices",
                list(
                  "targetQuestion" = choices_col,
                  "choices" = as.list(unique(filtered_data[[choices_col]]))
                )
              )
            }
          }
          break
        }
      }
    }
  })
  
  # Handle survey data submission
  observeEvent(input$surveyData, {
    # Parse submitted survey data
    data <- fromJSON(input$surveyData)
    
    # Add group information if available
    field_config <- current_field_config()
    if (!is.null(field_config) && !is.null(field_config$group_col)) {
      # Use actual group value instead of token
      if (!is.null(group_value())) {
        data[[field_config$group_col]] <- group_value()
      }
    }
    
    # Update survey data and render table
    survey_data(data)
    output$surveyData <- renderTable({
      req(survey_data())
      survey_data()
    })
  })
  
  # Return the survey data reactive value
  return(survey_data)
}
