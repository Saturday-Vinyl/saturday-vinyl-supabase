We are working on a consumer-facing flutter app for ios and android that is used to manage a user's vinyl record collection and connect to an ecosystem of embedded devices built by our company, Saturday. Take a look at @docs/DEVELOPERS_GUIDE.md for more information about the app.

## Key Architecture Notes

### Push Notifications
The app uses Firebase Cloud Messaging (FCM) for push notifications, triggered by Supabase database webhooks. If you need to work on push notifications:
- See `docs/PUSH_NOTIFICATIONS_SETUP.md` for initial setup
- See `docs/PUSH_NOTIFICATIONS_DEVELOPMENT.md` for adding new notification types

Key files:
- `supabase/functions/process-now-playing-event/` - Now Playing push notifications
- `supabase/functions/register-push-token/` - FCM token registration
- `lib/services/push_token_service.dart` - Token management
- `lib/services/push_notification_handler.dart` - Notification handling
