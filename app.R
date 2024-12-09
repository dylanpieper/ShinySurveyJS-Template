# ShinySurveyJS app

# if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
# pak::pkg_install(c("R6", "dotenv", "shiny", "jsonlite", "shinyjs", "httr", "DBI", "RPostgres", "yaml", "future"))

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
source("shiny/survey.R")
source("shiny/messages.R")
source("shiny/database.R")

# If TRUE, use tokens for survey access in the URL query
# If FALSE, use survey name directly
token_active <- TRUE

# Define class for database state
DBState <- R6::R6Class(
  "DBState",
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
      private$log_message("DBState initialized")
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

db_state <- DBState$new()
plan(multisession)

ui <- fluidPage(
  useShinyjs(),
  messageUI(),
  div(id = "surveyContainer",
      surveyUI("survey")
  ),
  tableOutput("surveyData")
)

server <- function(input, output, session) {
  session_db_state <- DBState$new(session$token)
  tokens_data <- reactiveVal(NULL)
  
  observe({
    req(session)
    
    if (!session_db_state$is_initialized()) {
      session_db_state$set_initialized()
      
      if (token_active) {
        initial_tokens <- read_table(session_db_state$pool, "tokens", session$token)
        session_db_state$set_tokens(initial_tokens)
        tokens_data(initial_tokens)
      } else {
        empty_tokens <- data.frame(
          object = character(),
          token = character(),
          type = character(),
          stringsAsFactors = FALSE
        )
        session_db_state$set_tokens(empty_tokens)
        tokens_data(empty_tokens)
      }
      
      # Pass session$token explicitly to future to ensure it is available inside the future process
      future({
        # Create a new pool inside the future process
        future_pool <- create_db_pool()
        
        tryCatch({
          # Pass session$token explicitly to the future
          message(sprintf("[Session %s] Database setup started in future", session$token))
          
          # Make sure to set up the database for the future process
          if (token_active && !is.null(initial_tokens) && nrow(initial_tokens) > 0) {
            setup_database(future_pool, "tokens", initial_tokens, session_id = session$token)
          } else {
            setup_database(future_pool, "initial", session_id = session$token)
          }
          
          message(sprintf("[Session %s] Database setup completed in future", session$token))
          TRUE
        }, error = function(e) {
          message(sprintf("[Session %s] Database setup error in future: %s", 
                          session$token, e$message))
          FALSE
        }, finally = {
          # Close the pool in the future process to avoid lingering connections
          if (!is.null(future_pool) && pool::dbIsValid(future_pool)) {
            pool::poolClose(future_pool)
            message(sprintf("[Session %s] Future pool closed", session$token))
          }
        })
      }, seed = NULL)
    }
  })
  
  observe({
    req(tokens_data())
    
    if (token_active) {
      handle_url_parameters(session, tokens_data)
      survey_data <- surveyServer(input, output, session, 
                                  token_active = TRUE, 
                                  token_table = tokens_data(),
                                  pool = session_db_state$get_pool(),
                                  session_id = session$token)
    } else {
      handle_url_parameters_tokenless(session, tokens_data)
      survey_data <- surveyServer(input, output, session, 
                                  token_active = FALSE,
                                  pool = session_db_state$get_pool(),
                                  session_id = session$token)
    }
  })
  
  session$onSessionEnded(function() {
    message(sprintf("[Session %s] Session ended", session$token))
    session_db_state$close_pool()
  })
}

shinyApp(ui = ui, server = server)
