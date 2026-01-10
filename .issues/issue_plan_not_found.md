# Bug: `issue_plan_not_found` error when creating issues

## Description
After the agent completed a codebase analysis and outputted a detailed issue template (in JSON format), attempting to use the "create issues" functionality resulted in an error.

## Error Message
```json
{
  "errors": {
    "detail": "issue_plan_not_found"
  },
  "detail": "issue_plan_not_found"
}
```

## Context
The agent had just proposed a set of 10 GitHub issues for a refactoring task, including:
- Extracting language mapping utility functions.
- Creating InputParams base classes hierarchy.
- Creating frame import presets module.
- Enhancing WebsocketService base class.
- Creating LifecycleMixin.
- Creating error handling decorators.
- Creating frame dispatch decorators.
- Creating SettingsManager.
- Creating provider-specific aggregator factory.
- Final integration and testing.

The output included a full JSON structure with `repo`, `prd_path`, `questions`, and `issues` array. However, the subsequent step to actually create these issues on GitHub failed with the `issue_plan_not_found` error.

## Proposed Resolution/Investigation
- Investigate why the issue plan (the JSON output) was not correctly registered or persisted for the "create issues" action to pick up.
- Verify if the state is lost between the output of the proposal and the execution of the creation command.
- Consider if the agent should use the `gh` CLI directly to create issues if the built-in integration fails.
