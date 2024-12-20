-- Create the survey config table
CREATE TABLE surveys (
    id SERIAL PRIMARY KEY,
    survey_name TEXT NOT NULL,
    survey_active BOOLEAN DEFAULT TRUE,
    json text NOT NULL,
    json_config JSON,
    json_stage TEXT,
    date_start DATE,
    date_end DATE,
    date_created TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    date_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(survey_name)
);

-- Insert the configs
INSERT INTO surveys (survey_name, json_config, json)
VALUES 
    ('survey_llm', 
     '{
         "table_name": "config_pid",
         "group_col": "pid",
         "select_group": false
     }'::json,
     '{
         "title": "LLM Survey",
         "description": "Assign participant ID in URL query with no selections for group or additional choices",
         "elements": [
             {
                 "type": "html",
                 "visibleIf": "{pid} notempty",
                 "html": "Hi, welcome to the survey {pid}"
             },
             {
                 "type": "radiogroup",
                 "name": "llm_provider", 
                 "title": "Who is your favorite Large Language Model (LLM) provider?",
                 "choices": ["OpenAI", "Anthropic", "Google"],
                 "hasOther": true,
                 "isRequired": true
             },
             {
                 "type": "text",
                 "name": "pid",
                 "visible": false
             }
         ]
     }'),
    
    ('survey_vacation', 
     '{
         "table_name": "config_vacation",
         "group_col": "country",
         "select_group": true
     }'::json,
     '{
         "title": "Vacation Survey",
         "description": "Select group (country) from a database table with no additional choices or participant tracking",
         "elements": [
             {
                 "type": "dropdown",
                 "name": "country",
                 "title": "If you could plan your dream vacation, which country would you visit?",
                 "choices": [],
                 "isRequired": true
             }
         ]
     }'),
    
    ('survey_vacation_query_group',
     '{
         "table_name": "config_vacation",
         "group_col": "country",
         "select_group": false,
         "choices_col": "city"
     }'::json,
     '{
         "title": "Vacation Survey",
         "description": "Assign group (country) in URL query and select filtered choices (city) from a database table",
         "elements": [
             {
                 "type": "ranking",
                 "name": "city",
                 "title": "Rank the cities you would like to visit on your next vacation:",
                 "choices": [],
                 "isRequired": true
             }
         ]
     }'),
    
    ('survey_vacation_select_group',
     '{
         "table_name": "config_vacation",
         "group_col": "country",
         "select_group": true,
         "choices_col": "city"
     }'::json,
     '{
         "title": "Vacation Survey",
         "description": "Select group (country) and additional choices (city) from a database table",
         "elements": [
             {
                 "type": "dropdown",
                 "name": "country",
                 "title": "If you could plan your dream vacation, which country would you visit?",
                 "choices": [],
                 "isRequired": true
             },
             {
                 "type": "ranking",
                 "name": "city",
                 "title": "Rank the cities you would like to visit:",
                 "choices": [],
                 "isRequired": true,
                 "visibleIf": "{country} notempty"
             }
         ]
     }'),
    
    ('survey_vacation_group_id',
     '{
         "table_name": "config_vacation",
         "group_col": "country",
         "select_group": true,
         "group_id_table_name": "config_pid",
         "group_id_col": "pid",
         "choices_col": "city"
     }'::json,
     '{
         "title": "Vacation Survey",
         "description": "Select group (country) and additional choices (city) from a database table with participant tracking",
         "elements": [
             {
                 "type": "html",
                 "visibleIf": "{pid} notempty",
                 "html": "Hi, welcome to the survey {pid}"
             },
             {
                 "type": "dropdown",
                 "name": "country",
                 "title": "If you could plan your dream vacation, which country would you visit?",
                 "choices": [],
                 "isRequired": true
             },
             {
                 "type": "ranking",
                 "name": "city",
                 "title": "Rank the cities you would like to visit:",
                 "choices": [],
                 "isRequired": true,
                 "visibleIf": "{country} notempty"
             },
             {
                 "type": "text",
                 "name": "pid",
                 "visible": false
             }
         ]
     }'),
    
    ('survey_doctor_clinic',
     '{
         "table_name": "config_doctor_clinic",
         "group_col": "doctor",
         "select_group": false,
         "choices_col": "clinic"
     }'::json,
     '{
         "title": "Clinical Survey",
         "description": "Assign group ID to doctors in URL query with a selection for the clinic they worked in",
         "elements": [
            {
                 "type": "html",
                 "visibleIf": "{doctor} notempty",
                 "html": "Hi, welcome to the survey {doctor}"
             },
             {
                 "type": "radiogroup",
                 "name": "clinic",
                 "title": "Where did you see the client today?",
                 "choices": [],
                 "isRequired": true
             },
             {
                 "type": "dropdown",
                 "name": "session_type",
                 "title": "Type of Session",
                 "isRequired": true,
                 "choices": [
                     "Individual Therapy",
                     "Group Therapy",
                     "Crisis Intervention",
                     "Follow-up"
                 ]
             },
             {
                 "type": "matrix",
                 "name": "symptoms",
                 "title": "Rate current symptoms",
                 "isRequired": true,
                 "columns": [
                     "None",
                     "Mild",
                     "Moderate", 
                     "Severe"
                 ],
                 "rows": [
                     "Anxiety",
                     "Depression",
                     "Sleep Issues"
                 ]
             },
             {
                 "type": "checkbox",
                 "name": "interventions",
                 "title": "Interventions Used",
                 "isRequired": true,
                 "choices": [
                     "Narrative Therapy",
                     "Mindfulness",
                     "Crisis Management",
                     "Skills Training"
                 ]
             },
             {
                 "type": "text",
                 "name": "notes",
                 "title": "Session Notes",
                 "isRequired": true
             },
             {
                 "type": "dropdown",
                 "name": "next_session",
                 "title": "Next Session",
                 "isRequired": true,
                 "choices": [
                     "1 week",
                     "2 weeks",
                     "As needed"
                 ]
             },
             {
                 "type": "text",
                 "name": "doctor",
                 "visible": false
             }
         ],
         "showQuestionNumbers": "off",
         "widthMode": "responsive"
     }'),
    
    ('survey_product_feedback', 
     NULL,
     '{
         "title": "Product Feedback Survey",
         "description": "Static survey with no dynamic fields",
         "completedHtml": "<h3>Thank you for your valuable feedback!</h3>",
         "pages": [
             {
                 "name": "satisfaction",
                 "elements": [
                     {
                         "type": "rating",
                         "name": "product_satisfaction",
                         "title": "Overall Satisfaction",
                         "description": "How satisfied are you with your experience using our product?",
                         "rateMin": 1,
                         "rateMax": 5,
                         "rateStep": 1,
                         "minRateDescription": "Very Dissatisfied",
                         "maxRateDescription": "Very Satisfied",
                         "isRequired": true
                     },
                     {
                         "type": "rating",
                         "name": "product_quality",
                         "title": "Product Quality",
                         "description": "How would you rate the overall quality of our product?",
                         "rateMin": 1,
                         "rateMax": 5,
                         "rateStep": 1,
                         "minRateDescription": "Poor Quality",
                         "maxRateDescription": "Excellent Quality",
                         "isRequired": true
                     },
                     {
                         "type": "radiogroup",
                         "name": "recommend_product",
                         "title": "Likelihood to Recommend",
                         "description": "How likely are you to recommend our product to others?",
                         "choices": [
                             {
                                 "value": "definitely",
                                 "text": "Definitely would recommend"
                             },
                             {
                                 "value": "probably",
                                 "text": "Probably would recommend"
                             },
                             {
                                 "value": "maybe",
                                 "text": "Might or might not recommend"
                             },
                             {
                                 "value": "probably_not",
                                 "text": "Probably would not recommend"
                             },
                             {
                                 "value": "definitely_not",
                                 "text": "Definitely would not recommend"
                             }
                         ],
                         "isRequired": true
                     }
                 ]
             },
             {
                 "name": "feedback",
                 "elements": [
                     {
                         "type": "comment",
                         "name": "strengths",
                         "title": "Product Strengths",
                         "description": "What aspects of the product do you like the most?",
                         "placeholder": "Please share what you enjoy about our product...",
                         "rows": 3
                     },
                     {
                         "type": "comment",
                         "name": "improvements",
                         "title": "Suggested Improvements",
                         "description": "What aspects of the product could be improved?",
                         "placeholder": "Please share your suggestions for improvement...",
                         "rows": 3
                     }
                 ]
             }
         ],
         "showQuestionNumbers": "off",
         "showProgressBar": "top",
         "progressBarType": "questions"
     }'),

    ('survey_protected_feedback',
     NULL,
     '{
         "title": "Protected Feedback Survey",
         "description": "Static survey with simple password protection built into the survey JSON",
         "firstPageIsStarted": true,
         "startSurveyText": "Start Survey",
         "pages": [
             {
                 "name": "passwordPage",
                 "elements": [
                     {
                         "type": "text",
                         "name": "password",
                         "title": {
                             "default": "Thank you for entering the survey password",
                             "visibleIf": "{password} = ''secret123''"
                         },
                         "isRequired": true
                     }
                 ],
                 "navigationButtonsVisibility": "show"
             },
             {
                 "name": "feedback",
                 "elements": [
                     {
                         "type": "rating",
                         "name": "meeting_rating",
                         "title": "How would you rate the effectiveness of todays meeting?",
                         "isRequired": true,
                         "rateMax": 5
                     },
                     {
                         "type": "checkbox",
                         "name": "meeting_aspects",
                         "title": "What aspects of the meeting were most valuable?",
                         "isRequired": true,
                         "choices": [
                             "Presentation Content",
                             "Group Discussion",
                             "Q&A Session",
                             "Networking Opportunities",
                             "Project Updates"
                         ]
                     },
                     {
                         "type": "comment",
                         "name": "suggestions",
                         "title": "What suggestions do you have for future meetings?",
                         "rows": 3
                     },
                     {
                         "type": "boolean",
                         "name": "follow_up",
                         "title": "Would you like someone to follow up with you about any of your feedback?",
                         "isRequired": true
                     },
                     {
                         "type": "text",
                         "name": "contact_info",
                         "title": "If you would like a follow-up, please provide your contact information:",
                         "visibleIf": "{follow_up} = true"
                     }
                 ],
                 "visibleIf": "{password} = ''secret123''"
             }
         ],
         "showQuestionNumbers": "off"
     }');

