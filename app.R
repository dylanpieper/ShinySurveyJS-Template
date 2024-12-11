# ShinySurveyJS App
# Manages multiple surveys using Shiny, SurveyJS, and PostgreSQL

# Packages ----

library(R6)
library(dotenv)
library(shiny)
library(jsonlite)
library(shinyjs)
library(httr)
library(DBI)
library(RPostgres)
library(yaml)
library(future)
library(promises)

# Source dependencies
source("shiny/survey.R")
source("shiny/messages.R")
source("shiny/database.R")

# Configuration
token_active <- FALSE  # Use tokens for survey access in URL query

# Initialize parallel processing
plan(multisession)

#' App State Manager
#' @description R6 class to manage application state
AppState <- R6::R6Class(
  "AppState",
  public = list(
    db_initialized = FALSE,
    current_survey = NULL,
    db_ops = NULL,
    db_pool = NULL,
    db_setup = NULL,
    
    initialize = function() {
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
      if (!is.null(self$db_pool$pool)) {
        self$db_pool$pool <- NULL
      }
      self$db_initialized <- FALSE
      self$db_ops <- NULL
      self$db_setup <- NULL
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
      surveyUI("survey")
    )
  )
)

# Server ----
server <- function(input, output, session) {
  # Initialize app state
  app_state <- AppState$new()
  
  # Reactive values
  rv <- reactiveValues(
    tokens_data = NULL,
    initialization_complete = FALSE
  )
  
  # Database Initialization
  observe({
    req(app_state$db_pool$pool)
    
    if (!rv$initialization_complete) {
      # Initialize database
      success <- app_state$init_database(session$token)
      
      if (success && token_active) {
        # Initialize tokens
        tryCatch({
          if (app_state$db_ops$check_table_exists("tokens")) {
            rv$tokens_data <- app_state$db_ops$read_table("tokens")
          } else {
            rv$tokens_data <- data.frame(
              object = character(),
              token = character(),
              date_created = character(),
              date_updated = character(),
              stringsAsFactors = FALSE
            )
          }
          
          # Async database setup
          future({
            setup_database_async(
              session_token = session$token,
              token_active = token_active,
              initial_tokens = rv$tokens_data
            )
          }) %...>%
            catch(function(e) {
              message(sprintf("Error in future: %s", e$message))
              FALSE
            })
          
        }, error = function(e) {
          message(sprintf("Error initializing tokens: %s", e$message))
        })
      }
      
      rv$initialization_complete <- TRUE
    }
  })
  
  # Survey initialization
  observe({
    req(rv$initialization_complete)
    req(app_state$db_ops)
    
    if (token_active) {
      req(rv$tokens_data)
      tokens_for_url <- data.frame(
        id = integer(),
        table_id = integer(),
        table_name = character(),
        object = character(),
        token = character(),
        date_created = character(),
        date_updated = character(),
        stringsAsFactors = FALSE
      )
      handle_url_parameters(session, reactive(tokens_for_url))
    } else {
      handle_url_parameters_tokenless(session)
    }
    
    # Initialize survey with token table
    app_state$current_survey <- surveyServer(
      input, output, session,
      token_active = token_active,
      token_table = reactive(rv$tokens_data),
      session_id = session$token,
      db_ops = app_state$db_ops
    )
  })
  
  # Clean up on session end
  session$onSessionEnded(function() {
    message(sprintf("[Session %s] Cleaning up session resources", session$token))
    app_state$cleanup()
  })
}

#' Async Database Setup
#' @param session_token The session token
#' @param token_active Whether token authentication is active
#' @param initial_tokens Initial tokens data
setup_database_async <- function(session_token, token_active, initial_tokens) {
  future_pool <- db_pool$new()
  future_ops <- db_operations$new(future_pool$pool, session_token)
  future_setup <- db_setup$new(future_ops, session_token)
  
  tryCatch({
    message(sprintf("[Session %s] Starting asynchronous database initialization", 
                    session_token))
    
    if (token_active) {
      if (!is.null(initial_tokens) && nrow(initial_tokens) > 0) {
        message(sprintf("[Session %s] Setting up database with existing tokens (%d records)", 
                        session_token, nrow(initial_tokens)))
        future_setup$setup_database("tokens", initial_tokens)
      } else {
        message(sprintf("[Session %s] Initializing empty token table", 
                        session_token))
        future_setup$setup_database("initial", initial_tokens)
      }
    }
    
    message(sprintf("[Session %s] Database setup completed successfully", 
                    session_token))
    
    TRUE
    
  }, error = function(e) {
    message(sprintf("[Session %s] Database setup failed: %s", 
                    session_token, e$message))
    FALSE
  }, finally = {
    if (!is.null(future_pool$pool) && pool::dbIsValid(future_pool$pool)) {
      pool::poolClose(future_pool$pool)
      message(sprintf("[Session %s] Database connection pool closed successfully", 
                      session_token))
    }
  })
}

# Launch app
shinyApp(ui = ui, server = server)
