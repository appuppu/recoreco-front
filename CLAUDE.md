# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SugarBeat is a music social network iOS app built with SwiftUI. Users can share music posts (Apple Music tracks, YouTube videos, or website links), follow other users, and interact through likes and comments. The app uses Firebase for backend services (Firestore, Auth, Storage) and supports Apple Music integration via MusicKit.

## Development Setup

### Initial Setup
```bash
# Install CocoaPods dependencies (required after cloning)
pod install

# Always open the workspace, not the project file
open SugarBeat.xcworkspace
```

### Building & Running
- **IMPORTANT**: NEVER run `xcodebuild` commands as they take too long (3+ minutes)
- Always use Xcode GUI for building and running (CMD+R in Xcode)
- Main scheme: `SugarBeat`
- Always use the `.xcworkspace` file, not `.xcodeproj`

## Architecture

### Data Flow: Backend Migration Status
**CRITICAL**: This app is currently migrated from a REST API backend to Firebase/Firestore:
- Authentication: Uses Firebase Auth with Google Sign-In and Apple Sign-In
- Data storage: Uses Firestore for all user data, posts, comments, likes, follows, etc.
- **Legacy APIClient.swift remains but is mostly unused** - Firestore managers handle all CRUD operations
- The app can run with or without authentication (discovery feed is public)

### Core Architecture Patterns

#### 1. MVVM with SwiftUI
- **Views** (`SugarBeat/Views/`): SwiftUI views for UI
- **ViewModels** (`SugarBeat/ViewModels/`): Business logic and state management (e.g., `FeedViewModel`, `CreatePostViewModel`, `UserProfileViewModel`)
- **Models** (`SugarBeat/Models/`): Data models (`User`, `Post`, `Comment`, `Notification`)

#### 2. Service Layer - Firestore Managers
All backend operations go through dedicated Firestore managers in `SugarBeat/Services/`:
- **FirestoreUserManager**: User CRUD operations, profile updates, post counts
- **FirestorePostManager**: Post creation, retrieval, deletion, feed queries
- **FirestoreCommentManager**: Comment CRUD with real-time listeners
- **FirestoreLikeManager**: Like/unlike operations
- **FirestoreFollowManager**: Follow/unfollow, follower/following lists
- **FirestoreBlockManager**: User blocking functionality
- **FirestoreNotificationManager**: Notification creation and management
- **FirestoreChannelManager**: Channel (feed grouping) operations
- **FirestoreListenerManager**: Centralized real-time listener management
- **FirestoreCacheManager**: Client-side caching for performance

**Pattern**: These managers are singletons accessed via `.shared` and handle all Firestore queries, including:
- Batch operations to avoid N+1 queries
- Real-time listeners for live updates
- Error handling with custom error enums
- Authentication checks before mutations

#### 3. Global State Managers
Located in `SugarBeat/Services/`:
- **AuthManager** (`@MainActor`, `ObservableObject`): Authentication state, login/logout, Google/Apple Sign-In
- **MusicKitManager**: Apple Music authorization, search, preview playback
- **PlaybackStateManager**: Global music playback coordination (ensures only one track plays at a time)
- **LikeStateManager**: Optimistic UI updates for likes across all views
- **CommentStateManager**: Comment count management
- **UnreadPostsManager**: Track unread posts per user
- **FeedAdManager**: Google AdMob native ad management

#### 4. Firebase Integration
- **FirebaseConfig** (`SugarBeat/Utils/`): Environment-based Firebase configuration (dev/prod)
- Firebase is initialized in `AuthManager.init()` before any Firebase calls
- Uses `@DocumentID` for Firestore document IDs in models
- All models conform to `Codable` for Firestore encoding/decoding

### Key Architectural Decisions

1. **User Data Denormalization**: User info (username, displayName, profileImageUrl) is fetched dynamically rather than stored in posts/comments to ensure consistency

2. **Optimistic UI Updates**: Like and comment actions update UI immediately, then sync with Firestore. Rollback on failure.

3. **Real-time Updates**:
   - Comments use Firestore listeners for live updates
   - Feed uses polling (30s interval) for new posts
   - Notifications checked periodically

