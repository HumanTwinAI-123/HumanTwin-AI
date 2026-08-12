# HumanTwin AI — Shared Agent Rules

This file contains stable, repository-wide rules shared by Codex, Grok, Cursor,
and other AI development tools. It intentionally does not duplicate changing
Day plans or the full project lead instructions.

## Project Scope

HumanTwin AI is a Chinese-language AI digital-human Flutter demo. The product is
limited to these six core screens:

1. Home
2. Photo Guide
3. Photo Selection
4. Photo Confirmation
5. AI Processing
6. 3D Viewer

Do not proactively add login, profile, history, health analysis, an AI doctor,
payments, AR, clothing, Firebase, cloud storage, a real backend, real AI
reconstruction, or a seventh core screen.

The demo boundary is real Flutter UI and photo selection, a mock AI generation
pipeline, and a pre-generated local GLB. Never describe it as real AI body
reconstruction or a production medical system.

## Frozen Technical Stack

Keep the established stack:

- Flutter 3.44.9 and Dart 3.12.2
- Material 3
- Riverpod 3.3.2
- go_router 17.3.0
- image_picker 1.2.3 with `XFile`
- model_viewer_plus 1.10.0
- Local GLB assets
- Android-first delivery

Do not proactively add Dio, Freezed, build_runner, GetIt, Retrofit, Firebase, a
new state-management library, a new 3D package, or Unity. Do not run
`flutter pub upgrade` or `flutter pub upgrade --major-versions`.

## Architecture

Preserve the project contract:

```text
UI
→ Riverpod Controller
→ DigitalTwinRepository
→ MockDigitalTwinRepository
```

A future real API may replace only the repository implementation. Do not add
UseCase, Datasource, Domain Layer, Service Locator, Mapper, Event Bus, complex
dependency injection, or enterprise Clean Architecture layers.

`PhotoFlowController` is the only source of truth for the front, side, and back
`XFile` photos. Do not create confirmation-specific copies or a second photo
controller, and do not pass the three photos through `go_router extra`.

## Approved UI

Screens marked Approved or frozen are immutable by default. Modify one only for
an explicit P0/P1 bug or when the user explicitly requests the change. Do not
change Approved screens for cleanup, consistency, refactoring, or personal
design preference.

The visual direction is **Clinical Spatial Premium**: restrained, trustworthy,
precise medical technology with limited ice-blue accents. Preserve SafeArea,
responsive layouts, short-screen scrolling, and text-scale behavior.

Approved Design > AI Preference.

## AI Collaboration

One feature has exactly one primary implementation agent. Codex is the default.

- ChatGPT: Product / Technical Lead and scope decisions
- Codex: Primary Implementation Agent for formal feature implementation
- Grok / Grok Build: planning, architectural critique, second opinion, and code review
- Cursor: local pair programming, code navigation, debugging, UI fine-tuning,
  and small targeted fixes
- User: final approval and acceptance

Grok and Cursor must not independently reimplement or create competing versions
of a feature assigned to Codex.

Any proposal from Grok, Cursor, ChatGPT, Figma AI, or another AI is reference
material, not an approved requirement. New architecture, packages, state,
large refactors, or scope expansion require explicit user approval before
implementation.

### Grok quick usage

Ask Grok to work read-only and use a Plan / Review mindset: inspect the relevant
code or diff, trace risks, and report findings. Do not assign Grok as the default
feature implementation agent or ask it to modify the whole repository.

## Change Discipline

Before editing, inspect `git status`, `HEAD`, `origin/main`, the relevant code,
and existing project rules. State the intended result, the files expected to
change, and a short execution plan.

Prefer one clear outcome and a small change, normally about 3–5 primary files.
Explain before proceeding when more than five primary files are genuinely
required. Do not touch unrelated files, perform opportunistic refactors, or
start the next Day without explicit user direction.

If the user asks only to inspect, analyze, review, or explain why, investigate
and report first; do not edit automatically.

Without explicit user authorization, do not commit, push, reset, rebase, force
push, delete unrelated files, install dependencies, or change global AI-tool
configuration.

## Verification

For implementation code changes, run:

```text
flutter analyze --no-pub
flutter test --no-pub
```

Also use proportionate Android/emulator and responsive UI verification when the
change affects a user flow. Report only checks actually run and results actually
observed.
