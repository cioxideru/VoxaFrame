# SmartTube Swift package

The package contains `SmartTubeIOSCore` (models, APIs, stores and decision logic) and
`SmartTubeIOS` (views, view models and platform services). App and extension targets live in
`../SmartTubeApp/`; open `SmartTube.xcworkspace` from the repository root.

See the [project overview](../README.md), [architecture](../docs/architecture.md),
[development rules](../AGENTS.md), and [test guide](../docs/how-to/run-tests.md).
The Foundation-only Core boundary is the intended rule; existing platform imports are tracked
in [open questions](../docs/OPEN_QUESTIONS.md#oq-0009--architecture-debt).

From this directory, run `swift test --filter <Suite>` for a package suite. For full project
checks and simulator builds, use the scripts described in the agent guide.

OAuth tokens are owned by `TokenManager` and stored in Keychain. Stream URLs are short-lived;
see the architecture and playback notes before changing refresh behavior.
