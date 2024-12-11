# Style messages
messageUI <- function() {
  list(
    tags$head(
      tags$style(HTML("
        /* Base styling for all message containers */
        .message-container {
          position: fixed;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          background-color: white;
          z-index: 9999;
          display: flex;
          justify-content: center;
          align-items: center;
          flex-direction: column;
          font-family: Arial, sans-serif; /* Consistent font */
          font-size: 1.2em; /* Uniform font size */
          color: #333; /* Uniform text color */
          text-align: center;
        }

        /* Spinner for loading state */
        .loading-spinner {
          width: 60px;
          height: 60px;
          border: 6px solid #f3f3f3;
          border-top: 6px solid #3498db;
          border-radius: 50%;
          animation: spin 1s linear infinite;
          margin-bottom: 15px;
        }

        @keyframes spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }
      "))
    ),
    div(
      id = "waitingMessage",
      class = "message-container",
      div(class = "loading-spinner"),
      div("Loading survey...")
    ),
    div(
      id = "surveyNotFoundMessage",
      class = "message-container",
      style = "display: none;",
      div("Survey not found. Please check the URL and try again.")
    ),
    div(
      id = "surveyNotDefinedMessage",
      class = "message-container",
      style = "display: none;",
      div("No survey defined. Please provide a survey parameter in the URL.")
    )
  )
}
# Handle URL parameters and show appropriate messages
handle_url_parameters <- function(session, token_reactive) {
  observeEvent(session$clientData$url_search, {
    query <- parseQueryString(session$clientData$url_search)
    
    if (is.null(query$survey)) {
      hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
    } else {
      shinyjs::hide("waitingMessage", anim = TRUE, animType = "fade", time = 1)
    }
  }, ignoreInit = FALSE)
}

# Handle URL parameters and show appropriate messages
handle_url_parameters_tokenless <- function(session, token_reactive) {
  observeEvent(session$clientData$url_search, {
    query <- parseQueryString(session$clientData$url_search)
    
    if (is.null(query$survey)) {
      hide_and_show_message("waitingMessage", "surveyNotDefinedMessage")
    } else {
      shinyjs::hide("waitingMessage", anim = TRUE, animType = "fade", time = 1)
    }
    
  }, ignoreInit = FALSE)
}

# Helper function to hide one message and show another
hide_and_show_message <- function(hide_id, show_id) {
  shinyjs::hide(hide_id, anim = TRUE, animType = "fade", time = 1)
  shinyjs::show(show_id, anim = TRUE, animType = "fade", time = 1)
}
