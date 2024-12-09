# Define class for tracking the database state and token access
db_state <- R6::R6Class(
  "ShinySurveyJS database state",
  public = list(
    initialized = FALSE,
    session_id = NULL,
    tokens_data = NULL,
    pool = NULL,
    
    initialize = function(session_id = NULL) {
      self$initialized <- FALSE
      self$session_id <- session_id
      self$tokens_data <- NULL
      self$pool <- create_db_pool()
    },
    
    set_initialized = function() {
      self$initialized <- TRUE
      private$log_message("Session started")
    },
    
    is_initialized = function() {
      return(self$initialized)
    },
    
    set_session_id = function(id) {
      self$session_id <- id
      private$log_message("Session ID updated")
    },
    
    set_tokens = function(tokens) {
      self$tokens_data <- tokens
      private$log_message("Tokens data updated")
    },
    
    get_tokens = function() {
      return(self$tokens_data)
    },
    
    get_pool = function() {
      return(self$pool)
    },
    
    close_pool = function() {
      if (!is.null(self$pool) && pool::dbIsValid(self$pool)) {
        pool::poolClose(self$pool)
        self$pool <- NULL
        private$log_message("Pool closed")
      }
    }
  ),
  
  private = list(
    log_message = function(msg) {
      if (!is.null(self$session_id)) {
        # Use sprintf to ensure session ID is included in the message
        message(sprintf("[Session %s] %s", self$session_id, msg))
      } else {
        message("[No Session] %s", msg)  # Ensure this correctly handles the case where session ID is missing
      }
    }
  )
)

create_db_pool <- function() {
  dotenv::load_dot_env()
  
  pool::dbPool(
    Postgres(),
    host = Sys.getenv("DB_HOST"),
    port = Sys.getenv("DB_PORT"),
    dbname = Sys.getenv("DB_NAME"),
    user = Sys.getenv("DB_USER"),
    password = Sys.getenv("DB_PASSWORD"),
    minSize = 1,
    maxSize = Inf
  )
}

# Create the 'tokens' table if it doesn't exist
create_tokens_table <- function(pool, session_id) {
  create_table_query <- "
    CREATE TABLE IF NOT EXISTS tokens (
      object TEXT,
      token TEXT,
      type TEXT
    );
  "
  tryCatch({
    pool::poolWithTransaction(pool, function(conn) {
      dbExecute(conn, create_table_query)
    })
    message(sprintf("[Session %s] Table 'tokens' was created or already exists", session_id))
  }, error = function(e) {
    message(sprintf("[Session %s] An error occurred: %s", session_id, e$message))
  })
}

write_to_tokens_table <- function(pool, data, session_id) {
  required_fields <- c("object", "token", "type")
  if (!all(required_fields %in% names(data))) {
    stop(sprintf("[Session %s] The data frame must contain fields: 'object', 'token', and 'type'", session_id))
  }
  
  tryCatch({
    pool::poolWithTransaction(pool, function(conn) {
      dbWriteTable(
        conn,
        name = "tokens",
        value = data,
        append = TRUE,
        row.names = FALSE
      )
    })
    message(sprintf("[Session %s] Successfully wrote to 'tokens' table", session_id))
  }, error = function(e) {
    message(sprintf("[Session %s] An error occurred while writing to 'tokens' table: %s", session_id, e$message))
  })
}

delete_from_tokens_table <- function(pool, objects_to_remove, session_id) {
  placeholders <- paste(sprintf("$%d", seq_along(objects_to_remove)), collapse = ",")
  query <- sprintf("DELETE FROM tokens WHERE object IN (%s)", placeholders)
  
  tryCatch({
    result <- pool::poolWithTransaction(pool, function(conn) {
      dbExecute(conn, query, objects_to_remove)
    })
    message(sprintf("[Session %s] Successfully deleted %d rows from tokens table", session_id, result))
    return(result)
  }, error = function(e) {
    message(sprintf("[Session %s] An error occurred while deleting from tokens table: %s", session_id, e$message))
    return(0)
  })
}

create_dynamic_field_tables <- function(pool, session_id) {
  config <- read_yaml("dynamic_fields.yml")
  if (!"fields" %in% names(config) || !is.list(config$fields)) {
    stop(sprintf("[Session %s] The configuration file must include a 'fields' list", session_id))
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
      pool::poolWithTransaction(pool, function(conn) {
        dbExecute(conn, create_table_query)
      })
      message(sprintf("[Session %s] Table '%s' has been created (or already exists)", session_id, table_name))
    }, error = function(e) {
      message(sprintf("[Session %s] An error occurred while creating table: %s", session_id, e$message))
    })
  }
}

check_table_exists <- function(pool, table_name, session_id) {
  tryCatch({
    exists <- dbExistsTable(pool, table_name)
    message(sprintf("[Session %s] Table %s exists: %s", session_id, table_name, exists))
    return(exists)
  }, error = function(e) {
    message(sprintf("[Session %s] Error checking table %s: %s", session_id, table_name, e$message))
    return(FALSE)
  })
}

