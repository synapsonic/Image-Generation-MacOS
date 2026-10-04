# LayerAI for macOS

LayerAI is an experimental native macOS image editor built around **AI-generated, recursively editable layers**. Instead of treating an AI image as a single flattened bitmap, LayerAI is designed to represent a scene as a hierarchy of objects that can be selected, prompted, regenerated, masked, versioned, and recomposed independently.

> Current project version: **v0.7.3 (stabilized)**

## Requirements

- macOS 14.0 or later
- Xcode with a compatible macOS SDK
- Swift / SwiftUI
- Internet access for remote AI providers
- An API key for the provider you want to use

## Getting started

1. Extract the project archive.
2. Open `Image Generation.xcodeproj` in Xcode.
3. Select the `Image Generation` macOS target.
4. Run **Product → Clean Build Folder** (`Shift + Command + K`).
5. Build with `Command + B`.
6. Run the app with `Command + R`.
7. During onboarding, select an available AI provider and enter your API key.

API keys are intended to be stored in the **macOS Keychain**, rather than committed to the source tree.

## Current features

LayerAI currently includes the foundations of the planned editor:

- Native SwiftUI macOS interface
- Recursive scene/layer hierarchy
- Per-layer prompts and generation metadata
- Layer visibility and opacity controls
- AI generation workflow
- OpenAI image provider integration
- Local object-selection workflow
- Bitmap masks attached to layers
- Local region-growing segmentation fallback
- Smart Select workflow from a point clicked on the canvas
- Per-layer generation history
- Version restoration
- Undo / Redo foundations
- Before / After comparison workflow
- Masked editing pipeline foundations
- macOS Keychain API-key storage
- macOS App Sandbox outgoing-network entitlement

## AI providers

### OpenAI

OpenAI is the currently implemented remote image provider. Requests use the official API host:

`https://api.openai.com/v1/`

The application requires outbound network access. The Xcode project enables the macOS App Sandbox outgoing client-network entitlement.

### Gemini

Gemini may appear in parts of the provider UI/architecture, but its image-generation adapter is **not yet considered production-ready in this version**.

### fal.ai

fal.ai is planned as an additional provider. A production distribution should carefully consider whether provider credentials should be sent directly from a desktop client or proxied through a controlled backend.

## Architecture

The important source files currently include:

- `Image_GenerationApp.swift` — application entry point
- `ContentView.swift` — main editor UI and editor state
- `AppState.swift` — application/onboarding/provider state
- `SceneModels.swift` — recursive scene and layer data models
- `AIService.swift` — AI-provider abstraction and image requests
- `SegmentationService.swift` — segmentation abstraction and local selection engine

The long-term document model is based on a scene graph such as:

```text
Scene
├── Background
│   ├── Sky
│   ├── Buildings
│   └── Ground
└── Subject
    ├── Face
    ├── Hair
    └── Clothes
        ├── Jacket
        └── Pants
```

Each node can ultimately own its own image, mask, prompt, provider configuration, transformations, children, and generation history.

## Smart Select

The current local selection engine provides a fallback that can work without a dedicated segmentation server. It uses local pixel similarity / region-growing concepts to create a bitmap mask around a clicked point.

This architecture is intentionally abstracted behind a segmentation provider so that a more capable model such as SAM/SAM 2 or another segmentation service can replace the fallback later without redesigning the editor or document model.

## Security

Do **not** commit API keys into Swift files, configuration files, Git history, screenshots, or distributable archives.

LayerAI is designed to use the macOS Keychain for user-supplied secrets. Before commercial distribution, provider-specific security requirements should be reviewed and server-side proxying should be used where exposing a provider credential in a desktop application is inappropriate.

## Known limitations

v0.7.3 is a development build, not a production release. In particular:

- Only the OpenAI path is currently intended to perform real remote image generation.
- Smart Select is not yet equivalent to semantic object segmentation from a dedicated vision model.
- Masked editing and compositing are still evolving.
- The final `.aiimg` project package format is not yet implemented.
- Layer transforms and drag-and-drop layer organization are planned for a later version.
- The project should be validated with the exact Xcode/macOS SDK used for release before distribution.

## Roadmap

Planned milestones include semantic object segmentation, higher-quality masked regeneration, direct canvas transforms, layer duplication/deletion/renaming, drag-and-drop scene hierarchy editing, a persistent `.aiimg` package format, additional AI providers, PSD/export workflows, and more advanced non-destructive compositing.

## Troubleshooting

If Xcode reports stale or apparently duplicated compiler errors after updating the project, first use **Product → Clean Build Folder**, then rebuild.

If an API request reports that the server hostname cannot be found, verify that the target has the **Outgoing Connections (Client)** App Sandbox capability enabled and that the provider endpoint is correct.

If errors mention `ObservableObject`, `@Published`, or the defining module `Combine`, ensure files declaring those types import `Combine`.

## Project status

LayerAI is currently an experimental editor under active development. The priority of the v0.7.x line is a stable, understandable foundation before adding more editor functionality.
