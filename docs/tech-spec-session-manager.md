# Technical Specification: Extending TokenManager for User Data Management

## Overview
This document outlines the plan to extend the TokenManager GenServer to store and manage user data alongside token information, reducing API calls and improving authentication consistency.

## Summary of Implementation
The SessionManager refactoring has been successfully completed, transforming the authentication system from a simple token storage mechanism to a comprehensive user session management system. Key achievements include:

- Created a UserSession struct to encapsulate all user data
- Renamed TokenManager to SessionManager to reflect broader responsibilities
- Eliminated redundant API calls by caching user profile data
- Improved type safety by using UserSession throughout the codebase
- Enhanced error handling and session expiration flows
- Maintained backward compatibility during migration

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

### 3. Update Session Storage ✅ COMPLETED
- ✅ Minimal session: only `user_id` and encrypted `refresh_token`
- ✅ Remove redundant `username` and `access_token` from session
- ✅ Use `user_id` as primary identifier throughout
- ✅ Cleaned up legacy session keys (removed "user" key)

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

### 6. Error Handling ✅ COMPLETED

- ✅ Invalid refresh token: Clear session without redirecting, show flash message
- ✅ User profile fetch failure: Log error, return error to caller
- ✅ SessionManager crash: Supervisor restarts, session provides recovery
- ✅ Token expiration during API calls: Automatically refresh and retry

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
6. Remove redundant session data once all components updated ✅ COMPLETED
   - Cleaned up legacy "user" session key from sign_out function

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

5. **Enhanced Error Recovery**
   - Retry logic for transient API failures
   - Automatic fallback to cached data when API is unavailable
   - Better error messages for different failure scenarios

6. **Performance Optimizations**
   - Connection pooling for Spotify API requests
   - Request batching for multiple track searches
   - Cache warming strategies for popular content

## Implementation Timeline

1. Phase 1: Create UserSession struct (0.5 day) ✅ COMPLETED
2. Phase 2: Rename and update SessionManager (1 day) ✅ COMPLETED
3. Phase 3: Modify OAuth flow (1 day) ✅ COMPLETED
4. Phase 4: Update session restoration (1 day) ✅ COMPLETED
5. Phase 5: Migrate UI components (2 days) ✅ COMPLETED
6. Phase 6: Testing and cleanup (1 day) ✅ COMPLETED

## Remaining Work

1. **Extract Token Refresh Helper** - Refactor token refresh and retry logic into a reusable helper function ✅ COMPLETED
2. **Protected Routes** - Add auth requirement hook/plug for pages that require authentication, as some pages may need to redirect when user_session is nil instead of rendering without auth
3. **Documentation** - Update README with new authentication flow
4. **Rename refresh_token to refresh_session** - Update SessionManager.refresh_token to be refresh_session and return the UserSession instead of just the access token

### Token Refresh Helper Specification

#### Problem
The `search_for_track` function contains token refresh and retry logic that should be available to other API functions. Currently, functions like `create_playlist` and `add_tracks_to_playlist` don't handle token expiration gracefully.

#### Solution
Extract a helper function `with_token_refresh/2` that:
- Accepts a `UserSession` and a request function
- Handles 401 responses with "invalid_token" in the www-authenticate header
- Refreshes the token through SessionManager
- Retries the request once with the new session
- Returns consistent error tuples

#### Implementation Details

```elixir
defp with_token_refresh(user_session, request_fn) do
  req = client(user_session)
  
  case request_fn.(req) do
    {:ok, %{status: 401} = response} ->
      # Check if this is a token expiration issue
      authenticate_header =
        Enum.find_value(response.headers, fn {header, value} ->
          if String.downcase(header) == "www-authenticate", do: value
        end)

      if authenticate_header && String.contains?(authenticate_header, "invalid_token") do
        Logger.info(
          "Token expired, attempting to refresh for user_id: #{user_session.user_id}"
        )

        # Attempt to refresh the token
        case Setlistify.Spotify.SessionManager.refresh_token(user_session.user_id) do
          {:ok, _new_token} ->
            Logger.info("Successfully refreshed token, retrying request")
            # Get the new session and retry ONCE
            case Setlistify.Spotify.SessionManager.get_session(user_session.user_id) do
              {:ok, new_session} -> 
                # Create new client and retry the request
                new_req = client(new_session)
                request_fn.(new_req)
              
              _ -> 
                {:error, :session_refresh_failed}
            end

          {:error, reason} ->
            Logger.error(
              "Failed to refresh token for user_id #{user_session.user_id}: #{inspect(reason)}"
            )
            {:error, :token_refresh_failed}
        end
      else
        # Non-token 401 error, just pass it through
        {:ok, response}
      end
    
    # Any other response passes through unchanged
    other -> other
  end
end
```

#### Functions to Update

1. **`search_for_track`** - Refactor to use the helper
2. **`create_playlist`** - Convert from `Req.post!` to `Req.post` and use the helper
3. **`add_tracks_to_playlist`** - Convert from `Req.post!` to `Req.post` and use the helper

