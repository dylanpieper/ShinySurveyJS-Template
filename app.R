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

# Source R6 classes and other dependencies
source("shiny/survey.R")
source("shiny/messages.R")
source("shiny/database.R")

# If TRUE, use tokens for survey access in the URL query
# If FALSE, use survey name directly
token_active <- FALSE
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
  # Initialize our R6 classes
  session_db_state <- db_state$new(session$token)
  db_pool_instance <- db_pool$new()
  db_ops <- db_operations$new(db_pool_instance$pool, session$token)
  db_setup_instance <- db_setup$new(db_ops, session$token)
  
  tokens_data <- reactiveVal(NULL)
  
  observe({
    req(session)
    
    if (!session_db_state$is_initialized()) {
      session_db_state$set_initialized()
      
      table_exists <- db_ops$check_table_exists("tokens")
      
      if (token_active && table_exists) {
        initial_tokens <- db_ops$read_table("tokens")
        session_db_state$set_tokens(initial_tokens)
        tokens_data(initial_tokens)
      } else {
        initial_tokens <- data.frame(
          object = character(),
          token = character(),
          type = character(),
          stringsAsFactors = FALSE
        )
        session_db_state$set_tokens(initial_tokens)
        tokens_data(initial_tokens)
      }
      
      # Setup database in background
      future({
        Sys.sleep(2)
        
        future_pool <- db_pool$new()
        future_ops <- db_operations$new(future_pool$pool, session$token)
        future_setup <- db_setup$new(future_ops, session$token)
        
        tryCatch({
          message(sprintf("[Session %s] Database setup started in future", session$token))
          
          if (token_active && !is.null(initial_tokens) && nrow(initial_tokens) > 0) {
            future_setup$setup_database("tokens", initial_tokens)
          } else if(token_active) {
            future_setup$setup_database("initial", initial_tokens)
          }
          
          message(sprintf("[Session %s] Database setup completed in future", session$token))
          TRUE
        }, error = function(e) {
          message(sprintf("[Session %s] Database setup error in future: %s", 
                          session$token, e$message))
          FALSE
        }, finally = {
          if (!is.null(future_pool$pool) && pool::dbIsValid(future_pool$pool)) {
            future_pool$pool <- NULL
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
                                  session_id = session$token,
                                  db_ops = db_ops)
    } else {
      handle_url_parameters_tokenless(session, tokens_data)
      survey_data <- surveyServer(input, output, session, 
                                  token_active = FALSE,
                                  session_id = session$token,
                                  db_ops = db_ops)
    }
  })
  
  session$onSessionEnded(function() {
    message(sprintf("[Session %s] Session ended", session$token))
    session_db_state$close_pool()
    db_pool_instance$pool <- NULL  # Clean up the pool
  })
}

shinyApp(ui = ui, server = server)
