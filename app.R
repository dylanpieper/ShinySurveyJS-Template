# ShinySurveyJS App
# A template to host multiple surveys using Shiny + SurveyJS + PostgreSQL

# if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
# pak::pkg_install(c("R6", "dotenv", "shiny", "jsonlite", "shinyjs", "sass",
#                    "DBI", "RPostgres", "pool", future", "promises", "DT"))

# Packages ----
library(R6)
library(dotenv)
library(shiny)
library(jsonlite)
library(shinyjs)
library(sass)
library(DBI)
library(RPostgres)
library(pool)
library(future)
library(promises)
library(DT)

# Modules
source("shiny/shiny.R")
source("shiny/survey.R")
source("shiny/messages.R")
source("shiny/database.R")

# Global variables ----
dotenv::load_dot_env()

# Use tokens for survey access in URL query
token_active <- as.logical(Sys.getenv("token_active"))

# Show survey response as a table
show_response <- as.logical(Sys.getenv("show_response"))

# SQL table names
token_table_name <- Sys.getenv("token_table_name")
survey_table_name <- Sys.getenv("survey_table_name")

# Async cooldown time in seconds
async_cooldown <- as.numeric(Sys.getenv("async_cooldown"))

# Set future plan
plan(multisession)

# Initialize global database pool
global_pool <- pool::dbPool(
  RPostgres::Postgres(),
  host = Sys.getenv("DB_HOST"),
  port = Sys.getenv("DB_PORT"),
  dbname = Sys.getenv("DB_NAME"),
  user = Sys.getenv("DB_USER"),
  password = Sys.getenv("DB_PASSWORD"),
  minSize = 1,
  maxSize = Inf
)

# Register the callback to close the pool when the app stops
onStop(function() {
  if (!is.null(global_pool) && pool::dbIsValid(global_pool)) {
    pool::poolClose(global_pool)
    message("Global database connection pool closed")
  }
  
  # Clean up lock file
  if (file.exists("shiny_setup.lock")) {
    unlink("shiny_setup.lock")
  }
})

# Setup cooldown
.globals <- new.env()
.globals$last_setup_time <- NULL
.globals$setup_lock <- FALSE

# App state manager
AppState <- R6::R6Class(
  "AppState",
  public = list(
    db_initialized = FALSE,
    current_survey = NULL,
    db_ops = NULL,
    db_pool = NULL,
    db_setup = NULL,
    session_id = NULL,
    
    initialize = function(session_id) {
      self$session_id <- session_id
      self$db_pool <- db_pool$new()
    },
    
    init_database = function(session_token) {
      if (!self$db_initialized && !is.null(self$db_pool$pool)) {
        self$db_ops <- db_operations$new(self$db_pool$pool, session_token)
        self$db_setup <- db_setup$new(self$db_ops, session_token)
        self$db_initialized <- TRUE
        return(TRUE)
      }
      return(FALSE)
    },
    
    cleanup = function() {
      self$db_initialized <- FALSE
      self$db_ops <- NULL
      self$db_setup <- NULL
      message(sprintf("[Session %s] Session ended", 
                      self$session_id))
    }
  )
)

