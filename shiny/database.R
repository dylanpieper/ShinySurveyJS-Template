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
    message(sprintf("[Session %s] Table 'tokens' has been created (or already exists)", session_id))
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
  if(missing(token_table)) {
    token_table <- data.frame(
      object = "",
      token = "",
      type = ""
    )
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
  
  if (!all(token_table$type %in% c("Group", "Survey"))) {
    stop(sprintf("[Session %s] 'type' column must only include the values 'Group' or 'Survey'", session_id))
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

# Generate a unique token for all surveys and dynamic field groups
generate_tokens <- function(pool, token_table = NULL, session_id) {
  
  config <- read_yaml("dynamic_fields.yml")
  table_cache <- new.env()
  
  read_cached_table <- function(table_name) {
    if (!exists(table_name, envir = table_cache)) {
      assign(table_name, read_table(pool, table_name, session_id), envir = table_cache)
    }
    get(table_name, envir = table_cache)
  }
  
  all_groups <- tryCatch({
    unique(unlist(lapply(config$fields, function(field_config) {
      table_data <- read_cached_table(field_config$table_name)
      table_data[[field_config$group_col]]
    })))
  }, error = function(e) {
    message(sprintf("[Session %s] Error reading table data: %s", session_id, e$message))
    return(NULL)
  })
  
  if (is.null(all_groups)) {
    message(sprintf("[Session %s] Function aborted due to error in reading table data", session_id))
    return(invisible(token_table))
  }
  
  all_surveys <- sub("\\.json$", "", list.files("www/", pattern = "*.json", full.names = FALSE))
  
  current_objects <- unique(data.frame(
    object = c(all_surveys, all_groups),
    type = c(rep("Survey", length(all_surveys)), rep("Group", length(all_groups))),
    stringsAsFactors = FALSE
  ))
  
  objects_to_remove <- setdiff(token_table$object, current_objects$object)
  new_objects <- current_objects[!(current_objects$object %in% token_table$object), ]
  
  if (length(objects_to_remove) == 0 && nrow(new_objects) == 0) {
    message(sprintf("[Session %s] No updates needed for 'tokens' table", session_id))
    return(invisible(token_table))
  }
  
  if (any(duplicated(token_table$object))) {
    token_table <- token_table[!duplicated(token_table$object), ]
  }
  
  if (length(objects_to_remove) > 0) {
    delete_from_tokens_table(pool, objects_to_remove, session_id)
    token_table <- token_table[!(token_table$object %in% objects_to_remove), ]
    message(sprintf("[Session %s] Removed %d obsolete entries from 'tokens' table", session_id, length(objects_to_remove)))
  }
  
  if (nrow(new_objects) > 0) {
    existing_tokens <- token_table$token
    new_tokens <- replicate(nrow(new_objects), {
      repeat {
        token <- generate_unique_token(existing_tokens)
        if (!(token %in% existing_tokens)) {
          existing_tokens <- c(existing_tokens, token)
          break
        }
      }
      token
    })
    
    new_entries <- data.frame(
      object = new_objects$object,
      token = new_tokens,
      type = new_objects$type,
      stringsAsFactors = FALSE
    )
    
    write_to_tokens_table(pool, new_entries, session_id)
    message(sprintf("[Session %s] Added %d new entries to 'tokens' table", session_id, nrow(new_entries)))
    token_table <- rbind(token_table, new_entries)
  }
  
  if (any(duplicated(token_table$object))) {
    warning(sprintf("[Session %s] Unexpected duplicate objects found in final 'tokens' table", session_id))
  }
  if (any(duplicated(token_table$token))) {
    warning(sprintf("[Session %s] Unexpected duplicate tokens found in final 'tokens' table", session_id))
  }
  
  rm(list = ls(envir = table_cache), envir = table_cache)
  
  invisible(token_table)
}