INSERT INTO surveys (survey_name, json_stage, json)
VALUES (
  'survey_demographics',
  '{
        "title": "Demographics Survey",
        "description": "Static survey with field choices from a staged JSON table",
        "pages": [
            {
                "name": "demographics",
                "elements": [
                    {
                        "type": config_demographics["age_group", "field_type"],
                        "name": "age_group",
                        "title": "What is your age group?",
                        "isRequired": true,
                        "choices": config_demographics["age_group", "choices"]
                    },
                    {
                        "type": "radiogroup",
                        "name": "gender",
                        "title": "What is your gender?",
                        "isRequired": true,
                        "choices": config_demographics["gender", "choices"]
                    },
                    {
                        "type": "dropdown",
                        "name": "education",
                        "title": "What is your highest level of education?",
                        "isRequired": true,
                        "choices": config_demographics["education", "choices"]
                    },
                    {
                        "type": "checkbox",
                        "name": "employment",
                        "title": "What is your current employment status? (Select all that apply)",
                        "isRequired": true,
                        "choices": config_demographics["employment", "choices"]
                    },
                    {
                        "type": "text",
                        "name": "zip_code",
                        "title": "What is your ZIP code?",
                        "isRequired": true,
                        "validators": [
                            {
                                "type": "regex",
                                "regex": "^\\d{5}(?:-\\d{4})?$",
                                "text": "Please enter a valid ZIP code (12345 or 12345-6789)"
                            }
                        ],
                        "maxLength": 10
                    }
                ]
            }
        ],
        "showQuestionNumbers": "off"
    }',
  '{
        "title": "Staged JSON Survey",
        "description": "Basic demographic information survey",
        "pages": [
            {
                "name": "demographics",
                "elements": [
                    {
                        "type": "dropdown",
                        "name": "age_group",
                        "title": "What is your age group?",
                        "isRequired": true,
                        "choices": [
                            "18-24",
                            "25-34",
                            "35-44",
                            "45-54",
                            "55-64",
                            "65 or older"
                        ]
                    },
                    {
                        "type": "radiogroup",
                        "name": "gender",
                        "title": "What is your gender?",
                        "isRequired": true,
                        "choices": [
                            "Man",
                            "Woman",
                            "Non-binary",
                            "Prefer not to say"
                        ]
                    },
                    {
                        "type": "dropdown",
                        "name": "education",
                        "title": "What is your highest level of education?",
                        "isRequired": true,
                        "choices": [
                            "High School or equivalent",
                            "Some College",
                            "Bachelor''s Degree",
                            "Master''s Degree",
                            "Doctorate",
                            "Other"
                        ]
                    },
                    {
                        "type": "checkbox",
                        "name": "employment",
                        "title": "What is your current employment status? (Select all that apply)",
                        "isRequired": true,
                        "choices": [
                            "Full-time employed",
                            "Part-time employed",
                            "Self-employed",
                            "Student",
                            "Retired",
                            "Unemployed"
                        ]
                    },
                    {
                        "type": "text",
                        "name": "zip_code",
                        "title": "What is your ZIP code?",
                        "isRequired": true,
                        "validators": [
                            {
                                "type": "regex",
                                "regex": "^\\d{5}(?:-\\d{4})?$",
                                "text": "Please enter a valid ZIP code (12345 or 12345-6789)"
                            }
                        ],
                        "maxLength": 10
                    }
                ]
            }
        ],
        "showQuestionNumbers": "off"
    }'
);

