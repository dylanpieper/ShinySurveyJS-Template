# UI ----
surveyUI <- function(id = NULL, theme = "defaultV2") {
  css_file <- switch(theme,
    "defaultV2" = paste0("https://unpkg.com/survey-core/defaultV2.fontless.css"),
    "modern" = paste0("https://unpkg.com/survey-core/modern.css")
  )

  tagList(
    tags$head(
      tags$script(src = paste0("https://unpkg.com/survey-jquery/survey.jquery.min.js")),
      tags$link(rel = "stylesheet", href = css_file),
      tags$style(sass::sass(sass::sass_file("www/custom.scss"))),
      tags$script(src = "survey.js")
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
                         survey_show_response = TRUE) {
  
  # Initialize reactive values for state management
  rv <- reactiveValues(
    survey_data = NULL,            # Final survey response data
    survey_config = NULL,          # Survey configuration from database
    dynamic_config = NULL,         # Parsed json_config for dynamic fields
    group_value = NULL,            # Current group value
    group_id = NULL,               # Current group ID
    table_cache = new.env(),       # Cache for database tables
    token_data = NULL,             # Store token data
    display_data = NULL,           # Processed data for display
    time_load = NULL,              # Time when survey JSON is sent
    time_json_load = NULL,         # Time when JSON is loaded
    time_survey_complete = NULL    # Time when survey is completed
  )
  
  # Record timing data on page load
  observe({
    if (is.null(rv$page_load)) {
      rv$time_load <- Sys.time()
    }
  }, priority = 1000) 

  # Helper function to check survey availability and hide and show messages
  check_survey_availability <- function(survey_record) {
    if (is.null(survey_record)) {
      return(FALSE)
    }

    # Check if survey is active
    if (!isTRUE(survey_record$survey_active)) {
      warning(sprintf("[Session %s] Survey is inactive", session_id))
      hide_and_show_message("waitingMessage", "inactiveSurveyMessage")
      return(FALSE)
    }

    current_time <- Sys.time()

    # Check start date only if it's not NULL and not NA
    if (!is.null(survey_record$date_start) && !is.na(survey_record$date_start)) {
      date_start <- as.POSIXct(survey_record$date_start)
      if (!is.na(date_start) && current_time < date_start) {
        warning(sprintf(
          "[Session %s] Survey hasn't started yet. Starts: %s",
          session_id, format(date_start)
        ))
        hide_and_show_message("waitingMessage", "surveyNotStartedMessage")
        return(FALSE)
      }
    }

    # Check end date only if it's not NULL and not NA
    if (!is.null(survey_record$date_end) && !is.na(survey_record$date_end)) {
      date_end <- as.POSIXct(survey_record$date_end)
      if (!is.na(date_end) && current_time > date_end) {
        warning(sprintf(
          "[Session %s] Survey has ended. Ended: %s",
          session_id, format(date_end)
        ))
        hide_and_show_message("waitingMessage", "surveyEndedMessage")
        return(FALSE)
      }
    }

    return(TRUE)
  }

  # Observe token table changes
  observe({
    if (is.function(token_table)) {
      rv$token_data <- token_table()
    } else {
      rv$token_data <- token_table
    }
  })

  # Helper function to safely get and cache table data with validation
  get_cached_table <- function(table_name, required_cols = NULL) {
    if (!exists(table_name, envir = rv$table_cache)) {
      max_attempts <- 3
      attempt <- 1
      table_data <- NULL

      while (is.null(table_data) && attempt <= max_attempts) {
        table_data <- tryCatch(
          {
            data <- db_ops$read_table(table_name)

            # Validate required columns if specified
            if (!is.null(required_cols)) {
              missing_cols <- setdiff(required_cols, names(data))
              if (length(missing_cols) > 0) {
                stop(sprintf(
                  "Missing required columns in table %s: %s",
                  table_name, paste(missing_cols, collapse = ", ")
                ))
              }
            }

            data
          },
          error = function(e) {
            warning(sprintf(
              "[Session %s] Error reading table %s (attempt %d): %s",
              session_id, table_name, attempt, e$message
            ))
            NULL
          }
        )
        attempt <- attempt + 1
      }

      if (!is.null(table_data)) {
        assign(table_name, table_data, envir = rv$table_cache)
      }
    }
    get(table_name, envir = rv$table_cache)
  }

  # Helper function to validate values
  validate_value <- function(value, table_data, col_name, context = "value") {
    if (is.null(value) || is.null(table_data) || !col_name %in% names(table_data)) {
      return(FALSE)
    }

    is_valid <- value %in% table_data[[col_name]]
    if (!is_valid) {
      warning(sprintf(
        "[Session %s] Invalid %s: %s",
        session_id, context, value
      ))
    }
    return(is_valid)
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

  # Helper function to update survey text
  update_survey_text <- function(question_name, text) {
    if (!is.null(text)) {
      session$sendCustomMessage(
        "updateText",
        list(
          "targetQuestion" = question_name,
          "text" = as.character(text)
        )
      )
    }
  }

  # Helper function to resolve token to object
  resolve_token <- function(token) {
    if (is.null(token)) {
      warning(sprintf("[Session %s] No token provided", session_id))
      return(NULL)
    }

    token_df <- rv$token_data
    if (is.null(token_df)) {
      warning(sprintf("[Session %s] Token table is NULL (check token_table parameter)", session_id))
      return(NULL)
    }

    if (!("token" %in% names(token_df) && "object" %in% names(token_df))) {
      warning(sprintf(
        "[Session %s] Token table missing required columns (available columns: %s)",
        session_id, paste(names(token_df), collapse = ", ")
      ))
      return(NULL)
    }

    matching_rows <- token_df[token_df$token == token, "object"]
    if (length(matching_rows) > 0) {
      return(matching_rows[1])
    }

    warning(sprintf("[Session %s] Token not found: %s", session_id, token))
    return(NULL)
  }

  # Helper function to handle group value resolution and storage
  handle_group_value <- function(group_param) {
    if (is.null(group_param)) {
      warning(sprintf("[Session %s] No group parameter provided", session_id))
      hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
      return(NULL)
    }

    # Get the configuration first
    config <- rv$dynamic_config
    if (is.null(config) || is.null(config$table_name) || is.null(config$group_col)) {
      warning(sprintf("[Session %s] Missing configuration for group validation", session_id))
      hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
      return(NULL)
    }

    # Get table data with error handling
    table_data <- tryCatch(
      {
        get_cached_table(config$table_name, required_cols = config$group_col)
      },
      error = function(e) {
        warning(sprintf("[Session %s] Error retrieving table data: %s", session_id, e$message))
        hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
        return(NULL)
      }
    )

    if (is.null(table_data)) {
      warning(sprintf("[Session %s] Could not retrieve table data for validation", session_id))
      hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
      return(NULL)
    }

    # Resolve token and validate group value
    if (token_active) {
      group_val <- resolve_token(group_param)
    } else {
      group_val <- group_param
    }

    if (is.null(group_val)) {
      hide_and_show_message("waitingMessage", "invalidGroupIdMessage")
      return(NULL)
    }

    # Validate group value exists in table
    if (!group_val %in% table_data[[config$group_col]]) {
      warning(sprintf("[Session %s] Invalid group value provided: %s", session_id, group_val))
      hide_and_show_message("waitingMessage", "invalidGroupIdMessage")
      return(NULL)
    }

    # Store valid group value
    rv$group_value <- group_val
    return(group_val)
  }

  # Helper function to handle group ID resolution and storage
  handle_group_id <- function(id_param) {
    if (!is.null(id_param)) {
      # Resolve token first
      if (token_active) {
        id_val <- resolve_token(id_param)
      } else {
        id_val <- id_param
      }

      if (length(id_val) > 0) {
        # Get the configuration
        config <- rv$dynamic_config
        if (is.null(config) || is.null(config$group_id_table_name) || is.null(config$group_id_col)) {
          warning(sprintf(
            "[Session %s] Missing configuration for group ID validation",
            session_id
          ))
          hide_and_show_message("waitingMessage", "invalidGroupIdMessage")
          return(NULL)
        }

        # Get group ID table data with error handling
        group_id_table <- tryCatch(
          {
            get_cached_table(config$group_id_table_name, required_cols = config$group_id_col)
          },
          error = function(e) {
            warning(sprintf(
              "[Session %s] Error retrieving group ID table data: %s",
              session_id, e$message
            ))
            return(NULL)
          }
        )

        if (is.null(group_id_table)) {
          warning(sprintf(
            "[Session %s] Could not retrieve group ID table for validation",
            session_id
          ))
          hide_and_show_message("waitingMessage", "invalidGroupIdMessage")
          return(NULL)
        }

        # Validate group ID exists in table
        if (!id_val %in% group_id_table[[config$group_id_col]]) {
          warning(sprintf(
            "[Session %s] Invalid group ID provided: %s",
            session_id, id_val
          ))
          hide_and_show_message("waitingMessage", "invalidGroupIdMessage")
          return(NULL)
        }

        # If we get here, the group ID is valid
        rv$group_id <- id_val
        return(id_val)
      }
    }

    warning(sprintf(
      "[Session %s] No valid group ID found for parameter: %s",
      session_id, id_param
    ))
    hide_and_show_message("waitingMessage", "invalidGroupIdMessage")
    return(NULL)
  }

  # Initialize survey
  observe({
    query <- parseQueryString(session$clientData$url_search)
    survey_param <- query$survey

    if (is.null(survey_param)) {
      warning(sprintf("[Session %s] No survey parameter in query", session_id))
      hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
      return()
    }

    # When tokens are active, require token access
    if (token_active) {
      survey_name <- resolve_token(survey_param)
    } else {
      survey_name <- survey_param
    }

    if (is.null(survey_name)) {
      hide_and_show_message("waitingMessage", "surveyNotFoundMessage")
      return()
    }

    # Query survey table from database
    survey_record <- tryCatch(
      {
        result <- db_ops$read_table(survey_table_name) |>
          as.data.frame() |>
          dplyr::filter(survey_name == !!survey_name)
        
        if(nrow(result) == 1) {
          message(sprintf(
            "[Session %s] Located survey",
            session_id
          ))
  
          result
        }
      },
      error = function(e) {
        warning(sprintf(
          "[Session %s] Error querying survey table: %s",
          session_id, e$message
        ))
        return(NULL)
      }
    )

    if (is.null(survey_record) || nrow(survey_record) == 0) {
      warning(sprintf(
        "[Session %s] Survey not found in database: %s",
        session_id, survey_name
      ))
      hide_and_show_message("waitingMessage", "surveyNotFoundMessage")
      return()
    }

    if (!check_survey_availability(survey_record)) {
      return()
    }

    # Store survey configuration and parse JSON
    rv$survey_config <- survey_record
    if (!is.null(survey_record$json_config)) {
      tryCatch(
        {
          rv$dynamic_config <- jsonlite::fromJSON(survey_record$json_config)
        },
        error = function(e) {
          warning(sprintf(
            "[Session %s] Error parsing JSON config: %s",
            session_id, e$message
          ))
        }
      )
    }

    # Load survey JSON
    tryCatch({
      survey_json <- survey_record$json
      
      session$sendCustomMessage(
        "loadSurvey",
        jsonlite::fromJSON(survey_json, simplifyVector = FALSE)
      )
      shinyjs::hide("waitingMessage", anim = TRUE, animType = "fade", time = 1)
      
      rv$time_json_load <- Sys.time()
    }, error = function(e) {
      warning(sprintf(
        "[Session %s] Error loading survey JSON: %s",
        session_id, e$message
      ))
    })
  })
  
  # Handle dynamic field configurations
  observe({
    req(rv$dynamic_config)

    config <- rv$dynamic_config
    query <- parseQueryString(session$clientData$url_search)

    # Validate required configuration
    if (is.null(config$table_name) || is.null(config$group_col)) {
      return()
    }

    # Get main table data
    table_data <- get_cached_table(config$table_name,
      required_cols = c(config$group_col, config$choices_col)
    )

    # Handle group ID table if specified
    group_id_table <- NULL
    if (!is.null(config$group_id_table_name) && !is.null(config$group_id_col)) {
      group_id_table <- get_cached_table(config$group_id_table_name,
        required_cols = config$group_id_col
      )
    }

    # CASE 1: Assign group in URL with no selections
    if (!config$select_group && is.null(config$choices_col)) {
      group_val <- handle_group_value(query[[config$group_col]])
      if (is.null(group_val)) {
        hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
        return()
      }

      # Update the hidden text for surveyjs json reactivity
      update_survey_text(config$group_col, gsub("_", " ", group_val))
    }

    # CASE 2: Select group from a database table with no additional choices
    else if (config$select_group && is.null(config$choices_col)) {
      if (config$group_col %in% names(table_data)) {
        update_survey_choices(config$group_col, table_data[[config$group_col]])
      }
    }

    # CASE 3: Assign group in URL and select filtered choices
    else if (!config$select_group && !is.null(config$choices_col)) {
      group_val <- handle_group_value(query[[config$group_col]])
      if (is.null(group_val)) {
        hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
        return()
      }

      if (group_val %in% table_data[[config$group_col]]) {
        filtered_data <- table_data[table_data[[config$group_col]] == group_val, ]
        update_survey_choices(config$choices_col, filtered_data[[config$choices_col]])
        # Add text update similar to Case 1
        update_survey_text(config$group_col, gsub("_", " ", group_val))
      }
    }

    # CASE 4: Select group and additional choices
    else if (config$select_group && !is.null(config$choices_col) &&
             (is.null(config$group_id_col) || is.null(config$group_id_table_name))) {
      # Initialize group selection
      if (config$group_col %in% names(table_data)) {
        update_survey_choices(config$group_col, table_data[[config$group_col]])
      }
      
      # Handle existing group selection and update choices
      selected_group <- query[[config$group_col]]
      if (!is.null(selected_group)) {
        group_val <- handle_group_value(selected_group)
        if (!is.null(group_val) && group_val %in% table_data[[config$group_col]]) {
          filtered_data <- table_data[table_data[[config$group_col]] == group_val, ]
          update_survey_choices(config$choices_col, filtered_data[[config$choices_col]])
        }
      }
    }

    # CASE 5: Select group and additional choices with group ID tracking
    else if (config$select_group && !is.null(config$choices_col) &&
      !is.null(config$group_id_col) && !is.null(config$group_id_table_name)) {
      # Handle group ID validation
      group_id_val <- handle_group_id(query[[config$group_id_col]])
      if (is.null(group_id_val)) {
        hide_and_show_message("waitingMessage", "invalidGroupIdMessage")
        return()
      }

      # Initialize group selection dropdown
      if (config$group_col %in% names(table_data)) {
        update_survey_choices(config$group_col, table_data[[config$group_col]])
      }

      # Update the hidden text for group ID
      update_survey_text(config$group_id_col, gsub("_", " ", group_id_val))

      # Handle existing group selection and update choices
      selected_group <- query[[config$group_col]]
      if (!is.null(selected_group)) {
        group_val <- handle_group_value(selected_group)
        if (!is.null(group_val) && group_val %in% table_data[[config$group_col]]) {
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

  # Process survey data and add metadata columns
  process_survey_data <- function(data, session_id, timing_data = NULL) {
    if (is.null(data)) return(NULL)
    
    # Convert data to data frame if it's not already
    if (!is.data.frame(data)) {
      data <- as.data.frame(t(unlist(data)), stringsAsFactors = FALSE)
    }
    
    # Add timing data if available
    if (!is.null(timing_data)) {
      for (field in names(timing_data)) {
        data[[field]] <- rep(timing_data[[field]], nrow(data))
      }
    }
    
    # Ensure group value is included
    if (!is.null(rv$group_value) && !is.null(rv$dynamic_config$group_col)) {
      data[[rv$dynamic_config$group_col]] <- rv$group_value
    }
    
    # Add session ID to data
    data$session_id <- session_id
    
    # Get IP address from headers if available
    ip <- NULL
    request <- session$request
    
    if (!is.null(request)) {
      ip <- if (!is.null(request$HTTP_X_FORWARDED_FOR)) {
        request$HTTP_X_FORWARDED_FOR
      } else if (!is.null(request$HTTP_X_REAL_IP)) {
        request$HTTP_X_REAL_IP
      } else if (!is.null(request$REMOTE_ADDR)) {
        request$REMOTE_ADDR
      }
      
      if (!is.null(ip)) {
        data$ip_address <- ip
      }
    }
    
    # Add group ID if available
    if (!is.null(rv$group_id) && !is.null(rv$dynamic_config$group_id_col)) {
      data[[rv$dynamic_config$group_id_col]] <- rv$group_id
    }
    
    # If data is multirow, then add row number
    if (nrow(data) > 1) {
      data$row_id <- seq_len(nrow(data))
    }
    
    # Add dates for created and updated
    data$date_created <- Sys.time()
    data$date_updated <- Sys.time()
    
    # Remove any empty columns
    data <- data[, colSums(is.na(data)) < nrow(data), drop = FALSE]
    
    # Define metadata columns that should appear at the end
    metadata_cols <- c(
      "session_id",
      "ip_address", 
      "duration_load",
      "duration_complete",
      "date_created",
      "date_updated"
    )
    
    # Define groups of columns for ordering
    all_cols <- names(data)
    
    # Get system columns that exist
    system_cols <- intersect(c("session_id", "ip_address"), all_cols)
    
    # Get duration columns that exist (in order)
    duration_cols <- grep("^duration_", all_cols, value = TRUE)
    duration_cols <- intersect(
      c("duration_load", "duration_complete"),
      duration_cols
    )
    
    # Get date columns that exist (in order)
    date_cols <- intersect(c("date_created", "date_updated"), all_cols)
    
    # Get all other columns (non-system, non-duration, non-date)
    metadata_cols <- c(system_cols, duration_cols, date_cols)
    regular_cols <- setdiff(all_cols, metadata_cols)
    
    # Combine in desired order
    final_col_order <- c(regular_cols, system_cols, duration_cols, date_cols)
    
    # Only reorder if we have columns to reorder
    if (length(final_col_order) > 0) {
      data <- data[, final_col_order, drop = FALSE]
    }
    
    return(data)
  }
  
  # Handle survey completion and data processing
  observeEvent(input$surveyData, {
    # Parse the survey data
    data <- tryCatch({
      jsonlite::fromJSON(input$surveyData)
    }, error = function(e) {
      warning(sprintf("[Session %s] Error parsing survey data: %s", session_id, e$message))
      return(NULL)
    })
    
    if (is.null(data)) {
      return()
    }
    
    # Show saving message
    shinyjs::show("savingDataMessage", anim = TRUE, animType = "fade")
    
    # Record completion time
    rv$time_survey_complete <- Sys.time()
    
    # Calculate all timing data upfront
    timing_data <- list()
    
    # Calculate load duration (time between page load and JSON load)
    if (!is.null(rv$time_load) && !is.null(rv$time_json_load)) {
      timing_data$duration_load <- as.numeric(difftime(rv$time_json_load,
                                                       rv$time_load,
                                                       units = "secs"))
    }
    
    # Calculate completion duration (time between JSON load and submission)
    if (!is.null(rv$time_json_load) && !is.null(rv$time_survey_complete)) {
      timing_data$duration_complete <- as.numeric(difftime(rv$time_survey_complete,
                                                           rv$time_json_load,
                                                           units = "secs"))
    }
    
    # Store timing data in reactive values
    rv$timing_data <- timing_data
    
    # Add group value if it was set from URL
    if (!is.null(rv$group_value) && !is.null(rv$dynamic_config$group_col)) {
      if (is.list(data) && !is.data.frame(data)) {
        data[[rv$dynamic_config$group_col]] <- rv$group_value
      } else if (is.data.frame(data)) {
        data[[rv$dynamic_config$group_col]] <- rep(rv$group_value, nrow(data))
      }
    }
    
    # Add group ID if available
    if (!is.null(rv$group_id) && !is.null(rv$dynamic_config$group_id_col)) {
      if (is.list(data) && !is.data.frame(data)) {
        data[[rv$dynamic_config$group_id_col]] <- rv$group_id
      } else if (is.data.frame(data)) {
        data[[rv$dynamic_config$group_id_col]] <- rep(rv$group_id, nrow(data))
      }
    }
    
    # Add timing data to the survey data
    if (is.list(data) && !is.data.frame(data)) {
      data <- c(data, timing_data)
    } else if (is.data.frame(data)) {
      for (field in names(timing_data)) {
        data[[field]] <- rep(timing_data[[field]], nrow(data))
      }
    }
    
    # Store raw survey data before processing
    rv$survey_data <- data
    
    # Get survey name from config
    survey_name <- rv$survey_config$survey_name
    if (is.null(survey_name)) {
      warning(sprintf("[Session %s] Survey name not found in configuration", session_id))
      shinyjs::hide("savingDataMessage", anim = TRUE, animType = "fade")
      return()
    }
    
    # Database operations with error handling
    tryCatch({
      # Process data for the data table
      temp_processed_data <- process_survey_data(data, session_id, timing_data)
      
      # Create table if it doesn't exist
      db_ops$create_survey_data_table(survey_name, temp_processed_data)
      
      # Update table schema if needed and insert data
      db_ops$update_survey_data_table(survey_name, temp_processed_data)
      
      # Process the final data with all timing information
      rv$display_data <- process_survey_data(data, session_id, timing_data)
    }, error = function(e) {
      warning(sprintf("[Session %s] Error saving data to database: %s",
                      session_id, e$message))
    })
    
    # Hide saving message
    shinyjs::hide("savingDataMessage", anim = TRUE, animType = "fade")
    
    # Show the data container if survey_show_response is TRUE
    if (survey_show_response) {
      shinyjs::show("surveyDataContainer")
    }
  })
  
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
  
  # Return reactive survey data
  return(reactive(rv$survey_data))
}
