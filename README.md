# Sugar Beat iOS App

SwiftUI-based iOS client for Sugar Beat music social network.

## Features

- **Feed View**: Horizontal swipe through mutual follows' music posts
- **User Posts**: Vertical swipe to see a user's past posts
- **User Search**: Search and discover new users
- **Follow/Unfollow**: Simple follow interactions
- **Profile View**: View user profiles and their posts

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Open the project in Xcode
2. Update the API base URL in `APIClient.swift` if needed (default: `http://localhost:8080/api`)
3. Build and run on simulator or device

## Project Structure

```
SugarBeat/
├── Models/           # Data models (User, Post, etc.)
├── Services/         # API client and networking
├── ViewModels/       # View models for business logic
├── Views/            # SwiftUI views
└── SugarBeatApp.swift  # App entry point
```

## Apple Music Integration

The app uses Apple Music API to:
- Display track information
- Show album artwork
- Play 30-second preview clips
- Link to full tracks in Apple Music

See the Apple Music API setup guide for configuration details.

## TODO

- [ ] Implement Apple MusicKit integration for playback
- [ ] Add JWT authentication
- [ ] Implement post creation flow with music search
- [ ] Add block and report functionality
- [ ] Implement proper error handling and loading states
- [ ] Add animations and transitions
- [ ] Implement pull-to-refresh
- [ ] Add pagination for user posts
- [ ] Implement deep linking
- [ ] Add push notifications

## License

MIT