# Connection manager
ConnectionManager <- R6::R6Class(
  "ConnectionManager",
  private = list(
    .active_sessions = list(),
    .active_pools = list(),
    .max_concurrent_sessions = 1,
    .setup_cooldown = 30,
    .lock_file = file.path(tempdir(), "shiny_setup.lock"),
    .last_setup_file = file.path(tempdir(), "last_setup.txt"),
    
    acquire_setup_lock = function() {
      start_time <- Sys.time()
      timeout <- 5
      
      while (file.exists(private$.lock_file)) {
        if (as.numeric(difftime(Sys.time(), start_time, units = "secs")) > timeout) {
          return(FALSE)
        }
        Sys.sleep(0.1)
      }
      
      writeLines(as.character(Sys.time()), private$.lock_file)
      return(TRUE)
    },
    
    release_setup_lock = function() {
      if (file.exists(private$.lock_file)) {
        unlink(private$.lock_file)
      }
    },
    
    check_cooldown = function() {
      if (!file.exists(private$.last_setup_file)) {
        return(TRUE)
      }
      
      last_setup_time <- as.POSIXct(readLines(private$.last_setup_file)[1])
      current_time <- Sys.time()
      elapsed_time <- as.numeric(difftime(current_time, last_setup_time, units = "secs"))
      return(elapsed_time >= private$.setup_cooldown)
    },
    
    update_last_setup_time = function() {
      writeLines(as.character(Sys.time()), private$.last_setup_file)
    }
  ),
  
  public = list(
    initialize = function(max_concurrent_sessions = 1, setup_cooldown = 30) {
      private$.max_concurrent_sessions <- max_concurrent_sessions
      private$.setup_cooldown = setup_cooldown
      
      # Clean up stale files
      if (file.exists(private$.lock_file)) unlink(private$.lock_file)
      if (!file.exists(private$.last_setup_file)) {
        writeLines(as.character(Sys.time() - private$.setup_cooldown), private$.last_setup_file)
      }
    },
    
    request_setup = function(session_id) {
      if (!private$acquire_setup_lock()) {
        message(sprintf("[Session %s] Unable to acquire setup lock", session_id))
        return(FALSE)
      }
      
      tryCatch({
        if (!private$check_cooldown()) {
          last_setup_time <- as.POSIXct(readLines(private$.last_setup_file)[1])
          elapsed_time <- as.numeric(difftime(Sys.time(), last_setup_time, units = "secs"))
          time_remaining <- ceiling(private$.setup_cooldown - elapsed_time)
          message(sprintf("[Session %s] Async setup cooldown in effect (%d seconds remaining)", 
                          session_id, time_remaining))
          return(FALSE)
        }
        
        private$update_last_setup_time()
        private$.active_sessions[[session_id]] <- Sys.time()
        
        message(sprintf("[Session %s] Async setup request granted", session_id))
        return(TRUE)
      }, finally = {
        private$release_setup_lock()
      })
    },
    
    # [Previous get_pool and return_pool methods remain unchanged]
    get_pool = function(session_id) {
      if (is.null(private$.active_sessions[[session_id]])) {
        return(NULL)
      }
      
      if (!is.null(private$.active_pools[[session_id]])) {
        return(private$.active_pools[[session_id]])
      }
      
      tryCatch({
        new_pool <- pool::dbPool(
          drv = RPostgres::Postgres(),
          host = Sys.getenv("DB_HOST"),
          port = as.numeric(Sys.getenv("DB_PORT")),
          dbname = Sys.getenv("DB_NAME"),
          user = Sys.getenv("DB_USER"),
          password = Sys.getenv("DB_PASSWORD"),
          minSize = 1,
          maxSize = 1,
          idleTimeout = as.numeric(Sys.getenv("shiny_idle_timeout"))
        )
        
        private$.active_pools[[session_id]] <- new_pool
        return(new_pool)
        
      }, error = function(e) {
        message(sprintf("[Session %s] Error creating pool: %s", session_id, e$message))
        return(NULL)
      })
    },
    
    return_pool = function(session_id) {
      if (!is.null(private$.active_pools[[session_id]])) {
        pool <- private$.active_pools[[session_id]]
        pool::poolClose(pool)
        private$.active_pools[[session_id]] <- NULL
      }
      
      private$.active_sessions[[session_id]] <- NULL
      message(sprintf("[Session %s] Pool returned", session_id))
    }
  )
)

connection_manager <- ConnectionManager$new(
  max_concurrent_sessions = 1,
  setup_cooldown = async_cooldown
)

# UI ----
ui <- fluidPage(
  tags$head(tags$title("ShinySurveyJS")),
  useShinyjs(),
  messageUI(),
  
  # Main container
  div(
    id = "mainContainer",
    class = "container-fluid",
    
    # Survey container
    div(
      id = "surveyContainer",
      surveyUI("survey", theme = "defaultV2")
    ),
    
    # Survey data output
    shinyjs::hidden(
      div(
        id = "surveyDataContainer",
        style = "text-align: left; margin-top: 20px;",
        tags$p(tags$strong("Data Received:")),
        div(
          style = "display: flex;",
          DT::dataTableOutput("surveyData")
        )
      )
    )
  )
)

