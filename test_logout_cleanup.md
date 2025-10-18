# Logout Cleanup Test Plan

## What We Implemented

### 1. Enhanced ChatService
- **clearCache()**: Clears all chat data including:
  - `_chats` map
  - `_chatMessages` map  
  - `_hasLoadInitialMessages` map
  - `_activeChatScreens` set
  - Resets `_isInitialized` to false
  - Notifies listeners with empty data

- **logoutCleanup()**: Consolidated method that:
  - Calls `clearCache()`
  - Disconnects WebSocket via `WebSocketService().disconnect()`

### 2. Updated Logout Handlers
- **LogoutEvent**: Uses `ChatService().logoutCleanup()`
- **Settings Widget**: Uses `ChatService().logoutCleanup()`

## How to Test

### Test Scenario 1: Manual Logout via Settings
1. Login with User A
2. Have some chat conversations
3. Go to Settings → Logout
4. Login with User B
5. **Expected**: No chats from User A should appear

### Test Scenario 2: Auto Logout (if token expires)
1. Login with User A  
2. Have some chat conversations
3. Let token expire or force logout via LogoutEvent
4. Login with User B
5. **Expected**: No chats from User A should appear

### Test Scenario 3: WebSocket Cleanup
1. Login and start a chat (WebSocket connected)
2. Logout
3. Check that WebSocket is properly disconnected
4. Login with different user
5. **Expected**: New WebSocket connection, no old messages

## Debug Output
When logout happens, you should see these console logs:
```
✅ ChatService cache cleared
✅ WebSocket disconnected  
✅ ChatService logout cleanup completed
```

## What This Prevents
- Previous user's chat list appearing for new user
- Mixed messages between different user sessions
- WebSocket receiving messages for wrong user
- Memory leaks from cached chat data
- Authentication confusion between user sessions

## Files Modified
- `/lib/app/services/chat_service.dart` - Added clearCache() and logoutCleanup()
- `/lib/app/events/logout_event.dart` - Uses logoutCleanup()
- `/lib/resources/widgets/settings_tab_widget.dart` - Uses logoutCleanup()