The goal:
I want to update how we are managing our user access tokens for a Spotify API integration in my Elixir/Phoenix application.

Background:
- We are using the Spotify API to authenticate users and perform actions on their behalf. The auth token lasts for 1 hour and can be refreshed.
- I would like to come up with a solution that allows me to track user tokens and auto-refresh them before expiration.
- This is an MVP for a side project, so scale is not a primary concern at this stage.

Requirements and restrictions:
- No database storage - everything should be in-memory with the GenServer
- We can bring in new dependencies if needed
- We are working with user access tokens so this needs to be secure
- Everything should have tests (success, error cases, edge cases) using TDD and outside-in testing approach

My proposed solution is to:
- Have a GenServer that stores each user's auth data (one GenServer per user)
- Manage these GenServers with DynamicSupervisor and Registry
- The GenServer will handle automatically attempting to refresh the token before expiration using `expires_in` from the token response. Example response:
  ```json
  {
   "access_token": "NgCXRK...MzYjw",
   "token_type": "Bearer",
   "scope": "user-read-private user-read-email",
   "expires_in": 3600,
   "refresh_token": "NgAagA...Um_SHo"
  }
  ```

Store the user's ID in the session for lookup
For application restart recovery: store the refresh token encrypted in the user's session/cookies using Phoenix.Token for encryption
On user authentication, if no GenServer exists for that user, check for a refresh token in the session and use it to recreate the GenServer state
If token refresh fails or user revokes access on Spotify's side, terminate the process and treat the user as logged out

Error handling:

Failed token refreshes should kill the process
The system should handle the case where a user revokes access from Spotify by terminating the GenServer

Please design this solution with the existing codebase in mind, which you can explore. Focus on implementing a secure in-memory token management system that can survive application restarts through encrypted session storage.

## Implementation Progress

### Completed
- Created token exchange functionality in Spotify.API module
- Extracted OAuth code exchange logic from OAuthCallbackController to Spotify.API.exchange_code/2
- Updated controller to use the new API function with proper error handling
- Fixed tests to use proper mocking with Hammox
- Improved session handling and error management
- Fixed the skipped test "sign out stops token process" by properly verifying the original process is stopped
- Improved test to account for the RestoreSpotifyToken plug behavior that creates a new process after sign-out
- Enhanced sign-out functionality to clear refresh tokens from the session, preventing token restoration on subsequent requests
- Improved test robustness with Registry lookup helper:
  - Created wait_for_registry helper to handle race conditions in tests
  - Updated tests to use unique user IDs to prevent test interference
  - Added proper cross-process mocking with Hammox's allow function
  - Fixed flaky tests related to Registry lookup timing issues
- Enhanced test organization and structure:
  - Renamed helper to assert_in_registry to follow ExUnit assertion pattern
  - Created dedicated Setlistify.Test.RegistryHelpers module for test utilities
  - Moved unique_user_id helper to the RegistryHelpers module
  - Updated ConnCase and DataCase to automatically import registry helpers
  - Improved error messages for registry lookups in tests
- Optimized logout session handling:
  - Identified and removed redundant refresh token deletion in UserAuth.log_out_user
  - Verified clear_session() in renew_session already removes all session data
  - Ensured tests confirm proper session clearing behavior

## Architecture Notes

- OAuthCallbackController now uses Spotify.API.exchange_code/2 for the initial OAuth code exchange
- TokenManager uses Spotify.API.refresh_token/1 for refreshing expired tokens
- Both follow the same pattern of extracting API communication to the API module
- Tests use Hammox for mocking API responses

## Next Steps

- Update the login indicator in the layout to show when a user is logged in
- Store `user_id` instead of `username` for working with the client
- Investigate if we can store the `username` in the session as a way to avoid having to make extra calls to `/me`
- Enhance Spotify.API.ExternalClient to track the user_id with the client:
  - Create a client struct that includes both the Req client and user_id
  - Options to consider:
    - Wrap the Req client in a struct: `%Setlistify.Spotify.Client{req: req_client, user_id: user_id}`
    - Use process dictionary (less preferred, but simpler short-term)
    - Add metadata to Req client options (would need to check if Req retains this)
  - Update all API functions to extract user_id from the enhanced client
  - This will eliminate the need for extra API calls to `/me` when refreshing tokens on 401 responses