> Status: archived — classified from code on 2026-10-15.
> Do not submit this text for review. Its no-storage/no-sharing statements conflict with TokenManager, local stores and network APIs. Use the privacy policy; OQ-0012 tracks replacement.
> Current references: [architecture](../architecture.md), [open questions](../OPEN_QUESTIONS.md).

# Reviewer Notes

## Login / Account

- Sign-in with Google is the only supported login method. This is intentional — the app requires it to access the user's personal YouTube data such as subscriptions, watch history, and playlists.
- The app does not track users or collect any account information.
- No personal data is stored or shared. The Google account is used solely to authenticate with YouTube's API for the purpose of browsing and playback.
