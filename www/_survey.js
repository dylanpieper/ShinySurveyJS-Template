$(document).ready(function() {
  var survey;
  var lastLoadedSurveyJSON = null;

  function areJSONsEqual(json1, json2) {
    // Deep comparison of survey JSON
    return JSON.stringify(json1) === JSON.stringify(json2);
  }

  function initializeSurvey(surveyJSON) {
    // Check if the survey JSON is exactly the same as the last loaded
    if (lastLoadedSurveyJSON && areJSONsEqual(lastLoadedSurveyJSON, surveyJSON)) {
      console.log("Identical survey JSON. Skipping reinitialization.");
      return;
    }

    try {
      console.log("Initializing survey with JSON:", surveyJSON);
      
      // Parse surveyJSON string into an object
      if (typeof surveyJSON === 'string') {
        surveyJSON = JSON.parse(surveyJSON);
      }
      
      // Clear existing survey
      $("#surveyContainer").empty();
      
      // Initialize the survey model with the JSON
      survey = new Survey.Model(surveyJSON);
      
      // Store the last loaded JSON to prevent duplicate loads
      lastLoadedSurveyJSON = surveyJSON;
      
      // Setup to send survey results to server upon completion
      survey.onComplete.add(function(result) {
        console.log("Survey completed. Data:", result.data);
        Shiny.setInputValue("surveyData", JSON.stringify(result.data));
      });
      
      // Add a listener for value changes in the survey
      survey.onValueChanged.add(function(sender, options) {
        console.log("Value changed:", {
          fieldName: options.name,
          value: options.value,
          previousValue: options.previousValue
        });
        
        // Send the selected choice back to the Shiny server
        Shiny.onInputChange("selectedChoice", {
          fieldName: options.name,
          selected: options.value
        });
      });
      
      // Additional debug logging for survey questions
      console.log("Survey Questions:", survey.getAllQuestions().map(q => q.name));
      
      // Display the survey in the designated container
      $("#surveyContainer").Survey({ model: survey });
      
      console.log("Survey initialization complete");
    } catch (error) {
      // Log initialization errors in detail
      console.error("Error initializing survey:", error);
      console.trace(); // Provide a stack trace for more context
    }
  }
  
  // Handle survey loading requests
  Shiny.addCustomMessageHandler("loadSurvey", function(surveyJSON) {
    console.log("Received loadSurvey message with JSON:", surveyJSON);
    initializeSurvey(surveyJSON);
  });
  
  // Handle requests to update survey choices dynamically
  Shiny.addCustomMessageHandler("updateChoices", function(data) {
    console.log("Received updateChoices message:", data);
    
    if (survey) {
      var targetQuestion = survey.getQuestionByName(data.targetQuestion);
      
      if (targetQuestion) {
        console.log("Found target question:", targetQuestion.name);
        
        // Update question choices based on incoming data
        targetQuestion.choices = data.choices.map(choice => {
          console.log("Adding choice:", choice);
          return { value: choice, text: choice };
        });
        
        survey.render();
        console.log("Updated choices for question:", data.targetQuestion);
      } else {
        console.warn("Target question not found:", data.targetQuestion);
      }
    } else {
      console.error("Survey not initialized when trying to update choices");
    }
  });
});