4. **Feed Architecture**:
   - `FeedView`: Horizontal swipe through users (each user = one page)
   - `UserPostsView`: Vertical swipe through a user's posts
   - `DiscoveryView`: Public feed of all posts (no auth required)
   - `FollowingFeedView`: Authenticated user's following feed

5. **Content Types**: Posts support three content types:
   - `music`: Apple Music tracks with preview playback
   - `youtube`: YouTube videos (embedded player)
   - `website`: External links

6. **Deep Linking**: Universal Links for profile sharing via `DeepLinkManager`
   - Format: `https://appuppu.github.io/docs/profile/{username}`

## Environment Configuration

### API Environment Switching
In `APIClient.swift:67`:
```swift
private let environment: Environment = .prod  // Change to .dev for local development
```

### Firebase Configuration
Uses two Firebase projects:
- Dev: `GoogleService-Info-Dev.plist`
- Prod: `GoogleService-Info-Prod.plist`

Switched via `FirebaseConfig.swift` based on build configuration.

### AdMob Test Mode
In `APIClient.swift:64`:
```swift
static let isTestMode = false  // Set to true for AdMob test ads
```

## File Organization

```
SugarBeat/
├── SugarBeatApp.swift          # App entry point, Firebase/AdMob initialization
├── Models/                      # Data models (Codable, Identifiable)
├── Views/                       # SwiftUI views
├── ViewModels/                  # MVVM view models
├── Services/                    # Firestore managers, AuthManager, APIClient
│   ├── Firestore*Manager.swift  # Firestore CRUD operations
│   ├── AuthManager.swift        # Authentication
│   ├── MusicKitManager.swift    # Apple Music
│   └── *StateManager.swift      # Global state
├── Managers/                    # DeepLinkManager
├── Utils/                       # Helpers (AppTheme, FirebaseConfig, YouTubeUtils)
└── Assets.xcassets/             # Images, colors
```

## Common Development Tasks

### Adding a New Firestore Collection
1. Create a model in `Models/` conforming to `Codable` and `Identifiable`
2. Use `@DocumentID var id: String?` for the document ID
3. Create a `Firestore*Manager` in `Services/` following existing patterns
4. Add collection name as private constant
5. Implement CRUD methods with proper error handling

### Modifying Feed Logic
- Feed loading: `FeedViewModel.swift:54-137`
- Polling for new posts: `FeedViewModel.swift:144-263`
- Feed UI: `FeedView.swift` and `FollowingFeedView.swift`

### Adding Authentication Providers
- Extend `AuthManager.swift` with new sign-in methods
- Update `LoginView.swift` and `SignUpView.swift` with UI buttons
- Add URL schemes to Info.plist for OAuth providers

### Working with MusicKit
- Search: `MusicKitManager.searchMusic(query:limit:)`
- Preview playback: `MusicKitManager.playPreviewFromURL(_:startTime:)`
- Authorization: Automatically requested on first use
- Global playback coordination: Use `PlaybackStateManager.shared`

## Important Constraints

1. **iOS 16.0+ minimum deployment target**
2. **MusicKit requires user authorization** - requested on app launch for authenticated users
3. **Firebase must be configured before Auth access** - handled in `AuthManager.init()`
4. **AdMob requires App Tracking Transparency** - requested in `SugarBeatApp.swift`
5. **User IDs are Firebase Auth UIDs (String)** - not numeric IDs
6. **All Firestore operations should use managers** - avoid direct Firestore calls in views/viewmodels
7. **Main actor isolation** - Most view models and managers use `@MainActor`

## Testing Notes

- Use `#DEBUG` flag for debug-only code (e.g., AdMob test device IDs)
- Firebase has separate dev/prod projects for safe testing
- APIClient has dev/prod environment switching
- Always test with real devices for MusicKit and push notifications

## Related Documentation

- `FIREBASE_SETUP.md`: Firebase configuration and Google/Apple Sign-In setup
- `XCODE_SETUP.md`: Xcode project setup instructions
- `UNIVERSAL_LINKS_SETUP.md`: Deep linking configuration
- `README.md`: High-level project overview
