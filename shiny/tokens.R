# Generate Tokens with a Flexible Vector Sampling Algorithm
#
# These functions offer a flexible approach to generating tokens by:
# - Using default vectors for categories when specific vectors are not provided
# - Allowing selective exclusion of vectors by setting them to FALSE
# - Enabling the use of custom vectors if provided, otherwise default vectors are used
# - Supporting dynamic vector injection through additional arguments passed via ellipsis (...)
# - Facilitating custom token generation with controlled randomization and uniqueness
#
# These show different ways to use the function:
# 1. Use defaults
# generate_token_options(colors = TRUE)  # Uses default_colors
# 
# # 2. Skip a category
# generate_token_options(colors = FALSE)  # No colors in tokens
# 
# # 3. Use custom values
# generate_token_options(colors = c("Ruby", "Sapphire"))  # Uses only these colors
# 
# # 4. Mix and match
# generate_token_options(
#   colors = c("Ruby", "Sapphire"),  # Custom colors
#   shapes = FALSE                   # No shapes
# )

# Helper function to process vector arguments
process_vector_arg <- function(vector_arg, default_vector) {
  if (is.logical(vector_arg)) {
    if (vector_arg) default_vector else NULL
  } else {
    vector_arg
  }
}

# Generate spelled number component
generate_spelled_number <- function() {
  numbers_below_20 <- c("Zero", "One", "Two", "Three", "Four", "Five", "Six", 
                        "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve", 
                        "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", 
                        "Eighteen", "Nineteen")
  tens <- c("Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", 
            "Ninety")
  hundreds <- "Hundred"
  
  num <- sample(0:999, 1)
  
  if (num < 20) {
    return(numbers_below_20[num + 1])
  } else if (num < 100) {
    return(generate_two_digit_number(num, numbers_below_20, tens))
  } else {
    return(generate_three_digit_number(num, numbers_below_20, tens, hundreds))
  }
}

# Helper function for two-digit numbers
generate_two_digit_number <- function(num, numbers_below_20, tens) {
  tens_part <- tens[(num %/% 10) - 1]
  units_part <- ifelse(num %% 10 == 0, "", numbers_below_20[(num %% 10) + 1])
  paste0(tens_part, units_part)
}

# Helper function for three-digit numbers
generate_three_digit_number <- function(num, numbers_below_20, tens, hundreds) {
  hundreds_part <- paste0(numbers_below_20[(num %/% 100) + 1], hundreds)
  remainder <- num %% 100
  
  if (remainder == 0) {
    return(hundreds_part)
  } else if (remainder < 20) {
    return(paste0(hundreds_part, numbers_below_20[remainder + 1]))
  } else {
    tens_part <- tens[(remainder %/% 10) - 1]
    units_part <- ifelse(remainder %% 10 == 0, "", numbers_below_20[(remainder %% 10) + 1])
    paste0(hundreds_part, tens_part, units_part)
  }
}

