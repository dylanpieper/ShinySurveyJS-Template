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
```

3.  Install the required R packages:

``` r
if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
pak::pkg_install(c("shiny", "jsonlite", "shinyjs", "httr", "DBI", "RPostgres", "yaml", "future"))
```

## Setup Dynamic Fields

1.  Create the table `entities` in your database to explore the example surveys and dynamic fields functionality. You can execute the following queries to create the table and insert the sample data.

``` sql
CREATE TABLE organization_location (
    organization TEXT,
    location TEXT
);

INSERT INTO organization_location (organization, location) 
VALUES 
    ('Google', 'San Francisco, CA'),
    ('Google', 'Boulder, CO'),
    ('Google', 'Chicago, IL'),
    ('Anthropic', 'San Francisco, CA'),
    ('Anthropic', 'Seattle, WA'),
    ('Anthropic', 'New York City, NY');
    
CREATE TABLE doctor_clinic (
   doctor TEXT,
   clinic TEXT
);
   
INSERT INTO doctor_clinic (doctor, clinic) VALUES
   ('SarahChen', 'Downtown Medical'),
   ('SarahChen', 'Westside Health'),
   ('JamesWilson', 'Downtown Medical'),
   ('JamesWilson', 'Eastside Clinic'),
   ('MariaGarcia', 'Westside Health'),
   ('MariaGarcia', 'Eastside Clinic');
```

2.  Optionally, create and manage your own dynamic fields table by adding your table and mapping your fields to the `dynamic_fields.yml` file. The `group_col` is the column that will be used to filter the dynamic fields, which is assigned a token and used in the URL query parameter. The `choices_col` is the column that will be used to locate the field name and populate the survey choices. The `surveys` field is a list of survey names that the dynamic field applies to.

Because the app uses URL queries, don't use spaces and special characters for the `group_col`.

## Run Survey App

1.  Run the app:

``` r
runApp()
```

If the `tokens` table does not exist yet, the app will automatically create it. The app will also generate tokens for each survey and store them in the database.

Tokenization is used by default. Using tokens requires an additional table read, making it a slightly slower process, which may not be necessary for your use case. Tokens are generated as a background task of the app using parallelization. If new tokens are created, users can access them on the next page load after the process runs. You can customize the tokenization algorithm in `shiny/token.R`.

2.  Access survey with URL query parameters:
    -   Generic:
        -   Without tokens (same as JSON file name): `/?survey=name`
        -   With tokens: `/?survey=token`
    -   Examples with dynamic fields:
        -   Without tokens (`token_active <- FALSE`): `/?survey=DynamicPersonID&entity=MariaGarcia`
        -   With tokens (`token_active <- TRUE`): `/?survey=LimeMeteorSevenHundredThirtyTwo&entity=FiveHundredSeventyFourGalaxyBrown`

## Use Any Database

Easily change the database driver in `db.R` to use any database system compatible with the `DBI` package (see [list of backends](https://github.com/r-dbi/backends#readme)). The `RPostgres` package is used by default.

## Follow The Roadmap

-   ✔️ Friendly initialization UI
-   ✔️ URL parameter tokenization
-   PostgreSQL
    -   ✔️ Tokens and dynamic fields handled in database
    -   Survey data is written to database
-   System to generate links for sharing surveys (admin login on base URL)
-   App is managed in a container

## Disclaimer

This application is provided as-is and does not include comprehensive security measures or authentication protocols. Users should be aware that there is no built-in authentication system, user management, or protection against unauthorized access. The application lacks encryption for data transmission and provides no safeguards against common web vulnerabilities or SQL injection. Due to these limitations, this application is not recommended for production use without significant security enhancements. Users who choose to deploy this application assume all risks and responsibilities for implementing necessary security measures, including authentication, authorization, and data encryption. The developers and maintainers are not responsible for any security breaches, data loss, or damages resulting from its use. No warranty or guarantee is provided regarding the application's security or fitness for any particular purpose. By using this application, users acknowledge these limitations and accept all associated risks.
