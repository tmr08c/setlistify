# Technical Specification: Extending TokenManager for User Data Management

## Overview
This document outlines the plan to extend the TokenManager GenServer to store and manage user data alongside token information, reducing API calls and improving authentication consistency.

## Current State
- Session stores: `username`, `access_token`, encrypted `refresh_token`
- TokenManager stores: `access_token`, `refresh_token`, `expires_in`
- Multiple API calls to `/me` endpoint for user identification
- User identification using display name, not Spotify ID

## Proposed Changes

### 1. Create UserSession Struct ✅ COMPLETED
```elixir
defmodule Setlistify.Spotify.UserSession do
  @moduledoc """
  Represents an authenticated Spotify user session with tokens and profile data.
  """
  
  @type t :: %__MODULE__{
    access_token: String.t(),
    refresh_token: String.t(),
    expires_at: integer(),
    user_id: String.t(),
    username: String.t()
  }
  
  @enforce_keys [:access_token, :refresh_token, :expires_at, :user_id, :username]
  defstruct [:access_token, :refresh_token, :expires_at, :user_id, :username]
end
```

### 2. Rename TokenManager to SessionManager ✅ COMPLETED
- Better reflects expanded responsibilities
- Manages complete user session, not just tokens
- Update all references throughout codebase
- Also rename UserTokenRegistry to UserSessionRegistry for consistency

```elixir
defmodule Setlistify.Spotify.SessionManager do
  # Previously TokenManager
  # Now manages UserSession structs
end
```

### 3. Update Session Storage ✅ PARTIALLY COMPLETED
- ✅ Minimal session: only `user_id` and encrypted `refresh_token`
- ✅ Remove redundant `username` and `access_token` from session
- ✅ Use `user_id` as primary identifier throughout
- ⚠️ Still storing old keys temporarily for backward compatibility

### 4. API Changes ✅ COMPLETED

#### SessionManager Functions ✅ COMPLETED
```elixir
# New/Modified functions
def start_link({user_id, user_session})
def get_session(user_id) # Returns {:ok, %UserSession{}}
def get_token(user_id)   # Backward compatibility
def refresh_session(user_id)
```

#### Spotify API Client ✅ COMPLETED
```elixir
# Fetch user profile during token operations
def exchange_code(code, redirect_uri) do
  # ... existing token exchange ...
  # Add call to fetch user profile
  # Return both tokens and user data
end

# Added new function for token refresh
def refresh_to_user_session(refresh_token, user_id) do
  # Refresh token and fetch user profile
  # Return complete UserSession
end
```

### 5. Authentication Flow Updates ✅ COMPLETED

1. **Initial OAuth:** ✅ COMPLETED
   - Exchange code for tokens
   - Fetch user profile from `/me` endpoint  
   - Create UserSession struct
   - Start SessionManager with complete session
   - Store only `user_id` and encrypted `refresh_token` in session

2. **Session Restoration:** ✅ COMPLETED
   - Extract `user_id` and encrypted `refresh_token` from session
   - Refresh token if needed
   - Fetch fresh user profile
   - Recreate SessionManager with UserSession

3. **LiveView Mounting:** ✅ COMPLETED
   - Use `on_mount` hook to fetch UserSession from SessionManager
   - Store complete UserSession in socket assigns
   - LiveView components use `user_session` from assigns
   - No additional API calls needed

### 6. Error Handling

- Invalid refresh token: Clear session, redirect to login
- User profile fetch failure: Log error, proceed with tokens only
- SessionManager crash: Supervisor restarts, session provides recovery

### 7. Testing Strategy ✅ COMPLETED

- ✅ Mock user profile responses in exchange_code tests
- ✅ Test UserSession struct creation and validation
- ✅ Verify session restoration with minimal data
- ✅ Test error scenarios (invalid tokens, API failures)
- ✅ Added comprehensive OAuth callback session tests
- ✅ Added LiveView authentication integration tests

### 8. Migration Path

