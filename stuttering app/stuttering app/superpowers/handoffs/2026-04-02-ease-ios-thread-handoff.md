# ease iOS Development Handoff

## Start Point

Begin a new development thread for a native SwiftUI iOS app called `ease`.

Use these references first:

- [Design spec](/Users/chongmiw/Documents/Appolio/app/test app/docs/superpowers/specs/2026-04-02-ease-ios-design.md)
- [Figma file](https://www.figma.com/design/625pqIVoZOe09f2h2hWIal/stuttering-app?node-id=0-1&p=f&t=S0UuU2oGXZQgGrrk-0)

## Build Goal

Create a real iOS app with:

- `Home`
- `Practice`
- `Reflection`

using:

- SwiftUI
- native iOS navigation/state flow
- a practice state model with `listening` and `slowDownSupport`

## Implementation Priorities

1. Create a new native iOS app project
2. Port the visual language from Figma into SwiftUI
3. Implement the screen flow:
   - home -> practice -> reflection
4. Implement a `PracticeViewModel`
5. Use a placeholder or simple signal for live slow-down support first
6. Keep copy, spacing, and tone aligned with the design spec

## Guardrails

- do not turn the app into a habit tracker
- do not add mascots
- do not introduce streaks, scores, or gamification
- do not make the live screen feel like a generic recorder
- do not use clinical wording unless truly necessary

## Recommended First Deliverable

A compilable SwiftUI app skeleton with:

- visual parity for the three main screens
- tappable transitions between screens
- visible `listening` and `slowDownSupport` states on the practice screen

## Thread Prompt Suggestion

Use this in the new thread if helpful:

`Build a native SwiftUI iOS app for the ease concept. Start from the design spec at docs/superpowers/specs/2026-04-02-ease-ios-design.md and the linked Figma file. Create a real iOS app project and implement the Home, Practice, and Reflection screens first.`
