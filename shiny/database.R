# database.R

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

# Database operations class for managing database tables and queries
db_operations <- R6::R6Class(
  "Database Operations",
  public = list(
    session_id = NULL,
    pool = NULL,
    
    initialize = function(pool, session_id) {
      self$pool <- pool
      self$session_id <- session_id
    },
    
    create_tokens_table = function(token_table_name) {
      if (is.null(token_table_name) || !is.character(token_table_name)) {
        stop(private$format_message("Invalid token_table_name"))
      }
      
      # Sanitize table name
      if (!grepl("^[a-zA-Z0-9_]+$", token_table_name)) {
        stop(private$format_message("Invalid table name format"))
      }
      
      create_table_query <- sprintf("
        CREATE TABLE IF NOT EXISTS %s (
            id SERIAL PRIMARY KEY,
            object TEXT,
            token TEXT UNIQUE,
            date_created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            date_updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );", token_table_name)
      
      create_function_query <- "
        CREATE OR REPLACE FUNCTION update_date_updated_column()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.date_updated = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        $$ language 'plpgsql';"
      
      # Separate queries for dropping and creating trigger
      drop_trigger_query <- sprintf("
        DROP TRIGGER IF EXISTS update_%s_date_updated ON %s;", 
                                    token_table_name, token_table_name)
      
      create_trigger_query <- sprintf("
        CREATE TRIGGER update_%s_date_updated
            BEFORE UPDATE ON %s
            FOR EACH ROW
            EXECUTE FUNCTION update_date_updated_column();", 
                                      token_table_name, token_table_name)
      
      tryCatch({
        # Get a direct connection from the pool
        conn <- pool::poolCheckout(self$pool)
        
        # Ensure connection is valid
        if (!DBI::dbIsValid(conn)) {
          stop("Invalid database connection")
        }
        
        # Start transaction
        DBI::dbBegin(conn)
        
        # Execute queries in sequence
        DBI::dbExecute(conn, create_table_query)
        private$log_message("Created table if it didn't exist")
        
        DBI::dbExecute(conn, create_function_query)
        private$log_message("Created update function")
        
        DBI::dbExecute(conn, drop_trigger_query)
        private$log_message("Dropped existing trigger if it existed")
        
        DBI::dbExecute(conn, create_trigger_query)
        private$log_message("Created trigger")
        
        # Commit transaction
        DBI::dbCommit(conn)
        private$log_message("Table tokens was created or already exists")
        
      }, error = function(e) {
        # Rollback on error
        if (exists("conn") && !is.null(conn) && DBI::dbIsValid(conn)) {
          DBI::dbRollback(conn)
        }
        private$log_message(sprintf("An error occurred: %s", e$message))
        stop(private$format_message(sprintf("Failed to create tokens table: %s", e$message)))
        
      }, finally = {
        # Return connection to pool
        if (exists("conn") && !is.null(conn)) {
          pool::poolReturn(conn)
        }
      })
    },
    
    write_to_tokens_table = function(data, token_table_name) {
      required_fields <- c("object", "token", "date_created", "date_updated")
      if (!all(required_fields %in% names(data))) {
        stop(private$format_message("The data frame must contain fields: object, token, date_created, date_updated"))
      }
      
      if (!is.data.frame(data) || nrow(data) == 0) {
        stop(private$format_message("Invalid data provided: must be a non-empty data frame"))
      }
      
      tryCatch({
        # Get a direct connection from the pool
        conn <- pool::poolCheckout(self$pool)
        
        # Start transaction
        DBI::dbBegin(conn)
        
        # Write data
        DBI::dbWriteTable(
          conn,
          name = token_table_name,
          value = data,
          append = TRUE,
          row.names = FALSE
        )
        
        # Commit transaction
        DBI::dbCommit(conn)
        private$log_message("Successfully wrote to tokens table")
        
      }, error = function(e) {
        # Rollback on error
        if (exists("conn") && !is.null(conn) && DBI::dbIsValid(conn)) {
          DBI::dbRollback(conn)
        }
        private$log_message(sprintf("An error occurred while writing to tokens table: %s", e$message))
        stop(private$format_message(sprintf("Failed to write to tokens table: %s", e$message)))
        
      }, finally = {
        # Return connection to pool
        if (exists("conn") && !is.null(conn)) {
          pool::poolReturn(conn)
        }
      })
    },
    
    check_table_exists = function(table_name) {
      if (is.null(table_name) || !is.character(table_name)) {
        stop(private$format_message("Invalid table_name"))
      }
      
      tryCatch({
        # Get a direct connection from the pool
        conn <- pool::poolCheckout(self$pool)
        
        # Check if table exists
        exists <- DBI::dbExistsTable(conn, table_name)
        private$log_message(sprintf("Table %s exists: %s", table_name, exists))
        return(exists)
        
      }, error = function(e) {
        private$log_message(sprintf("Error checking table %s: %s", table_name, e$message))
        return(FALSE)
        
      }, finally = {
        # Return connection to pool
        if (exists("conn") && !is.null(conn)) {
          pool::poolReturn(conn)
        }
      })
    },
    
    read_table = function(table_name) {
      if (is.null(table_name) || !is.character(table_name) || length(table_name) != 1) {
        stop(private$format_message("Invalid 'table_name'. It must be a non-null, single-character string."))
      }
      
      max_retries <- 3
      attempt <- 1
      result <- NULL
      
      while (attempt <= max_retries) {
        tryCatch({
          # Get a direct connection from the pool
          conn <- pool::poolCheckout(self$pool)
          
          # Start transaction
          DBI::dbBegin(conn)
          
          # Execute query
          query <- paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(conn, table_name), ";")
          result <- DBI::dbGetQuery(conn, query)
          
          # Commit transaction
          DBI::dbCommit(conn)
          
          private$log_message(sprintf("Successfully read '%s' table on attempt %d", table_name, attempt))
          
          # Exit loop on success
          break
          
        }, error = function(e) {
          # Rollback on error
          if (exists("conn") && !is.null(conn) && DBI::dbIsValid(conn)) {
            DBI::dbRollback(conn)
          }
          private$log_message(sprintf("Attempt %d failed for '%s' table: %s", attempt, table_name, e$message))
          
        }, finally = {
          # Return connection to pool
          if (exists("conn") && !is.null(conn)) {
            pool::poolReturn(conn)
          }
        })
        
        attempt <- attempt + 1
        Sys.sleep(1) # Optional: Brief delay before retrying
      }
      
      if (is.null(result)) {
        private$log_message(sprintf("Failed to read '%s' table after %d attempts", table_name, max_retries))
        stop(private$format_message(sprintf("Could not read '%s' table after multiple attempts.", table_name)))
      }
      
      return(result)
    }
  ),
  
  private = list(
    log_message = function(msg) {
      message(private$format_message(msg))
    },
    format_message = function(msg) {
      sprintf("[Session %s] %s", self$session_id, msg)
    }
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
      get_groups_from_config <- function(config_json) {
        if (is.null(config_json) || config_json == "" || is.na(config_json)) {
          return(character(0))
        }
        
        tryCatch({
          config <- jsonlite::fromJSON(config_json)
          if (!is.null(config) && 
              is.list(config) && 
              !is.null(config$table_name) && 
              !is.null(config$group_col)) {
            
            table_data <- read_cached_table(config$table_name)
            if (!is.null(table_data) && 
                is.data.frame(table_data) && 
                config$group_col %in% names(table_data)) {
              return(unique(table_data[[config$group_col]]))
            }
          }
          return(character(0))
        }, error = function(e) {
          private$log_message(sprintf("Error parsing config JSON: %s", e$message))
          return(character(0))
        })
      }
      
      # Extract all groups from valid configs
      all_groups <- tryCatch({
        valid_configs <- surveys_data$config_json[!is.na(surveys_data$config_json) & 
                                                    surveys_data$config_json != ""]
        
        groups <- lapply(valid_configs, get_groups_from_config)
        unique_groups <- unique(unlist(groups))
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
        private$log_message(sprintf("Added %d new entries to tokens table", nrow(new_entries)))
        
        # Update token_table with new entries
        token_table <- rbind(token_table, new_entries)
      }
      
      # Clean up
      rm(list = ls(envir = table_cache), envir = table_cache)
      
      invisible(token_table)
    }
  ),
  private = list(
    log_message = function(msg) {
      message(private$format_message(msg))
    },
    format_message = function(msg) {
      sprintf("[Session %s] %s", self$session_id, msg)
    }
  )
)
