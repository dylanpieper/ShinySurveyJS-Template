-- Create the survey config table
CREATE TABLE surveys (
    id SERIAL PRIMARY KEY,
    survey_name VARCHAR(255) NOT NULL,
    config_json JSON,
    json TEXT NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    start_date TIMESTAMP WITH TIME ZONE,
    end_date TIMESTAMP WITH TIME ZONE,
    created_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(survey_name)
);

-- Insert the configs
INSERT INTO surveys (survey_name, config_json, json)
VALUES 
    ('dynamic_survey_1', 
    '{
        "table_name": "organization_location",
        "group_col": "organization",
        "select_group": false
    }'::json,
    '{
        "title": "Dynamic Survey (Example 1)",
        "description": "Case: Assign group in URL query parameter, no selections for group or additional choices",
        "elements": [
            {
                "type": "text",
                "name": "name",
                "title": "What is your name?",
                "isRequired": true
            }
        ]
    }'),
    
    ('dynamic_survey_2', 
    '{
        "table_name": "organization_location",
        "group_col": "organization",
        "select_group": true
    }'::json,
    '{
        "title": "Dynamic Survey (Example 2)",
        "description": "Case: Select group, no additional choices",
        "elements": [
            {
                "type": "text",
                "name": "name",
                "title": "What is your name?",
                "isRequired": true
            },
            {
                "type": "dropdown",
                "name": "organization",
                "title": "Select your organization:",
                "choices": [],
                "isRequired": true
            }
        ]
    }'),
    
    ('dynamic_survey_3',
    '{
        "table_name": "organization_location",
        "group_col": "organization",
        "select_group": false,
        "choices_col": "location"
    }'::json,
    '{
        "title": "Dynamic Survey (Example 3)",
        "description": "Case: Assign group in URL query parameter, select from additional choices",
        "elements": [
            {
                "type": "text",
                "name": "name",
                "title": "What is your name?",
                "isRequired": true
            },
            {
                "type": "dropdown",
                "name": "location",
                "title": "Select your location:",
                "choices": [],
                "isRequired": true
            }
        ]
    }'),
    
    ('dynamic_survey_4',
    '{
        "table_name": "organization_location",
        "group_col": "organization",
        "select_group": true,
        "choices_col": "location"
    }'::json,
    '{
        "title": "Dynamic Survey (Example 4)",
        "description": "Case: Select group, select from additional choices",
        "elements": [
            {
                "type": "text",
                "name": "name",
                "title": "What is your name?",
                "isRequired": true
            },
            {
                "type": "radiogroup",
                "name": "organization",
                "title": "Select your organization:",
                "choices": [],
                "isRequired": true
            },
            {
                "type": "dropdown",
                "name": "location",
                "title": "Select your location:",
                "choices": [],
                "isRequired": true,
                "visibleIf": "{organization} notempty"
            }
        ]
    }'),
    
    ('dynamic_person_id',
    '{
        "table_name": "doctor_clinic",
        "group_col": "doctor",
        "select_group": false,
        "choices_col": "clinic"
    }'::json,
    '{
        "title": "Person ID",
        "description": "Case: Assign person ID to doctors in URL query parameter with a selection for the clinic they work in",
        "elements": [
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
                "choices": [
                    "CBT",
                    "Mindfulness",
                    "Crisis Management",
                    "Skills Training"
                ]
            },
            {
                "type": "text",
                "name": "notes",
                "title": "Session Notes"
            },
            {
                "type": "dropdown",
                "name": "next_session",
                "title": "Next Session",
                "choices": [
                    "1 week",
                    "2 weeks",
                    "As needed"
                ]
            }
        ],
        "showQuestionNumbers": "off",
        "widthMode": "responsive"
    }'),
    
    ('static_survey', 
    NULL,
    '{
        "title": "Static Survey",
        "pages": [
            {
                "name": "page1",
                "elements": [
                    {
                        "type": "radiogroup",
                        "name": "product_quality",
                        "title": "What is your opinion on the quality of our product?",
                        "choices": ["Excellent", "Good", "Fair", "Poor"]
                    },
                    {
                        "type": "comment",
                        "name": "suggestions",
                        "title": "What would make our product better?"
                    },
                    {
                        "type": "rating",
                        "name": "product_satisfaction",
                        "title": "How satisfied are you with the product?",
                        "rateMin": 0,
                        "rateMax": 5,
                        "rateStep": 1
                    },
                    {
                        "type": "dropdown",
                        "name": "recommend_product",
                        "title": "Would you recommend our product to your friends?",
                        "choices": ["Definitely", "Maybe", "Not sure", "Never"]
                    }
                ]
            }
        ]
    }');

-- Create the tables for the dynamic survey examples
CREATE TABLE organization_location (
    id SERIAL PRIMARY KEY,
    organization TEXT,
    location TEXT,
    date_created TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
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
    id SERIAL PRIMARY KEY,
    doctor TEXT,
    clinic TEXT,
    date_created TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
   
INSERT INTO doctor_clinic (doctor, clinic) VALUES
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
    NEW.updated = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create timestamp update triggers for all tables
CREATE TRIGGER update_timestamp_trigger
    BEFORE UPDATE ON surveys
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_timestamp_trigger
    BEFORE UPDATE ON organization_location
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_timestamp_trigger
    BEFORE UPDATE ON doctor_clinic
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();
