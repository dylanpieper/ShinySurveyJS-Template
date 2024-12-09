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
  session_db_state <- db_state$new(session$token)
  tokens_data <- reactiveVal(NULL)
  
  observe({
    req(session)
    
    if (!session_db_state$is_initialized()) {
      session_db_state$set_initialized()
      
      table_exists <- check_table_exists(session_db_state$get_pool(), "tokens", session$token)
      
      if (token_active && table_exists) {
        initial_tokens <- read_table(session_db_state$get_pool(), "tokens", session$token)
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
      
      future({
        Sys.sleep(2)
        
        future_pool <- create_db_pool()
        
        tryCatch({
          message(sprintf("[Session %s] Database setup started in future", session$token))
          
          if (token_active && !is.null(initial_tokens) && nrow(initial_tokens) > 0) {
            setup_database(future_pool, "tokens", initial_tokens, session_id = session$token)
          } else if(token_active) {
            setup_database(future_pool, "initial", initial_tokens, session_id = session$token)
          }
          
          message(sprintf("[Session %s] Database setup completed in future", session$token))
          TRUE
        }, error = function(e) {
          message(sprintf("[Session %s] Database setup error in future: %s", 
                          session$token, e$message))
          FALSE
        }, finally = {
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