# Define default vectors
get_default_vectors <- function() {
  list(
    colors = c("Red", "Blue", "Green", "Yellow", "Purple", "Orange", "Pink", 
               "Brown", "Gray", "Black", "White", "Teal", "Maroon", "Navy", 
               "Olive", "Lime", "Cyan", "Magenta", "Turquoise", "Lavender", 
               "Crimson", "Indigo", "Coral", "Salmon", "Bronze", "Gold", 
               "Silver", "Plum", "Violet", "Azure", "Beige", "Khaki", 
               "Scarlet", "Ruby", "Emerald", "Sapphire", "Pearl", "Auburn",
               "Copper", "Burgundy", "Mauve", "Mustard", "Peach", "Rose"),
    
    cosmos = c("Sun", "Moon", "Star", "Sky", "Cloud", "Comet", "Galaxy", 
               "Orbit", "Planet", "Nebula", "Asteroid", "BlackHole", 
               "Supernova", "Quasar", "Pulsar", "Meteor", "Constellation", 
               "Cosmos", "Universe", "Stardust", "SolarWind", "RedGiant",
               "WhiteDwarf", "NeutronStar", "MilkyWay", "Andromeda", 
               "VoidSpace", "DarkMatter", "CosmicRay", "Magnetosphere",
               "IonCloud", "GravityWell", "EventHorizon", "SpaceTime",
               "WormHole", "SolarFlare", "NovaRemnant", "GammaRay",
               "Ecliptic", "BlueShift", "RedShift"),
    
    animals = c("Cat", "Dog", "Butterfly", "Bird", "Horse", "Elephant", 
                "Dolphin", "Rabbit", "Fox", "Owl", "Lion", "Tiger", "Bear", 
                "Wolf", "Giraffe", "Penguin", "Koala", "Kangaroo", "Panda", 
                "Zebra", "Cheetah", "Gorilla", "Sloth", "Octopus", 
                "Chimpanzee", "Rhinoceros", "Crocodile", "Flamingo",
                "Jaguar", "Leopard", "Gazelle", "Antelope", "Hedgehog",
                "Platypus", "Raccoon", "Squirrel", "Peacock", "Seahorse",
                "Jellyfish", "Narwhal", "Pangolin", "Meerkat", "Armadillo",
                "Chameleon", "Lemur", "Mongoose", "Wombat", "Lynx"),
    
    shapes = c("Square", "Circle", "Triangle", "Rectangle", "Pentagon", 
               "Hexagon", "Star", "Oval", "Diamond", "Heart", "Crescent", 
               "Trapezoid", "Parallelogram", "Rhombus", "Octagon", "Cube", 
               "Sphere", "Cylinder", "Cone", "Pyramid", "Torus", "Prism",
               "Dodecahedron", "Icosahedron", "Helix", "Spiral", "Ellipse",
               "Heptagon", "Decagon", "Tetrahedron", "Mobius", "Klein",
               "Tesseract", "Frustum", "Polyhedron", "Geodesic", "Toroid",
               "Hypercube", "Stellated", "Vortex")
  )
}
# Generate token options
#
# Default Parameters:
# - num_options = 1: Defaults to returning a single token as this is the most common use case
#   where tokens are needed one at a time (e.g., generating a single unique identifier)
# - min_options = 20: Sets a minimum pool of 20 candidates before sampling to ensure sufficient
#   randomization while balancing performance. This provides enough variety to avoid 
#   predictable patterns while keeping generation time reasonable
#
generate_token_options <- function(colors = TRUE, 
                                   cosmos = TRUE, 
                                   animals = TRUE, 
                                   shapes = TRUE, 
                                   num_options = 1, 
                                   min_options = 20, ...) {
  
  default_vectors <- get_default_vectors()
  
  # Process vector arguments
  processed_vectors <- list(
    colors = process_vector_arg(colors, default_vectors$colors),
    cosmos = process_vector_arg(cosmos, default_vectors$cosmos),
    animals = process_vector_arg(animals, default_vectors$animals),
    shapes = process_vector_arg(shapes, default_vectors$shapes)
  )
  
  # Combine with extra vectors
  available_elements <- c(processed_vectors, list(...))
  available_elements <- available_elements[vapply(available_elements, length, integer(1)) > 0]
  
  if (length(available_elements) == 0) {
    stop("No valid element vectors provided.")
  }
  
  generate_tokens(available_elements, min_options, num_options)
}

# Generate tokens based on available elements
generate_tokens <- function(available_elements, min_options, num_options) {
  options <- c()
  
  while (length(options) < min_options) {
    elements <- lapply(available_elements, function(x) sample(x, 1))
    elements$number <- generate_spelled_number()
    
    new_option <- paste0(sample(unlist(elements)), collapse = "")
    options <- unique(c(options, new_option))
  }
  
  num_options <- min(num_options, length(options))
  sample(options, num_options)
}

# Generate unique token
generate_unique_token <- function(existing_tokens) {
  repeat {
    new_token <- generate_token_options(animals = FALSE, shapes = FALSE, num_options = 1)
    if (!(new_token %in% existing_tokens)) {
      return(new_token)
    }
  }
}
