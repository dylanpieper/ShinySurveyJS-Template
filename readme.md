# ShinySurveyJS

A template for hosting multiple surveys using **Shiny**, **SurveyJS**, and **PostgreSQL** (or any database).

![](ShinySurveyJS.png)

## Why SurveyJS?

[SurveyJS](https://surveyjs.io/) is a powerful open-source JavaScript library for designing forms and questionnaires with a ecosystem that includes a [visual editor](https://surveyjs.io/create-free-survey). It offers complete backend flexibility, as its libraries work seamlessly with any combination of server and database technologies. The front-end natively supports branching and conditional logic, input validation, diverse question types, theme and css options, adding panels and pages, and supporting multiple languages.

There are a couple amazing Shiny-based survey tools like [surveydown](https://github.com/surveydown-dev/surveydown) or [shinysurveys](https://github.com/jdtrat/shinysurveys). However, these tools rely on Shiny for building the user interface (UI) and are limited to hosting a single survey per server. Because SurveyJS manages most of the UI components, it simplifies the development of a Shiny codebase that supports abstraction, such as hosting multiple surveys on the same server with unique dynamic field configurations.

The current implementation of ShinySurveyJS uses the [SurveyJS jQuery Form Library](https://www.npmjs.com/package/survey-jquery).

## Key Features

-   Multiple surveys in a single app
-   URL query parameters use database tables to enable participant tracking and/or dynamically updating survey item choices (i.e., response options)
-   URL query tokens prevent user manipulation of public surveys
    -   Automatically generates and stores unique tokens in the database
    -   Supports multiple parameters and configurations
    -   Enhances security by obscuring direct parameter access
-   Visual survey creation using SurveyJS's [visual editor](https://surveyjs.io/create-free-survey)
-   PostgreSQL cloud platforms like [Supabase](https://supabase.com/) offer free and paid database solutions

## Get Started

1.  Clone the repository:

``` bash
git clone https://github.com/dylanpieper/ShinySurveyJS.git
```

2.  Create a `.env` file, modifying the following template with your database credentials. In Supabase, you can find project connect details by clicking "Connect" in the top bar.

``` env
DB_HOST=aws-0-us-east-2.pooler.supabase.com
DB_PORT=5432
DB_NAME=postgres
DB_USER=username
DB_PASSWORD=password
token_active=TRUE
show_response=TRUE
token_table_name=tokens
survey_table_name=surveys
```

3.  Install the required R packages:

``` r
if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
pak::pkg_install(c("R6", "dotenv", "shiny", "jsonlite", "shinyjs",
                   "DBI", "RPostgres", "pool", "future", "promises", "DT"))
```

## Setup Dynamic Fields

1.  Run the queries in `setup_example.sql` to create the setup the `surveys`, `config_pid`, `config_vacation`, and `config_doctor_clinic` tables and insert the example data. In Supabase, you can run these queries by clicking "SQL Editor" in the sidebar.

2.  Optionally, create and manage your own dynamic fields table by mapping your fields to the `config_json` field in your `surveys` table as a JSON object:

    -   `table_name`: The table name for the dynamic field
    -   `group_col`: The column name that will be used to filter the dynamic fields
    -   `select_group`: A logical for using the group column to populate the rows as survey item choices in a JSON input field (true) or defining the group in the URL query for tracking (false)
        -   `group_id_table_name`: If true, the table name to locate the group ID column used in the query for participant tracking
        -   `group_id_col`: If true, the group ID column used in the query for participant tracking
    -   `choices_col`: The column name used to populate the survey item choices
    -   `surveys`: A list of survey names that the dynamic field applies to

Don't include spaces and special characters for the `group_col` value if you are using it in the query by using `"select_group": false`.

## Try Example Surveys

These examples show how to use dynamic fields to track participants and/or update survey item choices using URL query parameters and database tables. The dynamic field server logic can be customized in `shiny/survey.R`. Remember that conditional logic can be handled by SurveyJS.

1.  **survey_llm**: Assign participant ID in URL query with no selections for group or additional choices

    ```         
    /?survey=survey_llm&pid=Sam_Altman
    ```

    In this case, you are not allowed to enter an invalid `pid` to avoid user manipulation

2.  **survey_vacation**: Select group (country) from a database table with no additional choices or participant tracking

    ```         
    /?survey=survey_vacation
    ```

3.  **survey_vacation_query_group**: Assign group (country) in URL query and select filtered choices (city) from a database table

    ```         
    /?survey=survey_vacation_query_group&country=USA
    ```

4.  **survey_vacation_select_group**: Select group (country) and additional choices (city) from a database table

    ```         
    /?survey=survey_vacation_select_group
    ```

5.  **survey_vacation_group_id**: Select group (country) and additional choices (city) from a database table with participant tracking

    ```         
    /?survey=survey_vacation_select_group&pid=Sam_Altman
    ```

6.  **survey_person_id**: Assign person ID to doctors in URL query with a selection for the clinic they worked in that day

    ```         
    /?survey=survey_person_id&doctor=Sarah_Chen
    ```

7.  **survey_product_feedback**: Static survey with no dynamic fields

    ```         
    /?survey=survey_product_feedback
    ```

## Run Survey App

1.  Run the app:

``` r
runApp()
```

If the `tokens` table does not exist yet, the app will automatically create it. The app will also generate tokens for each survey and store them in the database.

Tokenization is used by default. Using tokens requires an additional table read, making it a slower process. Tokens are generated as a background task of the app using parallelization. If new tokens are created, users can access them on the next page load after the process runs. You can customize the tokenization algorithm in `shiny/tokens.R`.

2.  Access survey with URL query parameters:
    -   Generic:
        -   Without tokens (same as JSON file name): `/?survey=name`
        -   With tokens: `/?survey=token`
    -   Examples with dynamic fields:
        -   Without tokens (`token_active <- FALSE`): `/?survey=survey_person_id&doctor=James_Wilson`
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

This application template was not built with comprehensive security features. It lacks robust authentication methods, user management, private data encryption, and protection against common vulnerabilities like SQL injection. It is not suitable for production use. Users must implement their own security measures and accept all associated risks. No warranty is provided.
