# Bug: Remove Assignee from TODO Lane in /board

## Description
The TODO lane in the `/board` view currently displays an assignee for tasks. Since this lane represents the general pipeline of tasks that haven't been claimed or started yet, having an assignee is incorrect.

## Context
Tasks in the TODO lane are waiting to be picked up. Assigning them at this stage is premature and inconsistent with standard Kanban/Board workflows where assignment typically happens when a task moves to "In Progress".

## Proposed Resolution/Investigation
- Update the UI component for tasks in the TODO lane to hide or remove the assignee field.
- Ensure that the backend or state management still allows for assignment once the task moves to another lane (e.g., In Progress).
- Verify the layout remains consistent after removing the assignee element.