read_table <- function(pool, table_name, session_id) {
  query <- paste0("SELECT * FROM ", table_name, ";")
  tryCatch({
    table_df <- pool::poolWithTransaction(pool, function(conn) {
      dbGetQuery(conn, query)
    })
    message(sprintf("[Session %s] Successfully read '%s' table", session_id, table_name))
    return(table_df)
  }, error = function(e) {
    message(sprintf("[Session %s] An error occurred while reading '%s' table: %s", session_id, table_name, e$message))
    return(NULL)
  })
}

setup_database <- function(pool, mode, token_table, session_id) {
  
  if (nrow(token_table) > 0 && !all(token_table$type %in% c("Group", "Survey"))) {
    stop(sprintf("[Session %s] 'type' column must only include the values 'Group' or 'Survey'", session_id))
  }
  
  if (!is.data.frame(token_table)) {
    stop(sprintf("[Session %s] 'token_table' must be a data frame", session_id))
  }
  
  if (missing(mode)) {
    stop(sprintf("[Session %s] The 'mode' argument must be provided", session_id))
  }
  
  if (!mode %in% c("initial", "tokens")) {
    stop(sprintf("[Session %s] Invalid 'mode': Accepted values are 'initial' or 'tokens'", session_id))
  }
  
  if (!identical(sort(names(token_table)), sort(c("object", "token", "type")))) {
    stop(sprintf("[Session %s] 'token_table' must have exactly the columns: 'object', 'token', and 'type'", session_id))
  }

  source("shiny/tokens.R")
  
  tryCatch({
    if (mode == "initial") {
      message(sprintf("[Session %s] Setting up database in 'initial' mode", session_id))
      create_tokens_table(pool, session_id)
      create_dynamic_field_tables(pool, session_id)
      generate_tokens(pool, token_table, session_id)
      message(sprintf("[Session %s] Database setup completed in 'initial' mode", session_id))
    }
    
    if (mode == "tokens") {
      message(sprintf("[Session %s] Generating tokens in 'tokens' mode", session_id))
      generate_tokens(pool, token_table, session_id)
      message(sprintf("[Session %s] Token generation completed", session_id))
    }
  }, error = function(e) {
    message(sprintf("[Session %s] An error occurred during setup: %s", session_id, e$message))
    stop(sprintf("[Session %s] Database setup failed", session_id))
  })
}

# Generate a unique token for all surveys, group_cols, and choice_cols
generate_tokens <- function(pool, token_table = NULL, session_id) {
  config <- read_yaml("dynamic_fields.yml")
  table_cache <- new.env()
  
  read_cached_table <- function(table_name) {
    if (!exists(table_name, envir = table_cache)) {
      assign(table_name, read_table(pool, table_name, session_id), envir = table_cache)
    }
    get(table_name, envir = table_cache)
  }
  
  # Get unique groups from all tables
  all_groups <- tryCatch({
    groups <- unlist(lapply(config$fields, function(field_config) {
      table_data <- read_cached_table(field_config$table_name)
      unique(table_data[[field_config$group_col]])
    }))
    unique(groups[!is.na(groups)])
  }, error = function(e) {
    message(sprintf("[Session %s] Error reading table data: %s", session_id, e$message))
    return(NULL)
  })
  
  if (is.null(all_groups)) {
    message(sprintf("[Session %s] Function aborted due to error in reading table data", session_id))
    return(invisible(token_table))
  }
  
  # Get unique surveys
  all_surveys <- unique(sub("\\.json$", "", list.files("www/", pattern = "*.json", full.names = FALSE)))
  
  # Check for duplicates between surveys and groups
  duplicate_objects <- intersect(all_surveys, all_groups)
  if (length(duplicate_objects) > 0) {
    warning(sprintf("[Session %s] Found objects that exist as both surveys and groups: %s", 
                    session_id, paste(duplicate_objects, collapse=", ")))
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
    warning(sprintf("[Session %s] Removing duplicate objects from token table", session_id))
    token_table <- token_table[!duplicated(token_table$object), ]
  }
  
  # objects_to_remove <- setdiff(token_table$object, current_objects$object)
  new_objects <- current_objects[!(current_objects$object %in% token_table$object), ]
  
  if (nrow(new_objects) == 0) { # length(objects_to_remove) == 0 && 
    message(sprintf("[Session %s] No updates needed for 'tokens' table", session_id))
    return(invisible(token_table))
  }
  
  # if (length(objects_to_remove) > 0) {
  #   delete_from_tokens_table(pool, objects_to_remove, session_id)
  #   token_table <- token_table[!(token_table$object %in% objects_to_remove), ]
  #   message(sprintf("[Session %s] Removed %d obsolete entries from 'tokens' table", 
  #                   session_id, length(objects_to_remove)))
  # }
  
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
    
    write_to_tokens_table(pool, new_entries, session_id)
    message(sprintf("[Session %s] Added %d new entries to 'tokens' table", 
                    session_id, nrow(new_entries)))
    token_table <- rbind(token_table, new_entries)
  }
  
  stopifnot("Duplicate objects found in final token table" = !any(duplicated(token_table$object)))
  stopifnot("Duplicate tokens found in final token table" = !any(duplicated(token_table$token)))
  
  rm(list = ls(envir = table_cache), envir = table_cache)
  
  invisible(token_table)
}
