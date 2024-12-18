# DB Pool ----

# Database pool class for managing database connections
db_pool <- R6::R6Class(
  "Database Pool",
  public = list(
    pool = NULL,
    initialize = function() {
      dotenv::load_dot_env()
      
      self$pool <- pool::dbPool(
        RPostgres::Postgres(),
        host = Sys.getenv("DB_HOST"),
        port = Sys.getenv("DB_PORT"),
        dbname = Sys.getenv("DB_NAME"),
        user = Sys.getenv("DB_USER"),
        password = Sys.getenv("DB_PASSWORD"),
        minSize = 1,
        maxSize = Inf
      )
    }
  )
)

# DB Ops ----

# Database operations class for managing database queries
db_operations <- R6::R6Class(
  "Database Operations",
  public = list(
    session_id = NULL,
    pool = NULL,
    
    initialize = function(pool, session_id) {
      if (is.null(pool)) {
        stop(private$format_message("Database pool cannot be NULL"))
      }
      self$pool <- pool
      self$session_id <- session_id
    },
    
    create_tokens_table = function(token_table_name) {
      if (is.null(token_table_name) || !is.character(token_table_name)) {
        stop(private$format_message("Invalid token_table_name"))
      }
      
      if (!grepl("^[a-zA-Z0-9_]+$", token_table_name)) {
        stop(private$format_message("Invalid table name format"))
      }
      
      self$execute_db_operation(function(conn) {
        # Create table query
        create_table_query <- sprintf("
          CREATE TABLE IF NOT EXISTS %s (
              id SERIAL PRIMARY KEY,
              object TEXT UNIQUE,
              token TEXT,
              date_created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
              date_updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
          );", token_table_name)
        
        # Create function query
        create_function_query <- "
          CREATE OR REPLACE FUNCTION update_date_updated_column()
          RETURNS TRIGGER AS $$
          BEGIN
              NEW.date_updated = CURRENT_TIMESTAMP;
              RETURN NEW;
          END;
          $$ language 'plpgsql';"
        
        # Trigger queries
        drop_trigger_query <- sprintf("
          DROP TRIGGER IF EXISTS update_%s_date_updated ON %s;", 
                                      token_table_name, token_table_name)
        
        create_trigger_query <- sprintf("
          CREATE TRIGGER update_%s_date_updated
              BEFORE UPDATE ON %s
              FOR EACH ROW
              EXECUTE FUNCTION update_date_updated_column();", 
                                        token_table_name, token_table_name)
        
        DBI::dbExecute(conn, create_table_query)
        DBI::dbExecute(conn, create_function_query)
        DBI::dbExecute(conn, drop_trigger_query)
        DBI::dbExecute(conn, create_trigger_query)
        
        private$log_message("Table tokens was created or already exists")
      }, "Failed to create tokens table")
    },
    
    write_to_tokens_table = function(data, token_table_name) {
      required_fields <- c("object", "token", "date_created", "date_updated")
      if (!all(required_fields %in% names(data))) {
        stop(private$format_message(paste0("The data frame must contain fields: ", required_fields)))
      }
      
      if (!is.data.frame(data) || nrow(data) == 0) {
        stop(private$format_message("Invalid data provided: must be a non-empty data frame"))
      }
      
      self$execute_db_operation(function(conn) {
        DBI::dbWriteTable(
          conn,
          name = token_table_name,
          value = data,
          append = TRUE,
          row.names = FALSE
        )
        private$log_message(private$log_message(sprintf("Successfully wrote to %s table", token_table_name)))
      }, sprintf("Failed to write to %s table", token_table_name))
    },
    
    write_to_surveys_table = function(data, survey_table_name) {
      required_fields <- c("id", "survey_name", "json")
      if (!all(required_fields %in% names(data))) {
        stop(private$format_message(paste0("The data frame must contain fields: ", required_fields)))
      }
      
      if (!is.data.frame(data) || nrow(data) == 0) {
        stop(private$format_message("Invalid data provided: must be a non-empty data frame"))
      }
      
      self$execute_db_operation(function(conn) {
        # For each row in the data frame
        for (i in 1:nrow(data)) {
          row <- data[i, ]
          
          # Check if ID exists
          if ("id" %in% names(row) && !is.na(row$id)) {
            # Update existing record
            update_query <- sprintf(
              "UPDATE %s 
           SET survey_name = $1, 
               json = $2
           WHERE id = $3",
              DBI::dbQuoteIdentifier(conn, survey_table_name)
            )
            
            DBI::dbExecute(
              conn,
              update_query,
              params = list(
                row$survey_name,
                row$json,
                row$id
              )
            )
          } else {
            # Insert new record
            DBI::dbWriteTable(
              conn,
              name = survey_table_name,
              value = row,
              append = TRUE,
              row.names = FALSE
            )
          }
        }
        private$log_message(sprintf("Successfully wrote to %s table", survey_table_name))
      }, sprintf("Failed to write to %s table", survey_table_name))
    },
    
    check_table_exists = function(table_name) {
      if (is.null(table_name) || !is.character(table_name)) {
        stop(private$format_message("Invalid table_name"))
      }
      
      self$execute_db_operation(function(conn) {
        exists <- DBI::dbExistsTable(conn, table_name)
        private$log_message(sprintf("Table %s exists: %s", table_name, exists))
        exists
      }, sprintf("Error checking table %s", table_name))
    },
    
    read_table = function(table_name = NULL,
                          max_retries = 3,
                          retry_timeout = .25,
                          attempt = 1,
                          last_error = NULL) {
      if (is.null(table_name) || !is.character(table_name) || length(table_name) != 1) {
        stop(private$format_message(paste0("Invalid 'table_name': ", table_name, ". It must be a non-null, single-character string.")))
      }
      
      while (attempt <= max_retries) {
        tryCatch({
          result <- self$execute_db_operation(function(conn) {
            table_quoted <- DBI::dbQuoteIdentifier(conn, table_name)
            query <- sprintf("SELECT * FROM %s;", table_quoted)
            DBI::dbGetQuery(conn, query)
          }, sprintf("Failed to read table %s", table_name))
          
          private$log_message(sprintf("Successfully read '%s' table (attempt %d of %d)", table_name, attempt, max_retries))
          return(result)
          
        }, error = function(e) {
          last_error <- e
          private$log_message(sprintf("Attempt %d failed for '%s' table: %s", 
                                      attempt, table_name, e$message))
          
          if (attempt < max_retries) {
            Sys.sleep(retry_timeout)
          }
        })
        
        attempt <- attempt + 1
      }
      
      stop(private$format_message(sprintf(
        "Could not read '%s' table after %d attempts. Last error: %s", 
        table_name, max_retries, 
        if (!is.null(last_error)) last_error$message else "Unknown error"
      )))
    },
    
    execute_db_operation = function(operation, error_message) {
      if (is.null(self$pool)) {
        stop(private$format_message("Database pool is not initialized"))
      }
      
      conn <- NULL
      tryCatch({
        conn <- pool::poolCheckout(self$pool)
        if (is.null(conn) || !DBI::dbIsValid(conn)) {
          stop("Failed to obtain valid database connection")
        }
        
        DBI::dbBegin(conn)
        result <- operation(conn)
        DBI::dbCommit(conn)
        
        return(result)
        
      }, error = function(e) {
        if (!is.null(conn) && DBI::dbIsValid(conn)) {
          tryCatch({
            DBI::dbRollback(conn)
          }, error = function(rollback_error) {
            private$log_message(sprintf("Rollback error: %s", rollback_error$message))
          })
        }
        private$log_message(sprintf("%s: %s", error_message, e$message))
        stop(private$format_message(sprintf("%s: %s", error_message, e$message)))
        
      }, finally = {
        if (!is.null(conn)) {
          tryCatch({
            pool::poolReturn(conn)
          }, error = function(return_error) {
            private$log_message(sprintf("Error returning connection to pool: %s", 
                                        return_error$message))
          })
        }
      })
    }
  ),
  
  private = list(
    log_message = function(msg) {
      message(private$format_message(msg))
    },
    
    format_message = function(msg) {
      sprintf("[Session %s] %s", self$session_id, msg)
    },
    
    table_cache = NULL
  )
)

# DB Setup ----

# Database setup class for initializing database and managing tokens
db_setup <- R6::R6Class(
  "Database Setup",
  public = list(
    db_ops = NULL,
    session_id = NULL,
    
    initialize = function(db_ops, session_id) {
      self$db_ops <- db_ops
      self$session_id <- session_id
    },
    
    setup_staged_json = function(survey_table_name) {
      # Initialize table_cache if needed
      if (is.null(private$table_cache)) {
        private$table_cache <- list()
      }
      
      # Read survey data with caching
      cache_key <- paste0("survey_", survey_table_name)
      if (is.null(private$table_cache[[cache_key]])) {
        surveys_data <- self$db_ops$read_table(survey_table_name)
        private$table_cache[[cache_key]] <- surveys_data
      } else {
        surveys_data <- private$table_cache[[cache_key]]
      }
      
      # Filter for non-null staged_json
      surveys_data <- surveys_data |>
        dplyr::filter(!is.na(staged_json))
      
      if (nrow(surveys_data) == 0) {
        private$log_message("No records with staged JSON found")
        return(surveys_data)
      }
      
      # Store original json for comparison later
      original_json <- surveys_data$json
      
      # Initialize list to store unique table names
      staged_tables <- character(0)
      staged_data_lookup <- list()
      
      # Process each survey row to find unique tables
      for (i in seq_len(nrow(surveys_data))) {
        json_str <- surveys_data$staged_json[i]
        
        # Find all patterns matching table_name["field_name", "column_name"]
        patterns <- unlist(regmatches(json_str, 
                                      gregexpr('\\w+\\["[^"]+", "[^"]+"\\]', 
                                               json_str)))
        
        # Extract table names from patterns
        for (pattern in patterns) {
          table_name <- regmatches(pattern, 
                                   regexec('(\\w+)\\["([^"]+)", "([^"]+)"\\]', 
                                           pattern))[[1]][2]
          staged_tables <- unique(c(staged_tables, table_name))
        }
      }
      
      # Cache and load all required staged json tables
      for (table_name in staged_tables) {
        cache_key <- paste0("staged_", table_name)
        if (is.null(private$table_cache[[cache_key]])) {
          table_data <- self$db_ops$read_table(table_name)
          private$table_cache[[cache_key]] <- table_data
        }
        staged_data_lookup[[table_name]] <- private$table_cache[[cache_key]]
      }
      
      # Process each survey row
      processed_json <- vector("character", nrow(surveys_data))
      for (i in seq_len(nrow(surveys_data))) {
        json_str <- surveys_data$staged_json[i]
        
        # Find all patterns matching table_name["field_name", "column_name"]
        patterns <- unlist(regmatches(json_str, 
                                      gregexpr('\\w+\\["[^"]+", "[^"]+"\\]', 
                                               json_str)))
        
        # Process each pattern
        for (pattern in patterns) {
          json_str <- private$process_match(pattern, json_str, staged_data_lookup)
        }
        
        # Parse and re-serialize to ensure proper JSON formatting
        tryCatch({
          final_json <- jsonlite::toJSON(
            jsonlite::fromJSON(json_str, simplifyVector = FALSE),
            auto_unbox = TRUE,
            pretty = TRUE
          )
          processed_json[i] <- final_json
        }, error = function(e) {
          warning("Failed to parse JSON for row ", i, ": ", e$message)
          processed_json[i] <- json_str
        })
      }
      
      # Update the json column with processed values
      surveys_data$json <- processed_json
      
      # Compare new JSON with original JSON and only write if different
      changed_records <- surveys_data[surveys_data$json != original_json, ]
      
      # Write to surveys database
      if (nrow(changed_records) > 0) {
        self$db_ops$write_to_surveys_table(changed_records |>
                                             dplyr::select(id, survey_name, json), 
                                           survey_table_name)
        private$log_message(sprintf(
          "Updated records in %s table (n = %d)",
          survey_table_name, nrow(changed_records)
        ))
      } else {
        private$log_message("No changes detected in staged JSON data")
      }
      
      return(surveys_data)
    },
    
    setup_database = function(mode, token_table, token_table_name, survey_table_name) {
      if (missing(mode) || !mode %in% c("initial", "tokens")) {
        stop(private$format_message("Invalid 'mode': Accepted values are 'initial' or 'tokens'"))
      }
      
      if (!is.data.frame(token_table)) {
        stop(private$format_message("'token_table' must be a data frame"))
      }
      
      if (is.null(token_table_name) || !is.character(token_table_name)) {
        stop(private$format_message("Invalid token_table_name"))
      }
      
      if (is.null(survey_table_name) || !is.character(survey_table_name)) {
        stop(private$format_message("Invalid survey_table_name"))
      }
      
      required_columns <- c("object", "token", "date_created", "date_updated")
      if (nrow(token_table) > 0) {
        missing_columns <- setdiff(required_columns, names(token_table))
        if (length(missing_columns) > 0) {
          stop(private$format_message(sprintf(
            "'token_table' is missing required columns: %s",
            paste(missing_columns, collapse = ", ")
          )))
        }
      }
      
      tryCatch(
        {
          if (mode == "initial") {
            private$log_message("Setting up database in 'initial' mode")
            self$db_ops$create_tokens_table(token_table_name)
          }
          
          updated_token_table <- self$generate_tokens(token_table, token_table_name, survey_table_name)
          
          if (mode == "initial") {
            private$log_message("Database setup completed in 'initial' mode")
          } else {
            private$log_message("Token generation completed")
          }
          
          return(invisible(updated_token_table))
        },
        error = function(e) {
          private$log_message(sprintf("An error occurred during setup: %s", e$message))
          stop(private$format_message("Database setup failed"))
        }
      )
    },
    
    generate_tokens = function(token_table = NULL, token_table_name = NULL, survey_table_name = NULL) {
      source("shiny/tokens.R")
      
      # Initialize empty token table if NULL
      if (is.null(token_table)) {
        token_table <- data.frame(
          object = character(),
          token = character(),
          date_created = character(),
          date_updated = character(),
          stringsAsFactors = FALSE
        )
      }
      
      # Read and validate surveys data
      surveys_data <- self$db_ops$read_table(survey_table_name)
      if (is.null(surveys_data) || nrow(surveys_data) == 0) {
        private$log_message("No survey data found")
        return(invisible(token_table))
      }
      
      # Create cache environment for database tables
      table_cache <- new.env()
      
      # Helper function to read and cache tables
      read_cached_table <- function(table_name) {
        if (is.null(table_name) || !is.character(table_name)) {
          return(NULL)
        }
        
        if (!exists(table_name, envir = table_cache)) {
          table_data <- self$db_ops$read_table(table_name)
          if (!is.null(table_data)) {
            assign(table_name, table_data, envir = table_cache)
          }
        }
        if (exists(table_name, envir = table_cache)) {
          return(get(table_name, envir = table_cache))
        }
        return(NULL)
      }
      
      # Helper function to extract groups from config
      get_groups_from_config <- function(config_json, group_id_table_name = FALSE) {
        if (is.null(config_json) || config_json == "" || is.na(config_json)) {
          return(character(0))
        }
        
        tryCatch({
          config <- jsonlite::fromJSON(config_json)
          table_logic <- if (!group_id_table_name) config$table_name else config$group_id_table_name
          group_logic <- if (!group_id_table_name) config$group_col else config$group_id_col
          if (!is.null(config) && 
              is.list(config) && 
              !is.null(table_logic) && 
              !is.null(group_logic)) {
            
            table_data <- read_cached_table(table_logic)
            if (!is.null(table_data) && 
                is.data.frame(table_data) && 
                group_logic %in% names(table_data)) {
              return(unique(table_data[[group_logic]]))
            }
          }
          return(character(0))
        }, error = function(e) {
          private$log_message(sprintf("Error parsing config JSON: %s", e$message))
          return(character(0))
        })
      }
      
      # Extract all groups and their IDs from valid configs
      all_groups <- tryCatch({
        valid_configs <- surveys_data$config_json[!is.na(surveys_data$config_json) & 
                                                    surveys_data$config_json != ""]
        
        # Extract groups and group IDs
        groups_and_ids <- lapply(valid_configs, function(config) {
          c(get_groups_from_config(config), 
            get_groups_from_config(config, group_id_table_name = TRUE))
        })
        
        unique_groups <- unique(unlist(groups_and_ids))
        unique_groups[!is.na(unique_groups)]
      }, error = function(e) {
        private$log_message(sprintf("Error processing survey configurations: %s", e$message))
        return(character(0))
      })
      
      # Get survey names
      all_surveys <- if (!is.null(surveys_data$survey_name)) {
        as.character(surveys_data$survey_name[!is.na(surveys_data$survey_name)])
      } else {
        character(0)
      }
      
      # Combine and deduplicate objects
      all_objects <- unique(c(all_surveys, all_groups))
      
      # Check for duplicates between surveys and groups
      duplicate_objects <- intersect(all_surveys, all_groups)
      if (length(duplicate_objects) > 0) {
        warning(private$format_message(sprintf(
          "Found objects that exist as both surveys and groups: %s",
          paste(duplicate_objects, collapse = ", ")
        )))
      }
      
      # Remove any duplicates from token table
      if (nrow(token_table) > 0 && any(duplicated(token_table$object))) {
        warning(private$format_message("Removing duplicate objects from token table"))
        token_table <- token_table[!duplicated(token_table$object), ]
      }
      
      # Find new objects that need tokens
      new_objects <- all_objects[!(all_objects %in% token_table$object)]
      
      if (length(new_objects) == 0) {
        private$log_message("No updates needed for tokens table")
        return(invisible(token_table))
      }
      
      # Generate new tokens
      existing_tokens <- if (!is.null(token_table$token)) token_table$token else character(0)
      new_tokens <- character(length(new_objects))
      
      for (i in seq_along(new_objects)) {
        repeat {
          token <- generate_unique_token(existing_tokens)
          if (!(token %in% existing_tokens)) {
            new_tokens[i] <- token
            existing_tokens <- c(existing_tokens, token)
            break
          }
        }
      }
      
      # Create new entries
      new_entries <- data.frame(
        object = new_objects,
        token = new_tokens,
        date_created = as.character(Sys.time()),
        date_updated = as.character(Sys.time()),
        stringsAsFactors = FALSE
      )
      
      # Write to database
      if (nrow(new_entries) > 0) {
        self$db_ops$write_to_tokens_table(new_entries, token_table_name)
        private$log_message(sprintf("Added new entries to tokens table (n = %d)", nrow(new_entries)))
        
        # Update token_table with new entries
        token_table <- rbind(token_table, new_entries)
      }
      
      # Clean up
      rm(list = ls(envir = table_cache), envir = table_cache)
      
      invisible(token_table)
    }
  ),
  
  private = list(
    table_cache = NULL,
    
    log_message = function(msg) {
      message(private$format_message(msg))
    },
    
    format_message = function(msg) {
      sprintf("[Session %s] %s", self$session_id, msg)
    },
    
    # Process a match in the staged JSON data
    process_match = function(pattern, json_str, staged_data_lookup) {
      parts <- regmatches(pattern, regexec('(\\w+)\\["([^"]+)", "([^"]+)"\\]', pattern))[[1]]
      
      if (length(parts) == 4) {
        table_name <- parts[2]
        field_name <- parts[3]
        column_name <- parts[4]
        
        # Get the corresponding staged data table
        staged_json_data <- staged_data_lookup[[table_name]]
        
        if (!is.null(staged_json_data)) {
          matching_row <- staged_json_data[gsub('"', '', staged_json_data$field_name) == field_name, ]
          
          if (nrow(matching_row) > 0) {
            replacement_value <- matching_row[[column_name]]
            
            # If the replacement value looks like a JSON array or object string, parse it
            if (grepl("^\\[|^\\{", replacement_value)) {
              tryCatch({
                parsed_value <- jsonlite::fromJSON(replacement_value)
                replacement_value <- jsonlite::toJSON(parsed_value, auto_unbox = TRUE)
              }, error = function(e) {
                replacement_value <- jsonlite::toJSON(replacement_value, auto_unbox = TRUE)
              })
            } else {
              replacement_value <- jsonlite::toJSON(replacement_value, auto_unbox = TRUE)
            }
            
            # Replace the pattern with the actual value
            json_str <- gsub(pattern, replacement_value, json_str, fixed = TRUE)
          }
        }
      }
      return(json_str)
    }
  )
)
