> Status: current — non-adoption checked against Package.swift on 2026-10-15.

# AetherEngine — considered, not adopted

**Summary:** A 2026-05-23 proposal to replace AVPlayer's direct CDN fetching with
[AetherEngine](https://github.com/superuser404notfound/AetherEngine) (FFmpeg-based, custom HTTP
headers including the iOS YouTube User-Agent, proxied through a local HLS-fMP4 server on
`127.0.0.1` so AVPlayer never talks to the CDN directly) — aimed at fixing CDN 403s on
non-embeddable videos caused by AVPlayer's own request headers not matching the URL's signing
context. **Never actually integrated**: no `AetherEngine` package dependency exists in
`Package.swift`, and the only reference in the current codebase is a comment in
`PlaybackViewModel+StreamAttempts.swift` explaining why it *can't* be used at that call site
("AetherEngine cannot be used here because FFmpegBuild has ..."), not a working integration. The
[original proposal](../archive/2026-05-aether-engine-proposal/AetherEngine.md) for history — treat everything in it
as a proposal that didn't ship, not a description of current architecture.
