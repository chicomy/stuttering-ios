# ease iOS App Design

## Product Summary

`ease` is a native iOS app concept for people who stutter. It should feel calm, light, and emotionally safe. The app is not meant to feel clinical, diagnostic, or performance-driven. Its main purpose is to support users in the moment by listening to speech rhythm and gently slowing the flow when tension appears.

## Core Product Direction

- Platform: native iOS app
- Implementation direction: SwiftUI
- Primary experience for v1: guided speaking practice
- Future direction: extend from guided practice into more real-time support

## Product Positioning

The app should feel like a quiet speech support tool, not a tracker, coach mascot, or therapy dashboard.

Desired qualities:

- lightweight
- low-pressure
- minimal cognitive load
- emotionally safe
- supportive rather than evaluative

Avoid:

- mascots or character-led UI
- streaks, gamification, or achievement framing
- harsh alerts
- clinical language
- heavy analytics or score-driven summaries

## V1 User Experience

The first version should focus on one simple loop:

1. Enter a calm practice session
2. Speak into the app
3. Let the app listen for rhythm disruption, blocking, repetition, or rushed pacing
4. When tension is detected, the app gently slows the flow
5. End with a soft, non-judgmental reflection

## Primary Screens

### 1. Home

Purpose:

- welcome the user
- reduce pressure before speaking
- present one clear action

Content:

- brand: `ease`
- warm greeting
- short reassurance line
- one main CTA to begin practice
- a small pre-session prompt such as “Start softly. Let your voice find its rhythm.”

### 2. Practice

Purpose:

- act as the main live support experience
- listen to speech rhythm
- shift the session when tension appears

Two key states:

- `listening`
  - copy example: `Listening to your rhythm`
  - visually quiet and steady
- `slow-down support`
  - copy examples:
    - `Let's slow down`
    - `Pause here`
    - `Take one breath`
    - `Continue when ready`
  - more breathing room in the layout
  - pacing visuals should soften and slow

Important:

- this screen should not look like a generic recording UI
- the central circular control should feel like a pacing or breathing guide
- the app should feel present but unobtrusive

### 3. Reflection

Purpose:

- close the session gently
- highlight support, not performance

Content direction:

- a reassuring opening line
- a soft rhythm summary
- a “steadier moments” view
- a “where we slowed down” view
- one small next-step suggestion

Preferred tone:

- non-judgmental
- calm
- specific enough to be useful
- never framed as failure or poor performance

## Visual Direction

Reference direction:

- soft, tactile, psychologically safe digital product
- lighter and more restrained than playful wellness apps

Visual principles:

- soft sage green, warm white, muted neutrals, pale misty blue
- generous whitespace
- rounded cards
- subtle depth
- premium but not cold
- no cartoon energy
- no heavy gradients
- no visually noisy dashboards

Typography:

- elegant serif for larger emotional headlines
- clean sans-serif for body and controls

## Interaction Principles

- one main action per screen
- minimal text during live use
- feedback should guide the next step instead of labeling the user
- use pacing, spacing, and motion to communicate support
- reduce the feeling of being monitored

## Product Language

Prefer language like:

- `Start softly`
- `Listening to your rhythm`
- `Let's slow down`
- `Take one breath`
- `Continue when ready`
- `Steadier moments`
- `Where we slowed down together`

Avoid language like:

- `score`
- `streak`
- `effortful`
- `performance`
- `improvement metrics`

## Technical Direction

Native iOS stack:

- SwiftUI for UI
- AVAudioSession and AVAudioEngine for microphone access and live audio input
- a lightweight rhythm/tension analyzer for v1
- a clear state model for screen flow and practice mode

Recommended early state model:

- app screen
  - `home`
  - `practice`
  - `reflection`
- practice mode
  - `listening`
  - `slowDownSupport`

## V1 Scope

Include:

- native SwiftUI app shell
- the three core screens
- live practice state transitions
- simulated or basic rhythm-driven slow-down support
- gentle reflection output

Do not include yet:

- complex speech scoring
- deep historical analytics
- achievement systems
- social features
- mascot-led onboarding
- overly complex settings

## Figma Reference

Design file:

- [stuttering-app](https://www.figma.com/design/625pqIVoZOe09f2h2hWIal/stuttering-app?node-id=0-1&p=f&t=S0UuU2oGXZQgGrrk-0)

Important note for implementation:

- treat the Figma file as the visual source of truth
- keep the product direction centered on a real native iOS app, not a web prototype

## Handoff Summary

The next development thread should start from a fresh native iOS SwiftUI implementation of `ease`, using this document and the linked Figma file as the primary references.