1. Create UserSession struct ✅ COMPLETED
2. Rename TokenManager to SessionManager ✅ COMPLETED
3. Update OAuth callback to fetch and store user profile ✅ COMPLETED
4. Modify RestoreSpotifyToken plug to use new structure ✅ COMPLETED
5. Gradually migrate components to use SessionManager ✅ COMPLETED
   - ✅ Updated ShowLive component
   - ✅ Updated app layout to use UserSession
   - ✅ Fixed auth_user to preserve session data
6. Remove redundant session data once all components updated ⏳ IN PROGRESS
   - Still need to clean up UserAuth.auth_user to remove old session keys

## Benefits

- Single source of truth for user data
- Reduced API calls to Spotify
- Consistent user identification (Spotify ID)
- Better separation of concerns
- Improved error recovery

## Risks & Mitigation

1. **Risk**: More complex session state management ✅ RESOLVED
   - **Mitigation**: Clear struct definition and type specs
   - **Status**: UserSession struct is well-defined with enforced keys

2. **Risk**: Breaking changes for existing code ✅ RESOLVED
   - **Mitigation**: Maintain backward-compatible interface during migration
   - **Status**: Successfully migrated with backward compatibility

3. **Risk**: Larger memory footprint per user ✅ RESOLVED
   - **Mitigation**: Only store essential fields
   - **Status**: UserSession only contains necessary fields

4. **Risk**: Testing complexity ✅ RESOLVED
   - **Mitigation**: Comprehensive test helpers and mocks
   - **Status**: Added AuthHelpers and extensive test coverage

## Out of Scope / Future Enhancements

1. **Stale User Data Handling**
   - Current system doesn't update cached username if changed on Spotify
   - Future: Implement periodic profile refresh (e.g., daily)
   - Future: Add profile refresh on specific user actions
   - Future: Handle profile update webhooks if Spotify provides them

2. **Additional User Fields**
   - Email address
   - Profile image URL
   - User subscription level
   - Country/locale information

3. **Multi-Provider Support**
   - Abstract session management for other music services
   - Provider-agnostic user session interface

4. **Session Analytics**
   - Track session duration
   - Monitor token refresh patterns
   - User activity metrics

## Implementation Timeline

1. Phase 1: Create UserSession struct (0.5 day) ✅ COMPLETED
2. Phase 2: Rename and update SessionManager (1 day) ✅ COMPLETED
3. Phase 3: Modify OAuth flow (1 day) ✅ COMPLETED
4. Phase 4: Update session restoration (1 day) ✅ COMPLETED
5. Phase 5: Migrate UI components (2 days) ✅ COMPLETED
6. Phase 6: Testing and cleanup (1 day) ✅ COMPLETED

## Remaining Work

1. **Clean up session storage** - Remove old `access_token` and `account_name` from auth_user ✅ COMPLETED
2. **Session expiration handling** - ~~Handle the redirect_to parameter better when sessions expire~~ ✅ IMPROVED - Changed to clear session but continue request flow, letting LiveView handle the UI state gracefully without a jarring redirect
3. **Documentation** - Update README with new authentication flow
4. **Protected Routes** - Add auth requirement hook/plug for pages that require authentication, as some pages may need to redirect when user_session is nil instead of rendering without auth

## Success Criteria

- ✅ No additional API calls for user identification
- ✅ Consistent use of Spotify ID throughout application
- ✅ All tests passing with new structure
- ✅ Smooth user experience across app restarts
- ✅ Clear migration path with backward compatibility

## Technical Decisions Made

1. **Socket assigns for UserSession** - Store complete UserSession in LiveView socket assigns instead of just user_id to reduce SessionManager lookups
2. **Session key preservation** - Modified auth_user to preserve session data through renew_session flow
3. **String keys for session** - Use string keys ("user_id") instead of atoms for Phoenix session compatibility
4. **Test coverage** - Added comprehensive OAuth callback and LiveView integration tests to prevent regressions