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
    create_tokens_table = function() {
      # Create table query
      create_table_query <- "
    CREATE TABLE IF NOT EXISTS tokens (
        id SERIAL PRIMARY KEY,
        object TEXT,
        token TEXT,
        date_created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        date_updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    );"
      
      # Create function query
      create_function_query <- "
    CREATE OR REPLACE FUNCTION update_date_updated_column()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW.date_updated = CURRENT_TIMESTAMP;
        RETURN NEW;
    END;
    $$ language 'plpgsql';"
      
      # Create trigger query
      create_trigger_query <- "
    CREATE OR REPLACE TRIGGER update_tokens_date_updated
        BEFORE UPDATE ON tokens
        FOR EACH ROW
        EXECUTE FUNCTION update_date_updated_column();"
      
      tryCatch(
        {
          pool::poolWithTransaction(self$pool, function(conn) {
            DBI::dbExecute(conn, create_table_query)
            DBI::dbExecute(conn, create_function_query)
            DBI::dbExecute(conn, create_trigger_query)
          })
          private$log_message("Table 'tokens' was created or already exists")
        },
        error = function(e) {
          private$log_message(sprintf("An error occurred: %s", e$message))
        }
      )
    },
    write_to_tokens_table = function(data) {
      required_fields <- c("object", "token", "date_created", "date_updated")
      if (!all(required_fields %in% names(data))) {
        stop(private$format_message("The data frame must contain fields: id, object, token, date_created, date_updated"))
      }
      
      tryCatch(
        {
          pool::poolWithTransaction(self$pool, function(conn) {
            DBI::dbWriteTable(
              conn,
              name = "tokens",
              value = data,
              append = TRUE,
              row.names = FALSE
            )
          })
          private$log_message("Successfully wrote to 'tokens' table")
        },
        error = function(e) {
          private$log_message(sprintf("An error occurred while writing to 'tokens' table: %s", e$message))
        }
      )
    },
    check_table_exists = function(table_name) {
      tryCatch(
        {
          exists <- DBI::dbExistsTable(self$pool, table_name)
          private$log_message(sprintf("Table %s exists: %s", table_name, exists))
          return(exists)
        },
        error = function(e) {
          private$log_message(sprintf("Error checking table %s: %s", table_name, e$message))
          return(FALSE)
        }
      )
    },
    read_table = function(table_name) {
      query <- paste0("SELECT * FROM ", table_name, ";")
      tryCatch(
        {
          table_df <- pool::poolWithTransaction(self$pool, function(conn) {
            DBI::dbGetQuery(conn, query)
          })
          private$log_message(sprintf("Successfully read '%s' table", table_name))
          return(table_df)
        },
        error = function(e) {
          private$log_message(sprintf("An error occurred while reading '%s' table: %s", table_name, e$message))
          return(NULL)
        }
      )
    },
    filter_table = function(table_name, column_name = NULL, value = NULL, operator = "=") {
      # Input validation
      if (!self$check_table_exists(table_name)) {
        stop(private$format_message(sprintf("Table '%s' does not exist", table_name)))
      }
      
      # Validate operator
      valid_operators <- c("=", "<", ">", "<=", ">=", "<>", "LIKE")
      if (!operator %in% valid_operators) {
        stop(private$format_message("Invalid operator provided"))
      }
      
      # Sanitize table name
      if (!grepl("^[a-zA-Z0-9_]+$", table_name)) {
        stop(private$format_message("Invalid table name"))
      }
      
      # Sanitize column name if provided
      if (!is.null(column_name) && !grepl("^[a-zA-Z0-9_]+$", column_name)) {
        stop(private$format_message("Invalid column name"))
      }
      
      tryCatch({
        result <- pool::poolWithTransaction(self$pool, function(conn) {
          if (!is.null(column_name) && !is.null(value)) {
            # For character values, properly escape and quote
            if (is.character(value) || is.factor(value)) {
              value <- sprintf("'%s'", value)
            }
            
            # Construct and execute query
            query <- sprintf("SELECT * FROM %s WHERE %s %s %s", 
                             table_name, column_name, operator, value)
            DBI::dbGetQuery(conn, query)
          } else {
            # Return all rows if no filter
            query <- sprintf("SELECT * FROM %s", table_name)
            DBI::dbGetQuery(conn, query)
          }
        })
        
        private$log_message(sprintf("Successfully filtered '%s' table", table_name))
        return(result)
        
      }, error = function(e) {
        private$log_message(sprintf("An error occurred while filtering '%s' table: %s", 
                                    table_name, e$message))
        return(NULL)
      })
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
    setup_database = function(mode, token_table) {
      if (missing(mode)) {
        stop(private$format_message("The 'mode' argument must be provided"))
      }
      if (!mode %in% c("initial", "tokens")) {
        stop(private$format_message("Invalid 'mode': Accepted values are 'initial' or 'tokens'"))
      }
      
      if (!is.data.frame(token_table)) {
        stop(private$format_message("'token_table' must be a data frame"))
      }
      
      required_columns <- c("object", "token", "date_created", "date_updated")
      missing_columns <- setdiff(required_columns, names(token_table))
      
      if (length(missing_columns) > 0) {
        stop(private$format_message(sprintf(
          "'token_table' is missing required columns: %s",
          paste(missing_columns, collapse = ", ")
        )))
      }
      
      if (!is.character(token_table$object)) {
        stop(private$format_message("'object' must be character"))
      }
      if (!is.character(token_table$token)) {
        stop(private$format_message("'token' must be character"))
      }
      if (!is.character(token_table$date_created) && !is.na(token_table$date_created)) {
        stop(private$format_message("'date_created' must be NULL character"))
      }
      if (!is.character(token_table$date_updated) && !is.na(token_table$date_created)) {
        stop(private$format_message("'date_updated' must be NULL character"))
      }
      
      tryCatch(
        {
          if (mode == "initial") {
            private$log_message("Setting up database in 'initial' mode")
            self$db_ops$create_tokens_table()
            self$generate_tokens(token_table)
            private$log_message("Database setup completed in 'initial' mode")
          }
          
          if (mode == "tokens") {
            private$log_message("Generating tokens in 'tokens' mode")
            self$generate_tokens(token_table)
            private$log_message("Token generation completed")
          }
        },
        error = function(e) {
          private$log_message(sprintf("An error occurred during setup: %s", e$message))
          stop(private$format_message("Database setup failed"))
        }
      )
    },
    generate_tokens = function(token_table = NULL) {
      source("shiny/tokens.R")
      
      # Read surveys table and parse config_json
      surveys_data <- self$db_ops$read_table("surveys")
      table_cache <- new.env()
      
      # Function to parse JSON config and extract unique groups
      get_groups_from_config <- function(config_json, table_cache) {
        if (is.null(config_json) || config_json == "") return(character(0))
        
        tryCatch({
          config <- jsonlite::fromJSON(config_json)
          if (!is.null(config$table_name) && !is.null(config$group_col)) {
            table_data <- read_cached_table(config$table_name)
            return(unique(table_data[[config$group_col]]))
          }
        }, error = function(e) {
          private$log_message(sprintf("Error parsing config JSON: %s", e$message))
          return(character(0))
        })
        return(character(0))
      }
      
      read_cached_table <- function(table_name) {
        if (!exists(table_name, envir = table_cache)) {
          assign(table_name, self$db_ops$read_table(table_name), envir = table_cache)
        }
        get(table_name, envir = table_cache)
      }
      
      # Get all groups from config_json
      all_groups <- tryCatch({
        groups <- unlist(lapply(surveys_data$config_json[!is.na(surveys_data$config_json)], 
                                function(config) get_groups_from_config(config, table_cache)))
        unique(groups[!is.na(groups)])
      }, error = function(e) {
        private$log_message(sprintf("Error processing survey configurations: %s", e$message))
        return(NULL)
      })
      
      if (is.null(all_groups)) {
        private$log_message("Function aborted due to error in processing survey configurations")
        return(invisible(token_table))
      }
      
      # Get all survey names from the surveys table
      all_surveys <- surveys_data$survey_name[!is.na(surveys_data$survey_name)]
      
      duplicate_objects <- intersect(all_surveys, all_groups)
      if (length(duplicate_objects) > 0) {
        warning(private$format_message(sprintf("Found objects that exist as both surveys and groups: %s", 
                                               paste(duplicate_objects, collapse=", "))))
      }
      
      current_objects <- data.frame(
        object = c(all_surveys, all_groups),
        type = c(rep("Survey", length(all_surveys)), rep("Group", length(all_groups))),
        stringsAsFactors = FALSE
      )
      current_objects <- current_objects[!duplicated(current_objects$object), ]
      
      # Initialize token_table with new structure if NULL
      if (is.null(token_table)) {
        token_table <- data.frame(
          id = integer(),
          object = character(),
          token = character(),
          date_created = as.POSIXct(character()),
          date_updated = as.POSIXct(character()),
          stringsAsFactors = FALSE
        )
      }
      
      if (any(duplicated(token_table$object))) {
        warning(private$format_message("Removing duplicate objects from token table"))
        token_table <- token_table[!duplicated(token_table$object), ]
      }
      
      new_objects <- current_objects[!(current_objects$object %in% token_table$object), ]
      
      if (nrow(new_objects) == 0) {
        private$log_message("No updates needed for 'tokens' table")
        return(invisible(token_table))
      }
      
      if (nrow(new_objects) > 0) {
        existing_tokens <- token_table$token
        new_tokens <- character(nrow(new_objects))
        
        # Generate tokens
        for (i in seq_len(nrow(new_objects))) {
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
          object = new_objects$object,
          token = new_tokens,
          date_created = Sys.time(),
          date_updated = Sys.time(),
          stringsAsFactors = FALSE
        )
        
        # Write to database
        self$db_ops$write_to_tokens_table(new_entries)
        private$log_message(sprintf("Added %d new entries to 'tokens' table", nrow(new_entries)))
        
        # Update token_table with new entries
        token_table <- rbind(token_table, new_entries)
      }
      
      stopifnot("Duplicate objects found in final token table" = !any(duplicated(token_table$object)))
      stopifnot("Duplicate tokens found in final token table" = !any(duplicated(token_table$token)))
      
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
