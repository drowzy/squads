# Feature: Redesign Agent View Layout for Maximized Chat Area

## Description
The current layout of the Agent view (e.g., `/agent/[id]`) does not prioritize the chat interface enough. Session history and statistics currently occupy significant space that could be better utilized for the primary interaction area.

## Requirements
- **Header Integration:** Move the session history and statistics (e.g., token usage, duration, status) into the header section of the Agent view.
- **Main View Expansion:** Reorganize the main view so that the Chat UI and any associated tabs (like the Task list or Logs) expand to fill the remaining vertical and horizontal space.
- **Improved Hierarchy:** Ensure that the most critical interaction element—the chat—is the focal point of the page.

## Context
As users spend most of their time interacting with the agent via chat, maximizing the chat's real estate improves usability and reduces the need for excessive scrolling. Moving secondary information like statistics to the header keeps them accessible but out of the way of the main workflow.

## Proposed Resolution/Investigation
- Refactor the Agent view component structure to use a more header-heavy layout.
- Use Flexbox or Grid to ensure the chat container dynamically fills the viewport height below the header.
- Review how tabs are integrated to ensure they don't compromise the expanded chat space.
