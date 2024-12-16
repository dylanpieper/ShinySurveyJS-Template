# Shiny options
options(shiny.maxRequestSize = 10*1024^2)   # Set max upload size to 10MB
options(shiny.host = '0.0.0.0')             # Allow connections from any IP
options(shiny.port = 3838)                  # Set port (optional)

# Set worker count and timeout
options(shiny.workers = 100)                # Allow up to 100 concurrent users
options(shiny.idle_timeout = 1800)          # Timeout idle sessions after 30 minutes

# Optional performance settings
options(shiny.sanitize.errors = FALSE)      # Disable error sanitization for better performance
options(shiny.autoreload = FALSE)           # Disable autoreload for production