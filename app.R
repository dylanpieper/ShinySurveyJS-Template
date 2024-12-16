# ShinySurveyJS App
# Manages multiple surveys using Shiny, SurveyJS, and PostgreSQL

# if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
# pak::pkg_install(c("R6", "dotenv", "shiny", "jsonlite", "shinyjs", 
#                    "DBI", "RPostgres", "pool", future", "promises", "DT"))

# Packages ----
library(R6)
library(dotenv)
library(shiny)
library(jsonlite)
library(shinyjs)
library(DBI)
library(RPostgres)
library(pool)
library(future)
library(promises)
library(DT)

# Source modules
source("shiny/shiny.R")
source("shiny/survey.R")
source("shiny/messages.R")
source("shiny/database.R")

# Global variables ----
dotenv::load_dot_env()

# Use tokens for survey access in URL query
token_active <- as.logical(Sys.getenv("token_active"))
show_response <- as.logical(Sys.getenv("show_response")) # Show survey response
token_table_name <- Sys.getenv("token_table_name") # SQL table name
survey_table_name <- Sys.getenv("survey_table_name") # SQL table name

# Initialize parallel processing
plan(multisession)

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
      tryCatch({
        if (!is.null(self$db_pool$pool)) {
          # Check if pool is valid before closing
          if (pool::dbIsValid(self$db_pool$pool)) {
            pool::poolClose(self$db_pool$pool)
            message(sprintf("[Session %s] Session ended: Database connection pool closed successfully", 
                            self$session_id))
          }
          self$db_pool$pool <- NULL
        }
      }, error = function(e) {
        warning(sprintf("[Session %s] Error during pool cleanup: %s", 
                        self$session_id, e$message))
      }, finally = {
        self$db_initialized <- FALSE
        self$db_ops <- NULL
        self$db_setup <- NULL
      })
    }
  )
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
                                   token_table_name, survey_table_name) {
    
    promise <- future({
      # Randomly delay the setup for concurrent user load testing
      Sys.sleep(runif(1, 0, 10))
      future_pool <- db_pool$new()
      future_ops <- db_operations$new(future_pool$pool, session_token)
      future_setup <- db_setup$new(future_ops, session_token)
      
      tryCatch({
        message(sprintf("[Session %s] Starting async database services", session_token))
        
        future_setup$setup_staged_json(survey_table_name)
        
        if (token_active) {
          if (!is.null(initial_tokens) && nrow(initial_tokens) > 0) {
            message(sprintf("[Session %s] Setting up database with existing tokens (n = %d)", 
                            session_token, nrow(initial_tokens)))
            future_setup$setup_database("tokens", initial_tokens, token_table_name, survey_table_name)
          } else {
            message(sprintf("[Session %s] Initializing tokens table", session_token))
            future_setup$setup_database("initial", initial_tokens, token_table_name, survey_table_name)
          }
        }
        
        list(success = TRUE, error = NULL)
        
      }, error = function(e) {
        message(sprintf("[Session %s] Database setup failed: %s", session_token, e$message))
        list(success = FALSE, error = e$message)
      }, finally = {
        if (!is.null(future_pool$pool) && pool::dbIsValid(future_pool$pool)) {
          pool::poolClose(future_pool$pool)
          message(sprintf("[Session %s] Database connection pool closed successfully", 
                          session_token))
        }
      })
    }, seed = NULL) %...>%
      catch(function(e) {
        list(success = FALSE, error = e$message)
      })
    
    return(promise)
  }
  
  # Database initialization
  observe({
    req(app_state$db_pool$pool)
    
    if (!rv$initialization_complete) {
      # Initialize database
      success <- app_state$init_database(session$token)
      
      if (success && token_active) {
        # Initialize tokens
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
          
          # Get the current value of tokens_data before passing to future
          tokens_snapshot <- isolate(rv$tokens_data)
          
          # Launch async database setup
          future::future(setup_database_async(
            session_token = session$token,
            token_active = token_active,
            initial_tokens = tokens_snapshot,
            token_table_name = token_table_name,
            survey_table_name = survey_table_name
          ), seed = NULL) %...>% 
            then(function(result) {
              if (result$success) {
                message(sprintf("[Session %s] Async database setup completed successfully", session$token))
              } else {
                warning(sprintf("[Session %s] Async database setup failed: %s", 
                                session$token, result$error))
              }
            }) %...>%
            catch(function(e) {
              warning(sprintf("[Session %s] Error in async setup: %s", session$token, e$message))
            })
          
        }, error = function(e) {
          warning(sprintf("[Session %s] Error initializing tokens: %s", session$token, e$message))
        })
      }
      
      rv$initialization_complete <- TRUE
    }
  })
  
  # Initialize survey server
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
