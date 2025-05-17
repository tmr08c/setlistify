# Architecture Decision Record: SessionManager Implementation

**Title**: Spotify Token Management System with In-Memory Session Storage
**Status**: Implemented
**Date**: 2025-05-12
**Decision Makers**: Troy (Project Lead)

## Context and Problem Statement

We need to update how we manage user access tokens for a Spotify API integration in our Elixir/Phoenix application. The current system has the following issues:
- Token expiration handling is manual and error-prone
- Multiple redundant API calls to identify users
- No automated token refresh mechanism
- Poor session recovery after application restarts

### Constraints
- No database storage - everything must be in-memory with GenServer
- Must be secure for user access tokens
- Scale is not a primary concern (MVP for side project)
- Must follow TDD and outside-in testing approach

## Decision Drivers

1. **Security**: User tokens must be handled securely
2. **Reliability**: System must survive application restarts
3. **Efficiency**: Minimize redundant API calls to Spotify
4. **Maintainability**: Clean separation of concerns
5. **User Experience**: Seamless authentication without interruptions

## Considered Options

### Option 1: Simple Token Storage
Store only access tokens in a basic GenServer with manual refresh

**Pros**:
- Simple implementation
- Minimal memory usage

**Cons**:
- Requires repeated API calls for user identification
- No automatic token refresh
- Poor error recovery

### Option 2: Comprehensive Session Management
Create a SessionManager that stores complete user sessions with automatic refresh

**Pros**:
- Single source of truth for user data
- Automatic token refresh
- Reduced API calls
- Better type safety with UserSession struct

**Cons**:
- More complex implementation
- Slightly larger memory footprint

## Decision

We will implement **Option 2: Comprehensive Session Management** with the following architecture:

1. **SessionManager GenServer** (one per user)
   - Stores complete UserSession struct
   - Automatically refreshes tokens before expiration
   - Broadcasts updates via PubSub

2. **DynamicSupervisor and Registry**
   - Manages SessionManager processes
   - Enables process lookup by user ID

3. **Encrypted Session Storage**
   - Stores encrypted refresh token in Phoenix session
   - Enables recovery after application restarts

4. **UserSession Struct**
   ```elixir
   defstruct [:access_token, :refresh_token, :expires_at, :user_id, :username]
   ```

## Implementation Details

### Architecture Components

```
lib/setlistify/
├── spotify/
│   ├── session_manager.ex       # GenServer for token management
│   ├── session_supervisor.ex    # DynamicSupervisor for sessions
│   ├── user_session.ex          # Struct for session data
│   └── api/
│       └── external_client.ex   # Spotify API client
└── setlistify_web/
    ├── controllers/
    │   └── user_auth.ex         # HTTP authentication
    └── auth/
        └── live_hooks.ex        # LiveView authentication
```

### Authentication Flow

1. **Initial OAuth**
   - Exchange authorization code for tokens
   - Fetch user profile from Spotify
   - Create UserSession struct
   - Start SessionManager process
   - Store encrypted refresh token in session

2. **Session Restoration**
   - Extract user_id and refresh_token from session
   - Refresh token if expired
   - Fetch user profile
   - Recreate SessionManager process

3. **LiveView Integration**
   - Subscribe to PubSub updates
   - Store UserSession in socket assigns
   - Automatic updates when tokens refresh

### Key Technical Decisions

1. **Use UserSession struct** instead of raw tokens for type safety
2. **Store minimal data in Phoenix session** (only user_id and encrypted refresh_token)
3. **Implement PubSub broadcasting** for real-time LiveView updates
4. **Use string keys in session** for Phoenix compatibility
5. **Non-disruptive session expiration** - clear session without redirecting
6. **Protected routes** with authentication plugs and LiveView hooks

## Consequences

### Positive
- ✅ Eliminated redundant API calls for user identification
- ✅ Automatic token refresh prevents authentication failures
- ✅ Type-safe session management with UserSession struct
- ✅ Seamless user experience across application restarts
- ✅ Real-time session updates in LiveView components
- ✅ Clear separation of concerns between auth layers

### Negative
- ❌ Increased complexity in session management
- ❌ Slightly larger memory footprint per user
- ❌ Requires careful testing of edge cases

### Neutral
- Session data can become stale if user updates profile on Spotify
- Future work needed for multi-provider support

## Implementation Status

### Completed
- SessionManager GenServer implementation
- UserSession struct creation
- OAuth flow integration
- Session restoration mechanism
- LiveView authentication hooks
- Protected route implementation
- PubSub broadcasting for token refresh
- Comprehensive test coverage

### Remaining Work
- Simplify socket assigns (remove duplicate user_id)
- Implement stale user data handling
- Add session analytics

## Success Metrics

- ✅ No additional API calls for user identification
- ✅ Consistent use of Spotify ID throughout application
- ✅ All tests passing with new structure
- ✅ Smooth user experience across app restarts
- ✅ Clear migration path with backward compatibility

## Future Considerations

1. **Enhanced User Profile Management**
   - Periodic profile refresh
   - Additional user fields (email, avatar, etc.)
   - Webhook support for profile updates

2. **Performance Optimizations**
   - Connection pooling for API requests
   - Request batching for track searches
   - Cache warming strategies

3. **Multi-Provider Support**
   - Abstract session management interface
   - Support for other music services
   - Provider-agnostic session handling

4. **Advanced Error Recovery**
   - Retry logic for transient failures
   - Fallback to cached data
   - Better error messaging

## References

- [Phoenix Session Documentation](https://hexdocs.pm/phoenix/Phoenix.Controller.html#module-session)
- [GenServer Documentation](https://hexdocs.pm/elixir/GenServer.html)
- [Spotify Web API Documentation](https://developer.spotify.com/documentation/web-api/)
- [Architecture Decision Records](https://adr.github.io/)

## Appendix: Risk Analysis

| Risk | Impact | Likelihood | Mitigation | Status |
|------|--------|------------|------------|--------|
| Complex session state management | Medium | High | Clear struct definition and type specs | ✅ Resolved |
| Breaking changes for existing code | High | Medium | Backward-compatible interface | ✅ Resolved |
| Larger memory footprint | Low | High | Store only essential fields | ✅ Resolved |
| Testing complexity | Medium | High | Comprehensive test helpers | ✅ Resolved |
