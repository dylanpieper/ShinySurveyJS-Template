# Shiny options
if (!is.null(Sys.getenv("shiny_host"))) {
  options(shiny.host = Sys.getenv("shiny_host"))
}
if (!is.null(Sys.getenv("shiny_port"))) {
  options(shiny.port = as.numeric(Sys.getenv("shiny_port")))
}

# Set worker count and timeout
if (!is.null(Sys.getenv("shiny_workers"))) {
  options(shiny.workers = as.numeric(Sys.getenv("shiny_workers")))
}
if (!is.null(Sys.getenv("shiny_idle_timeout"))) {
  options(shiny.idle_timeout = as.numeric(Sys.getenv("shiny_idle_timeout")))
}

# Optional performance settings
if (!is.null(Sys.getenv("shiny_sanitize_errors"))) {
  options(shiny.sanitize.errors = as.logical(Sys.getenv("shiny_sanitize_errors")))
}
if (!is.null(Sys.getenv("shiny_autoreload"))) {
  options(shiny.autoreload = as.logical(Sys.getenv("shiny_autoreload")))
}