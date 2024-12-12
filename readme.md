# ShinySurveyJS

A template for hosting multiple surveys using **Shiny**, **SurveyJS**, and **PostgreSQL** (or any database).

![](ShinySurveyJS.png)

## Why SurveyJS?

SurveyJS is a powerful open-source JavaScript library for designing forms and questionnaires with a ecosystem that includes a [visual editor](https://surveyjs.io/create-free-survey). It offers complete backend flexibility, as its libraries work seamlessly with any combination of server and database technologies. The front-end natively supports branching and conditional logic, input validation, diverse question types, theme and css options, adding panels and pages, and supporting multiple languages.

There are a couple amazing Shiny-based survey tools like [surveydown](https://github.com/surveydown-dev/surveydown) or [shinysurveys](https://github.com/jdtrat/shinysurveys). However, these tools rely on Shiny for building the user interface (UI) and are limited to hosting a single survey per server. Because SurveyJS manages most of the UI components, it simplifies the development of a Shiny codebase that supports abstraction, such as hosting multiple surveys on the same server.

## Key Features

-   Visual survey creation using SurveyJS's [visual editor](https://surveyjs.io/create-free-survey)
-   Multiple surveys in a single app
-   PostgreSQL cloud platforms like [Supabase](https://supabase.com/d) offer free and paid database solutions
-   URL query tokens prevent user manipulation of public surveys
    -   Automatically generates and stores unique tokens in the database
    -   Supports multiple parameters and configurations
    -   Enhances security by obscuring direct parameter access
-   Query parameters in URLs and database tables enable user or participant tracking and dynamically updating survey response options during data collection

## Get Started

1.  Clone the repository:

``` bash
git clone https://github.com/dylanpieper/ShinySurveyJS.git
```

2.  Create a `.env` file, modifying the following template with your database credentials. In Supabase, navigate to the project sidebar navigation pane ➡️ project settings ➡️ configuration: database ➡️ database settings: connection parameters.

``` env
DB_HOST=aws-0-us-west-1.pooler.supabase.com
DB_PORT=6543
DB_NAME=postgres
DB_USER=username
DB_PASSWORD=password
token_active=TRUE
token_table_name=tokens
survey_table_name=surveys
```

3.  Install the required R packages:

``` r
if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
pak::pkg_install(c("R6", "dotenv", "shiny", "jsonlite", "shinyjs",
                   "httr", "DBI", "RPostgres", "pool", future", "promises"))
```

## Setup Dynamic Fields

1.  You can run the queries in `setup_example.sql` to create the setup tables and insert the example data.

<!-- -->

2.  Optionally, create and manage your own dynamic fields table by creating a table and mapping your fields to the `config_json` field as a JSON object. The `table_name` is the table name. The `group_col` is the column that will be used to filter the dynamic fields. Using `select_group`, the group can be set to populate the choices in a JSON field or defined in the URL for individual tracking. The `choices_col` is the column used to locate the field name and populate the survey choices. The `surveys` field is a list of survey names that the dynamic field applies to.

Because the app uses URL queries, don't use spaces and special characters for the `group_col` value.

## Run Survey App

1.  Run the app:

``` r
runApp()
```

If the `tokens` table does not exist yet, the app will automatically create it. The app will also generate tokens for each survey and store them in the database.

Tokenization is used by default. Using tokens requires an additional table read, making it a slower process. Tokens are generated as a background task of the app using parallelization. If new tokens are created, users can access them on the next page load after the process runs. You can customize the tokenization algorithm in `shiny/token.R`.

2.  Access survey with URL query parameters:
    -   Generic:
        -   Without tokens (same as JSON file name): `/?survey=name`
        -   With tokens: `/?survey=token`
    -   Examples with dynamic fields:
        -   Without tokens (`token_active <- FALSE`): `/?survey=dynamic_person_id&doctor=James_Wilson`
        -   With tokens (`token_active <- TRUE`): `/?survey=SilverGalaxyEightHundredEightyOne&doctor=EightHundredTwelveGalaxyPlum`

## Use Any Database

Easily change the database driver in `database.R` to use any database system compatible with the `DBI` package (see [list of backends](https://github.com/r-dbi/backends#readme)). The `RPostgres` package is used by default.

## Follow The Roadmap

-   ✔️ Friendly initialization UI
-   ✔️ URL parameter tokenization
-   PostgreSQL
    -   ✔️ Tokens and dynamic fields handled in database
    -   Survey data is written to database
-   System to generate links for sharing surveys (admin login on base URL)
-   App is managed in a container

## Disclaimer

This application template was not built with comprehensive security features. It lacks authentication, user management, private data encryption, and protection against common vulnerabilities. It is not suitable for production use without realistic security upgrades. Users must implement their own security measures and accept all associated risks. No warranty is provided.
