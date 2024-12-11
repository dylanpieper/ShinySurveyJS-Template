-- Create the survey configurations table
CREATE TABLE surveys (
    id SERIAL PRIMARY KEY,
    survey_name VARCHAR(255) NOT NULL,
    config_json JSON,
    json TEXT NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    start_date TIMESTAMP WITH TIME ZONE,
    end_date TIMESTAMP WITH TIME ZONE,
    created_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(survey_name)
);

-- Insert the configurations
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
        "title": "Dyanmic Survey (Example 3)",
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
                "name": "sessionType",
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
                "name": "nextSession",
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
                        "name": "productQuality",
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
                        "name": "productSatisfaction",
                        "title": "How satisfied are you with the product?",
                        "rateMin": 0,
                        "rateMax": 5,
                        "rateStep": 1
                    },
                    {
                        "type": "dropdown",
                        "name": "recommendProduct",
                        "title": "Would you recommend our product to your friends?",
                        "choices": ["Definitely", "Maybe", "Not sure", "Never"]
                    }
                ]
            }
        ]
    }');

-- Create a function for updating the timestamp
CREATE OR REPLACE FUNCTION update_updated_date()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_date = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create a trigger to automatically update the updated_date
CREATE TRIGGER update_surveys_modtime
    BEFORE UPDATE ON surveys
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_date();
    
-- Create the tables for the dynamic survey examples
 CREATE TABLE organization_location (
    id SERIAL PRIMARY KEY,
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
    id SERIAL PRIMARY KEY,
    doctor TEXT,
    clinic TEXT
);
   
INSERT INTO doctor_clinic (doctor, clinic) VALUES
    ('Sarah_Chen', 'Downtown Medical'),
    ('Sarah_Chen', 'Westside Health'),
    ('James_Wilson', 'Downtown Medical'),
    ('James_Wilson', 'Eastside Clinic'),
    ('Maria_Garcia', 'Westside Health'),
    ('Maria_Garcia', 'Eastside Clinic');   
    
-- Add timestamp columns to organization_location
ALTER TABLE organization_location
ADD COLUMN date_created TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Add timestamp columns to doctor_clinic
ALTER TABLE doctor_clinic
ADD COLUMN date_created TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Create or replace the function for updating the timestamp
-- (Using a different name to avoid conflict with existing function)
CREATE OR REPLACE FUNCTION update_timestamp_columns()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for each table
CREATE TRIGGER update_organization_location_timestamp
    BEFORE UPDATE ON organization_location
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp_columns();

CREATE TRIGGER update_doctor_clinic_timestamp
    BEFORE UPDATE ON doctor_clinic
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp_columns();