-- Create the tables for the dynamic survey examples
CREATE TABLE config_pid (
    id SERIAL PRIMARY KEY,
    pid TEXT,
    date_created TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    date_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO config_pid (pid) 
VALUES 
    ('Sam_Altman'),
    ('Dario_Amodei'),
    ('Sundar_Pichai');
    
CREATE TABLE config_vacation (
    id SERIAL PRIMARY KEY,
    country TEXT,
    city TEXT,
    date_created TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    date_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO config_vacation (country, city) VALUES
    ('Argentina', 'Bariloche'),
    ('Argentina', 'Buenos Aires'),
    ('Argentina', 'Córdoba'),
    ('Argentina', 'Mendoza'),
    ('Australia', 'Brisbane'),
    ('Australia', 'Melbourne'),
    ('Australia', 'Sydney'),
    ('Austria', 'Graz'),
    ('Austria', 'Hallstatt'),
    ('Austria', 'Innsbruck'),
    ('Austria', 'Salzburg'),
    ('Austria', 'Vienna'),
    ('Belgium', 'Antwerp'),
    ('Belgium', 'Bruges'),
    ('Belgium', 'Brussels'),
    ('Belgium', 'Ghent'),
    ('Brazil', 'Florianópolis'),
    ('Brazil', 'Manaus'),
    ('Brazil', 'Rio de Janeiro'),
    ('Brazil', 'Salvador'),
    ('Brazil', 'São Paulo'),
    ('Canada', 'Montreal'),
    ('Canada', 'Toronto'),
    ('Canada', 'Vancouver'),
    ('China', 'Beijing'),
    ('China', 'Hong Kong'),
    ('China', 'Shanghai'),
    ('Colombia', 'Bogotá'),
    ('Colombia', 'Cali'),
    ('Colombia', 'Cartagena'),
    ('Colombia', 'Medellín'),
    ('Croatia', 'Dubrovnik'),
    ('Croatia', 'Hvar'),
    ('Croatia', 'Split'),
    ('Croatia', 'Zagreb'),
    ('Czech_Republic', 'Cesky Krumlov'),
    ('Czech_Republic', 'Karlovy Vary'),
    ('Czech_Republic', 'Prague'),
    ('Denmark', 'Aarhus'),
    ('Denmark', 'Copenhagen'),
    ('Denmark', 'Odense'),
    ('Ecuador', 'Cuenca'),
    ('Ecuador', 'Guayaquil'),
    ('Ecuador', 'Quito'),
    ('France', 'Bordeaux'),
    ('France', 'Lyon'),
    ('France', 'Marseille'),
    ('France', 'Nice'),
    ('France', 'Paris'),
    ('Germany', 'Berlin'),
    ('Germany', 'Cologne'),
    ('Germany', 'Dresden'),
    ('Germany', 'Frankfurt'),
    ('Germany', 'Hamburg'),
    ('Germany', 'Heidelberg'),
    ('Germany', 'Leipzig'),
    ('Germany', 'Munich'),
    ('Germany', 'Nuremberg'),
    ('Germany', 'Rothenburg'),
    ('Germany', 'Stuttgart'),
    ('Greece', 'Athens'),
    ('Greece', 'Mykonos'),
    ('Greece', 'Rhodes'),
    ('Greece', 'Santorini'),
    ('Greece', 'Thessaloniki'),
    ('Ireland', 'Cork'),
    ('Ireland', 'Dublin'),
    ('Ireland', 'Galway'),
    ('Ireland', 'Kilkenny'),
    ('Italy', 'Florence'),
    ('Italy', 'Milan'),
    ('Italy', 'Naples'),
    ('Italy', 'Rome'),
    ('Italy', 'Venice'),
    ('Japan', 'Kyoto'),
    ('Japan', 'Osaka'),
    ('Japan', 'Tokyo'),
    ('Mexico', 'Cabo San Lucas'),
    ('Mexico', 'Cancun'),
    ('Mexico', 'Mexico City'),
    ('Netherlands', 'Amsterdam'),
    ('Netherlands', 'Rotterdam'),
    ('Netherlands', 'The Hague'),
    ('Netherlands', 'Utrecht'),
    ('New_Zealand', 'Auckland'),
    ('New_Zealand', 'Queenstown'),
    ('New_Zealand', 'Wellington'),
    ('Norway', 'Bergen'),
    ('Norway', 'Oslo'),
    ('Norway', 'Tromsø'),
    ('Peru', 'Arequipa'),
    ('Peru', 'Cusco'),
    ('Peru', 'Lima'),
    ('Poland', 'Gdansk'),
    ('Poland', 'Krakow'),
    ('Poland', 'Warsaw'),
    ('Poland', 'Wroclaw'),
    ('Portugal', 'Faro'),
    ('Portugal', 'Lisbon'),
    ('Portugal', 'Madeira'),
    ('Portugal', 'Porto'),
    ('Spain', 'Barcelona'),
    ('Spain', 'Madrid'),
    ('Spain', 'Seville'),
    ('Sweden', 'Gothenburg'),
    ('Sweden', 'Malmö'),
    ('Sweden', 'Stockholm'),
    ('Switzerland', 'Bern'),
    ('Switzerland', 'Geneva'),
    ('Switzerland', 'Interlaken'),
    ('Switzerland', 'Lausanne'),
    ('Switzerland', 'Lucerne'),
    ('Switzerland', 'St. Moritz'),
    ('Switzerland', 'Zermatt'),
    ('Switzerland', 'Zurich'),
    ('Thailand', 'Bangkok'),
    ('Thailand', 'Chiang Mai'),
    ('Thailand', 'Phuket'),
    ('United_Kingdom', 'Edinburgh'),
    ('United_Kingdom', 'London'),
    ('United_Kingdom', 'Manchester'),
    ('Uruguay', 'Colonia del Sacramento'),
    ('Uruguay', 'Montevideo'),
    ('Uruguay', 'Punta del Este'),
    ('United_States', 'Boston'),
    ('United_States', 'Chicago'),
    ('United_States', 'Las Vegas'),
    ('United_States', 'Los Angeles'),
    ('United_States', 'Miami'),
    ('United_States', 'New York'),
    ('United_States', 'Orlando'),
    ('United_States', 'San Francisco'),
    ('United_States', 'Seattle');
    
CREATE TABLE config_doctor_clinic (
    id SERIAL PRIMARY KEY,
    doctor TEXT,
    clinic TEXT,
    date_created TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    date_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
   
INSERT INTO config_doctor_clinic (doctor, clinic) VALUES
    ('Sarah_Chen', 'Downtown Medical'),
    ('Sarah_Chen', 'Westside Health'),
    ('James_Wilson', 'Downtown Medical'),
    ('James_Wilson', 'Eastside Clinic'),
    ('Maria_Garcia', 'Westside Health'),
    ('Maria_Garcia', 'Eastside Clinic');   

-- Create a single function for all timestamp updates
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.date_updated = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create the config_demographics table
CREATE TABLE config_demographics (
    id SERIAL PRIMARY KEY,
    field_name VARCHAR(50),
    field_type VARCHAR(50),
    choices JSONB,
    date_created TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    date_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert configurations from the survey
INSERT INTO config_demographics (field_name, field_type, choices)
VALUES 
    ('age_group', 
     'radiogroup',
     '["18-24", "25-34", "35-44", "45-54", "55-64", "65 or older"]'::jsonb
    ),
    ('gender',
     'radiogroup',
     '["Male", "Female", "Non-binary", "Transgender", "Prefer not to say"]'::jsonb
    ),
    ('education',
     'dropdown',
     '["High School or equivalent", "Some College", "Bachelor''s Degree", "Master''s Degree", "Doctorate", "Other"]'::jsonb
    ),
    ('employment',
     'checkbox',
     '["Full-time employed", "Part-time employed", "Self-employed", "Student", "Retired", "Unemployed"]'::jsonb
    );

-- Create timestamp update triggers for all tables
CREATE TRIGGER update_timestamp_trigger_surveys
    BEFORE UPDATE ON surveys
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_timestamp_trigger_config_pid
    BEFORE UPDATE ON config_pid
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();
    
CREATE TRIGGER update_timestamp_trigger_config_vacation
    BEFORE UPDATE ON config_vacation
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_timestamp_trigger_config_doctor_clinic
    BEFORE UPDATE ON config_doctor_clinic
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();
    
CREATE TRIGGER update_timestamp_trigger_config_demographics
    BEFORE UPDATE ON config_demographics
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();
