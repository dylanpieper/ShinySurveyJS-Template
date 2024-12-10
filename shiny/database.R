# Database Pool class for managing database connections
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

# Database Operations class for managing database tables and queries
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
      create_table_query <- "
        CREATE TABLE IF NOT EXISTS tokens (
          object TEXT,
          token TEXT,
          type TEXT
        );
      "
      tryCatch({
        pool::poolWithTransaction(self$pool, function(conn) {
          DBI::dbExecute(conn, create_table_query)
        })
        private$log_message("Table 'tokens' was created or already exists")
      }, error = function(e) {
        private$log_message(sprintf("An error occurred: %s", e$message))
      })
    },
    
    write_to_tokens_table = function(data) {
      required_fields <- c("object", "token", "type")
      if (!all(required_fields %in% names(data))) {
        stop(private$format_message("The data frame must contain fields: 'object', 'token', and 'type'"))
      }
      
      tryCatch({
        pool::poolWithTransaction(self$pool, function(conn) {
          dbWriteTable(
            conn,
            name = "tokens",
            value = data,
            append = TRUE,
            row.names = FALSE
          )
        })
        private$log_message("Successfully wrote to 'tokens' table")
      }, error = function(e) {
        private$log_message(sprintf("An error occurred while writing to 'tokens' table: %s", e$message))
      })
    },
    
    delete_from_tokens_table = function(objects_to_remove) {
      placeholders <- paste(sprintf("$%d", seq_along(objects_to_remove)), collapse = ",")
      query <- sprintf("DELETE FROM tokens WHERE object IN (%s)", placeholders)
      
      tryCatch({
        result <- pool::poolWithTransaction(self$pool, function(conn) {
          DBI::dbExecute(conn, query, objects_to_remove)
        })
        private$log_message(sprintf("Successfully deleted %d rows from tokens table", result))
        return(result)
      }, error = function(e) {
        private$log_message(sprintf("An error occurred while deleting from tokens table: %s", e$message))
        return(0)
      })
    },
    
    create_dynamic_field_tables = function() {
      config <- yaml::read_yaml("dynamic_fields.yml")
      if (!"fields" %in% names(config) || !is.list(config$fields)) {
        stop(private$format_message("The configuration file must include a 'fields' list"))
      }
      
      for (field_config in config$fields) {
        table_name <- field_config$table_name
        group_col <- field_config$group_col
        choices_col <- field_config$choices_col
        fields <- c(group_col, choices_col)
        create_table_query <- sprintf(
          "CREATE TABLE IF NOT EXISTS %s (%s);",
          table_name,
          paste(sprintf("%s TEXT", fields), collapse = ", ")
        )
        
        tryCatch({
          pool::poolWithTransaction(self$pool, function(conn) {
            DBI::dbExecute(conn, create_table_query)
          })
          private$log_message(sprintf("Table '%s' has been created (or already exists)", table_name))
        }, error = function(e) {
          private$log_message(sprintf("An error occurred while creating table: %s", e$message))
        })
      }
    },
    
    check_table_exists = function(table_name) {
      tryCatch({
        exists <- DBI::dbExistsTable(self$pool, table_name)
        private$log_message(sprintf("Table %s exists: %s", table_name, exists))
        return(exists)
      }, error = function(e) {
        private$log_message(sprintf("Error checking table %s: %s", table_name, e$message))
        return(FALSE)
      })
    },
    
    read_table = function(table_name) {
      query <- paste0("SELECT * FROM ", table_name, ";")
      tryCatch({
        table_df <- pool::poolWithTransaction(self$pool, function(conn) {
          DBI::dbGetQuery(conn, query)
        })
        private$log_message(sprintf("Successfully read '%s' table", table_name))
        return(table_df)
      }, error = function(e) {
        private$log_message(sprintf("An error occurred while reading '%s' table: %s", table_name, e$message))
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

# Database Setup class for initializing database and managing tokens
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
      if (nrow(token_table) > 0 && !all(token_table$type %in% c("Group", "Survey"))) {
        stop(private$format_message("'type' column must only include the values 'Group' or 'Survey'"))
      }
      
      if (!is.data.frame(token_table)) {
        stop(private$format_message("'token_table' must be a data frame"))
      }
      
      if (missing(mode)) {
        stop(private$format_message("The 'mode' argument must be provided"))
      }
      
      if (!mode %in% c("initial", "tokens")) {
        stop(private$format_message("Invalid 'mode': Accepted values are 'initial' or 'tokens'"))
      }
      
      if (!identical(sort(names(token_table)), sort(c("object", "token", "type")))) {
        stop(private$format_message("'token_table' must have exactly the columns: 'object', 'token', and 'type'"))
      }
      
      tryCatch({
        if (mode == "initial") {
          private$log_message("Setting up database in 'initial' mode")
          self$db_ops$create_tokens_table()
          self$db_ops$create_dynamic_field_tables()
          self$generate_tokens(token_table)
          private$log_message("Database setup completed in 'initial' mode")
        }
        
        if (mode == "tokens") {
          private$log_message("Generating tokens in 'tokens' mode")
          self$generate_tokens(token_table)
          private$log_message("Token generation completed")
        }
      }, error = function(e) {
        private$log_message(sprintf("An error occurred during setup: %s", e$message))
        stop(private$format_message("Database setup failed"))
      })
    },
    
    generate_tokens = function(token_table = NULL) {
      source("shiny/tokens.R")
      
      config <- yaml::read_yaml("dynamic_fields.yml")
      table_cache <- new.env()
      
      read_cached_table <- function(table_name) {
        if (!exists(table_name, envir = table_cache)) {
          assign(table_name, self$db_ops$read_table(table_name), envir = table_cache)
        }
        get(table_name, envir = table_cache)
      }
      
      all_groups <- tryCatch({
        groups <- unlist(lapply(config$fields, function(field_config) {
          table_data <- read_cached_table(field_config$table_name)
          unique(table_data[[field_config$group_col]])
        }))
        unique(groups[!is.na(groups)])
      }, error = function(e) {
        private$log_message(sprintf("Error reading table data: %s", e$message))
        return(NULL)
      })
      
      if (is.null(all_groups)) {
        private$log_message("Function aborted due to error in reading table data")
        return(invisible(token_table))
      }
      
      all_surveys <- unique(sub("\\.json$", "", list.files("www/", pattern = "*.json", full.names = FALSE)))
      
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
      
      if (is.null(token_table)) {
        token_table <- data.frame(
          object = character(),
          token = character(),
          type = character(),
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
        
        new_entries <- data.frame(
          object = new_objects$object,
          token = new_tokens,
          type = new_objects$type,
          stringsAsFactors = FALSE
        )
        
        self$db_ops$write_to_tokens_table(new_entries)
        private$log_message(sprintf("Added %d new entries to 'tokens' table", nrow(new_entries)))
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
