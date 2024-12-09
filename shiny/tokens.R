# Generate Tokens with Flexible Vector Sourcing
#
# This function offers a flexible approach to generating tokens by:
# - Using default vectors for categories when specific vectors are not provided
# - Allowing selective exclusion of vectors by setting them to FALSE
# - Enabling the use of custom vectors if provided, otherwise default vectors are used
# - Supporting dynamic vector injection through additional arguments passed via ellipsis (...)
# - Facilitating custom token generation with controlled randomization and uniqueness
#
generate_token_options <- function(colors = TRUE, 
                                   cosmos = TRUE, 
                                   animals = TRUE, 
                                   shapes = TRUE, 
                                   num_options = 1, 
                                   min_options = 20, ...) {
  
  # Define default lists of elements for each category
  default_colors <- c("Red", "Blue", "Green", "Yellow", "Purple", "Orange", "Pink", 
                      "Brown", "Gray", "Black", "White", "Teal", "Maroon", "Navy", 
                      "Olive", "Lime", "Cyan", "Magenta", "Turquoise", "Lavender", 
                      "Crimson", "Indigo")
  default_cosmos <- c("Sun", "Moon", "Star", "Sky", "Cloud", "Comet", "Galaxy", 
                      "Orbit", "Planet", "Nebula", "Asteroid", "BlackHole", 
                      "Supernova", "Quasar", "Pulsar", "Meteor", "Constellation", 
                      "Cosmos", "Universe", "Stardust")
  default_animals <- c("Cat", "Dog", "Butterfly", "Bird", "Horse", "Elephant", 
                       "Dolphin", "Rabbit", "Fox", "Owl", "Lion", "Tiger", "Bear", 
                       "Wolf", "Giraffe", "Penguin", "Koala", "Kangaroo", "Panda", 
                       "Zebra", "Cheetah", "Gorilla", "Sloth", "Octopus", 
                       "Chimpanzee", "Rhinoceros", "Crocodile", "Flamingo")
  default_shapes <- c("Square", "Circle", "Triangle", "Rectangle", "Pentagon", 
                      "Hexagon", "Star", "Oval", "Diamond", "Heart", "Crescent", 
                      "Trapezoid", "Parallelogram", "Rhombus", "Octagon", "Cube", 
                      "Sphere", "Cylinder", "Cone", "Pyramid")
  
  # Helper function to generate a spelled-out number from 0 to 999
  generate_spelled_number <- function() {
    numbers_below_20 <- c("Zero", "One", "Two", "Three", "Four", "Five", "Six", 
                          "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve", 
                          "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", 
                          "Eighteen", "Nineteen")
    tens <- c("Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", 
              "Ninety")
    hundreds <- "Hundred"
    
    # Randomly select a number between 0 and 999
    num <- sample(0:999, 1)
    
    if (num < 20) {
      return(numbers_below_20[num + 1])
    } else if (num < 100) {
      tens_part <- tens[(num %/% 10) - 1]
      units_part <- ifelse(num %% 10 == 0, "", paste0(numbers_below_20[(num %% 10) + 1]))
      return(paste0(tens_part, units_part))
    } else {
      hundreds_part <- paste0(numbers_below_20[(num %/% 100) + 1], hundreds)
      remainder <- num %% 100
      if (remainder == 0) {
        return(hundreds_part)
      } else if (remainder < 20) {
        return(paste0(hundreds_part, numbers_below_20[remainder + 1]))
      } else {
        tens_part <- tens[(remainder %/% 10) - 1]
        units_part <- ifelse(remainder %% 10 == 0, "", paste0(numbers_below_20[(remainder %% 10) + 1]))
        return(paste0(hundreds_part, tens_part, units_part))
      }
    }
  }
  
  # Determine which vectors to use
  colors <- if (is.logical(colors)) {
    if (colors) default_colors else NULL
  } else {
    colors
  }
  
  cosmos <- if (is.logical(cosmos)) {
    if (cosmos) default_cosmos else NULL
  } else {
    cosmos
  }
  
  animals <- if (is.logical(animals)) {
    if (animals) default_animals else NULL
  } else {
    animals
  }
  
  shapes <- if (is.logical(shapes)) {
    if (shapes) default_shapes else NULL
  } else {
    shapes
  }
  
  # Collect any additional vectors passed via ...
  extra_vectors <- list(...)
  
  # Combine all available element vectors
  available_elements <- list(colors = colors, cosmos = cosmos, animals = animals, shapes = shapes)
  available_elements <- c(available_elements, extra_vectors)
  
  # Filter out empty vectors
  available_elements <- available_elements[vapply(available_elements, length, integer(1)) > 0]
  
  # Ensure at least one valid element vector is provided
  if (length(available_elements) == 0) {
    stop("No valid element vectors provided.")
  }
  
  options <- c()
  
  # Generate unique token options until the minimum number is reached
  while (length(options) < min_options) {
    elements <- lapply(available_elements, function(x) sample(x, 1))
    
    # Generate and add a spelled-out number to the elements
    elements$number <- generate_spelled_number()
    
    # Randomize the order of elements and create a new token option
    randomized_elements <- sample(unlist(elements))
    new_option <- paste0(randomized_elements, collapse = "")
    
    # Ensure uniqueness of the new option
    options <- unique(c(options, new_option))
  }
  
  # Limit the number of options to the requested amount
  if (num_options > length(options)) {
    num_options <- length(options)
  }
  
  # Return a random selection of the generated options
  return(sample(options, num_options))
}

# Repeat the token generation against existing tokens until a unique token is found
generate_unique_token <- function(existing_tokens) {
  repeat {
    # Exclude animals and shapes for a shorter token
    new_token <- generate_token_options(animals = FALSE, shapes = FALSE, num_options = 1)
    
    if (!(new_token %in% existing_tokens)) {
      return(new_token)
    }
  }
}
