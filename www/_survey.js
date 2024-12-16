$(document).ready(function() {
  var survey;
  var lastLoadedSurveyJSON = null;
  var questionValues = new Map();

  function areJSONsEqual(json1, json2) {
    return JSON.stringify(json1) === JSON.stringify(json2);
  }

  function preserveQuestionValues() {
    if (survey) {
      survey.getAllQuestions().forEach(question => {
        if (question.value !== undefined) {
          questionValues.set(question.name, question.value);
          // console.log(`Preserved value for ${question.name}:`, question.value);
        }
      });
    }
  }

  function restoreQuestionValues() {
    if (survey) {
      questionValues.forEach((value, name) => {
        const question = survey.getQuestionByName(name);
        if (question) {
          // Set both the model value and update the UI
          question.value = value;
          if (question.getType() === "dropdown") {
            question.displayValue = value; // Ensure visual display is updated
          }
          // console.log(`Restored value for ${name}:`, value);
        }
      });
    }
  }

  function initializeSurvey(surveyJSON) {
    try {
      if (lastLoadedSurveyJSON && areJSONsEqual(lastLoadedSurveyJSON, surveyJSON)) {
        console.log("Identical survey JSON. Skipping re-initialization.");
        return;
      }

      // console.log("Initializing survey with JSON:", surveyJSON);
      
      preserveQuestionValues();
      
      if (typeof surveyJSON === 'string') {
        surveyJSON = JSON.parse(surveyJSON);
      }
      
      $("#surveyContainer").empty();
      
      // Configure survey settings with focus on dropdown behavior
      Survey.settings.dropdown = {
        searchEnabled: true,
        closeOnSelect: true,
        preserveSelectedPosition: true,
        renderMode: "modern"
      };
      
      survey = new Survey.Model(surveyJSON);
      
      lastLoadedSurveyJSON = surveyJSON;
      
      // Restore values before rendering
      restoreQuestionValues();
      
      survey.onComplete.add(function(result) {
        // console.log("Survey completed. Data:", result.data);
        Shiny.setInputValue("surveyData", JSON.stringify(result.data));
      });
      
      survey.onValueChanged.add(function(sender, options) {
        // console.log("Value changed:", {
        //   fieldName: options.name,
        //   value: options.value,
        //   previousValue: options.previousValue
        // });
        
        questionValues.set(options.name, options.value);
        
        Shiny.setInputValue("selectedChoice", {
          fieldName: options.name,
          selected: options.value
        });
      });

      // Enhanced dropdown rendering
      survey.onAfterRenderQuestion.add(function(sender, options) {
        if (options.question.getType() === "dropdown") {
          const storedValue = questionValues.get(options.question.name);
          if (storedValue !== undefined) {
            // Force immediate value update and UI refresh
            options.question.value = storedValue;
            options.question.displayValue = storedValue;
            
            // Ensure the dropdown UI is updated
            const dropdownEl = options.htmlElement.querySelector("select");
            if (dropdownEl) {
              dropdownEl.value = storedValue;
              // Trigger change event to ensure UI updates
              const event = new Event('change', { bubbles: true });
              dropdownEl.dispatchEvent(event);
            }
          }
        }
      });
      
      $("#surveyContainer").Survey({ model: survey });
      
      console.log("Survey initialized");
    } catch (error) {
      console.error("Error initializing survey:", error);
      console.trace();
    }
  }
  
  Shiny.addCustomMessageHandler("loadSurvey", function(surveyJSON) {
    // console.log("Received loadSurvey message with JSON:", surveyJSON);
    initializeSurvey(surveyJSON);
  });
  
  Shiny.addCustomMessageHandler("updateChoices", function(data) {
    // console.log("Received updateChoices message:", data);
    
    if (!survey) {
      console.error("Survey not initialized when trying to update choices");
      return;
    }
    
    const targetQuestion = survey.getQuestionByName(data.targetQuestion);
    if (!targetQuestion) {
      console.warn("Target question not found:", data.targetQuestion);
      return;
    }
    
    const currentValue = targetQuestion.value;
    // console.log("Current value before update:", currentValue);
    
    targetQuestion.choices = data.choices.map(choice => ({
      value: choice,
      text: choice
    }));
    
    if (currentValue && data.choices.includes(currentValue)) {
      // Update both value and display value immediately
      targetQuestion.value = currentValue;
      targetQuestion.displayValue = currentValue;
      
      // Force UI update
      const dropdownEl = targetQuestion.dropdownEl || 
                        document.querySelector(`[name="${data.targetQuestion}"]`);
      if (dropdownEl) {
        dropdownEl.value = currentValue;
        const event = new Event('change', { bubbles: true });
        dropdownEl.dispatchEvent(event);
      }
      
      survey.render();
    }
    
    // console.log("Updated choices for question:", data.targetQuestion);
  });
});