# Server ----
server <- function(input, output, session) {
  # Store global pool in user's session data
  session$userData$global_pool <- global_pool
  
  # Initialize app state
  app_state <- AppState$new(session_id = session$token)
  
  # Reactive values
  rv <- reactiveValues(
    tokens_data = NULL,
    initialization_complete = FALSE,
    survey_data = NULL
  )
  
  # Async database setup function
  setup_database_async <- function(session_token, token_active, initial_tokens,
                                   token_table_name, survey_table_name, conn_manager) {
    
    future_promise <- future({
      # Request setup from connection manager
      if (!conn_manager$request_setup(session_token)) {
        stop("Setup request denied (another setup is in progress)")
      }
      
      # Get pool from connection manager
      async_pool <- conn_manager$get_pool(session_token)
      if (is.null(async_pool)) {
        conn_manager$return_pool(session_token)
        stop("Failed to create database pool")
      }
      
      message(sprintf("[Session %s] Database pool created", session_token))
      
      tryCatch({
        # Create operations instance
        future_ops <- db_operations$new(async_pool, session_token)
        
        # Create setup instance
        future_setup <- db_setup$new(future_ops, session_token)
        
        # Check and create JSON stage
        stage_result <- future_setup$setup_json_stage(survey_table_name)
        
        # Handle token setup if enabled
        if (token_active) {
          if (!is.null(initial_tokens) && nrow(initial_tokens) > 0) {
            message(sprintf("[Session %s] Setting up database with existing tokens (n = %d)", 
                            session_token, nrow(initial_tokens)))
            
            token_result <- future_setup$setup_database(
              "tokens",
              initial_tokens,
              token_table_name,
              survey_table_name
            )
          } else {
            message(sprintf("[Session %s] Initializing empty tokens table", 
                            session_token))
            
            init_result <- future_setup$setup_database(
              "initial",
              initial_tokens,
              token_table_name,
              survey_table_name
            )
          }
        }
        
        # Verify final setup
        verify_result <- future_ops$verify_setup(
          token_table_name,
          survey_table_name
        )
        
        list(
          success = TRUE,
          error = NULL,
          tables = list(
            token = token_table_name,
            survey = survey_table_name
          )
        )
        
      }, error = function(e) {
        list(
          success = FALSE,
          error = e$message
        )
      }, finally = {
        conn_manager$return_pool(session_token)
      })
    }) %...>%
      catch(function(e) {
        list(
          success = FALSE,
          error = sprintf("Async error: %s", e$message)
        )
      })
    
    future_promise
  }
  
  # Modified observer for server.R
  observe({
    req(app_state$db_pool$pool)
    
    if (!rv$initialization_complete) {
      # Initialize database (non-blocking)
      success <- app_state$init_database(session$token)
      
      if (success && token_active) {
        # Initialize tokens data immediately
        tryCatch({
          if (app_state$db_ops$check_table_exists(token_table_name)) {
            rv$tokens_data <- app_state$db_ops$read_table(token_table_name)
          } else {
            rv$tokens_data <- data.frame(
              object = character(),
              token = character(),
              date_created = character(),
              date_updated = character(),
              stringsAsFactors = FALSE
            )
          }
          
          # Get tokens snapshot
          tokens_snapshot <- isolate(rv$tokens_data)
          
          # Launch async database setup without blocking
          promises::future_promise({
            setup_database_async(
              session_token = session$token,
              token_active = token_active,
              initial_tokens = tokens_snapshot,
              token_table_name = token_table_name,
              survey_table_name = survey_table_name,
              conn_manager = connection_manager
            )
          }, seed = TRUE) %...>% 
            then(function(result) {
              if (result$success) {
                message(sprintf("[Session %s] Async database setup completed successfully", 
                                session$token))
              } else {
                warning(sprintf("[Session %s] Async database setup failed: %s", 
                                session$token, result$error))
              }
            }) %...>%
            catch(function(e) {
              warning(sprintf("[Session %s] Error in async setup: %s", 
                              session$token, e$message))
            })
          
        }, error = function(e) {
          warning(sprintf("[Session %s] Error initializing tokens: %s", 
                          session$token, e$message))
        })
      }
      
      rv$initialization_complete <- TRUE
    }
  })
  
  # Helper function to initialize the database asynchronously
  init_database_async <- function(app_state, session_token) {
    promises::future_promise({
      if (!app_state$db_initialized && !is.null(app_state$db_pool$pool)) {
        app_state$db_ops <- db_operations$new(app_state$db_pool$pool, session_token)
        app_state$db_setup <- db_setup$new(app_state$db_ops, session_token)
        app_state$db_initialized <- TRUE
        TRUE
      } else {
        FALSE
      }
    }, seed = TRUE)
  }
  
  # Define survey server
  rv$survey_data <- surveyServer(
    input = input,
    output = output,
    session = session,
    token_active = token_active,
    token_table = reactive(rv$tokens_data),
    db_ops = app_state$db_ops,
    session_id = session$token,
    survey_table_name = survey_table_name,
    show_response = show_response
  )
  
  session$onSessionEnded(function() {
    app_state$cleanup()
  })
}

shinyApp(ui = ui, server = server)
