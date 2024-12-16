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
          background: linear-gradient(135deg, #e8f7f4, #ffffff);
          z-index: 9999;
          display: flex;
          justify-content: center;
          align-items: center;
          flex-direction: column;
          font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
          font-size: clamp(2rem, 2vw, 1.25rem);
          color: #1a2b3c;
          text-align: center;
          letter-spacing: -0.01em;
        }
        /* Enhanced spinner with gradient border */
        .loading-spinner {
          width: 70px;
          height: 70px;
          border: 4px solid transparent;
          border-radius: 50%;
          background: linear-gradient(white, white) padding-box,
                    linear-gradient(45deg, #3498db, #2ecc71) border-box;
          animation: spin 1.2s cubic-bezier(0.4, 0, 0.2, 1) infinite;
          margin-bottom: 20px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
        }
        @keyframes spin {
          0% { transform: rotate(0deg) scale(1); }
          50% { transform: rotate(180deg) scale(0.95); }
          100% { transform: rotate(360deg) scale(1); }
        }
        /* Loading text animation */
        .loading-text {
          position: relative;
          display: inline-block;
        }
        .loading-text::after {
          content: '...';
          position: absolute;
          animation: ellipsis 1.5s infinite;
          margin-left: 4px;
        }
        @keyframes ellipsis {
          0% { content: '.'; }
          33% { content: '..'; }
          66% { content: '...'; }
          100% { content: '.'; }
        }
        /* Enhanced error styling */
        .error-message {
          font-size: clamp(2rem, 2.5vw, 1.5rem);
          font-weight: 600;
          color: #e74c3c;
          padding: 1rem 2rem;
          border-radius: 8px;
          background: rgba(231, 76, 60, 0.1);
          box-shadow: 0 2px 8px rgba(231, 76, 60, 0.15);
          max-width: 90%;
          margin: 0 auto;
        }
      "))
    ),
    div(
      id = "waitingMessage",
      class = "message-container",
      div(class = "loading-spinner"),
      div(class = "loading-text", "Loading Survey")
    ),
    div(
      id = "surveyNotFoundMessage",
      class = "message-container",
      style = "display: none;",
      div(class = "error-message", "⚠️ Survey Not Found")
    ),
    div(
      id = "surveyNotDefinedMessage",
      class = "message-container",
      style = "display: none;",
      div(class = "error-message", "❌ Survey Undefined")
    ),
    div(
      id = "invalidGroupIdMessage",
      class = "message-container",
      style = "display: none;",
      div(class = "error-message", "❌ Invalid Group ID")
    )
  )
}

# Helper function to hide one message and show another
hide_and_show_message <- function(hide_id, show_id) {
  shinyjs::hide(hide_id, anim = TRUE, animType = "fade", time = 1)
  shinyjs::show(show_id, anim = TRUE, animType = "fade", time = 1)
}