#### API Changes

- Replace bang functions (`!`) with regular functions that return error tuples
- Maintain backward compatibility by updating callers to handle the new return values
- Consistent error types: `{:error, :token_refresh_failed}`, `{:error, :session_refresh_failed}`

#### Benefits

1. **DRY Principle** - Single implementation of token refresh logic
2. **Consistent Error Handling** - All API functions handle 401s the same way
3. **Improved Reliability** - All functions can recover from expired tokens
4. **No Recursion Risk** - Helper only retries once after refresh
5. **Better Error Types** - Move away from exceptions to explicit error tuples

#### Testing Requirements

- Test successful token refresh and retry
- Test failed token refresh
- Test non-token 401 responses
- Test preservation of original response for non-401 errors
- Update existing tests for functions converting from bang to regular

### Rename refresh_token to refresh_session Specification

#### Problem
The current `SessionManager.refresh_token/1` function is misleadingly named and returns only the access token. Since we now manage full user sessions with the UserSession struct, the function should reflect this and return the complete refreshed session.

#### Solution
Rename `refresh_token` to `refresh_session` and update it to return the full UserSession:
- Function remains public for direct session refresh needs
- Returns `{:ok, %UserSession{}}` instead of `{:ok, access_token}`
- Maintains backward compatibility by keeping internal token refresh logic

#### Implementation Details

```elixir
# Current API
def refresh_token(user_id) do
  # Returns {:ok, access_token} or {:error, reason}
end

# New API
def refresh_session(user_id) do
  # Returns {:ok, %UserSession{}} or {:error, reason}
end
```

#### Migration Steps
1. Add new `refresh_session/1` function
2. Update internal `do_refresh_token` to support both return types
3. Update all callers to use `refresh_session`
4. Mark `refresh_token` as deprecated
5. Remove `refresh_token` in next major version

#### Benefits
- More accurate function naming
- Returns complete session data
- Aligns with UserSession-centric architecture
- Enables callers to get fresh session without additional `get_session` call

### PubSub Broadcasting Specification

#### Problem
When tokens are refreshed in the background by SessionManager, LiveView components maintain stale UserSession data in their socket assigns. This leads to potential authentication failures and inconsistent UI state.

#### Solution
Implement Phoenix PubSub broadcasting to notify LiveViews when tokens are refreshed:
- SessionManager broadcasts token refresh events on user-specific channels
- LiveViews subscribe to their user's channel on mount
- Default handle_info callback updates socket assigns with fresh session data

#### Implementation Details

1. **SessionManager Broadcasting** ✅ COMPLETED
```elixir
defp broadcast_token_refreshed(state) do
  user_session = %UserSession{
    access_token: state.access_token,
    refresh_token: state.refresh_token,
    expires_at: state.expires_at,
    user_id: state.user_id,
    username: Map.get(state, :username, state.user_id)
  }

  Phoenix.PubSub.broadcast(
    Setlistify.PubSub,
    "user:#{state.user_id}",
    {:token_refreshed, user_session}
  )
end
```

2. **LiveView Subscription** ✅ COMPLETED
```elixir
def on_mount(:default, _params, session, socket) do
  with {:ok, user_id} <- Map.fetch(session, "user_id"),
       {:ok, user_session} <- SessionManager.get_session(user_id) do
    # Subscribe to token refresh events for this user
    Phoenix.PubSub.subscribe(Setlistify.PubSub, "user:#{user_id}")
    # ... rest of mount logic
  end
end
```

3. **LiveView Update Handler** ✅ COMPLETED
```elixir
def handle_info({:token_refreshed, new_session}, socket) do
  {:noreply, Phoenix.Component.assign(socket, :user_session, new_session)}
end
```

#### Benefits
- Real-time session synchronization across all LiveView components
- No manual session refresh required in LiveViews
- User-specific channels ensure privacy and efficiency
- Seamless token rotation without UI disruption

#### Testing
- Verified broadcasts are received by correct user
- Confirmed users don't receive other users' broadcasts
- Tested multi-user scenarios with isolated channels

## Completed Work

1. ✅ **Clean up session storage** - Removed old `access_token` and `account_name` from auth_user
2. ✅ **Session expiration handling** - Improved to clear session but continue request flow
3. ✅ **Update Spotify.API function signatures** - Changed to accept UserSession instead of client
4. ✅ **Remove legacy session keys** - Cleaned up "user" session key from sign_out function
5. ✅ **Fix redirect handling** - Preserve redirect_to through OAuth flow correctly
6. ✅ **Extract Token Refresh Helper** - Implemented with_token_refresh helper with contextual logging
7. ✅ **PubSub Broadcasting for Token Refresh** - Implemented real-time LiveView updates when tokens refresh

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
5. **Non-disruptive session expiration** - Clear session without redirecting when tokens expire, letting UI handle state gracefully
6. **API consistency** - Refactored Spotify.API to use UserSession consistently instead of raw client objects