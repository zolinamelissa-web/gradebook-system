# Google OAuth Setup for Flutter Web

## Problem
The Google Sign-In is failing with "Authorization Error: no registered origin" because the OAuth 2.0 client is not properly configured for web applications.

## Solution Steps

### 1. Go to Google Cloud Console
1. Visit: https://console.cloud.google.com/
2. Select your project: `grade-book-99d84`
3. Navigate to: **APIs & Services** → **Credentials**

### 2. Create Web OAuth Client
1. Click **+ CREATE CREDENTIALS** → **OAuth client ID**
2. Select **Web application** as the application type
3. Give it a name: `Grade Book Web Client`
4. Under **Authorized JavaScript origins**, add:
   - `http://localhost:8080` (primary port)
   - `http://127.0.0.1:8080` (alternative localhost)
   - `https://localhost:8080` (for HTTPS testing)
   - `https://127.0.0.1:8080` (for HTTPS testing)
5. Under **Authorized redirect URIs**, add:
   - `http://localhost:8080` (primary port)
   - `http://127.0.0.1:8080` (alternative localhost)
   - `https://localhost:8080` (for HTTPS testing)
   - `https://127.0.0.1:8080` (for HTTPS testing)
6. Click **CREATE**

### 3. Update Firebase Configuration
After creating the web OAuth client, you'll get a new Client ID. Update the `firebase_options.dart` file:

```dart
static const FirebaseOptions web = FirebaseOptions(
  apiKey: 'AIzaSyB42fLLAzvcVlbbVlL0iF_mf8tferzorlc',
  appId: '1:352028414871:web:8e353ae433a9cabb34aad2',
  messagingSenderId: '352028414871',
  projectId: 'grade-book-99d84',
  authDomain: 'grade-book-99d84.firebaseapp.com',
  databaseURL: 'https://grade-book-99d84-default-rtdb.asia-southeast1.firebasedatabase.app',
  storageBucket: 'grade-book-99d84.firebasestorage.app',
  measurementId: 'G-GEPT4612YR',
  // Add the new web client ID here
  clientId: 'YOUR_NEW_WEB_CLIENT_ID_HERE',
);
```

### 4. Enable Required APIs
Make sure these APIs are enabled in Google Cloud Console:
1. **Google+ API** (if using older Google Sign-In)
2. **Google Identity Toolkit API**
3. **Firebase Authentication API**

### 5. For Production Deployment
When deploying to production, add your production domain:
1. Go back to the OAuth client settings
2. Add your production domain to authorized origins:
   - `https://yourdomain.com`
3. Add production redirect URIs:
   - `https://yourdomain.com`

### 6. Test the Configuration
1. Restart your Flutter web server on port 8080:
   ```bash
   flutter run -d web-server --web-port=8080
   ```
2. Try Google Sign-In again
3. Check browser console for any remaining errors

## Common Issues & Solutions

### Issue: "redirect_uri_mismatch"
- **Cause**: The redirect URI in the request doesn't match what's configured
- **Fix**: Add the exact URL (including port) to authorized redirect URIs

### Issue: "invalid_client"
- **Cause**: Using wrong client ID or client not configured for web
- **Fix**: Create proper web OAuth client and use its client ID

### Issue: "access_denied"
- **Cause**: User denied consent or OAuth screen not configured properly
- **Fix**: Configure OAuth consent screen with proper app information

## Alternative: Use Firebase Auth UI
If OAuth setup is complex, consider using Firebase UI Auth:

```dart
dependencies:
  firebase_ui_auth: ^1.12.0
  firebase_ui_oauth_google: ^1.5.0
```

This handles the OAuth configuration automatically.

## Debugging Tips
1. Check browser network tab for failed requests
2. Look for detailed error messages in browser console
3. Verify the client ID matches exactly (no extra spaces)
4. Ensure Firebase project is in the same Google Cloud project as OAuth client

## Security Notes
- Never expose client secrets in Flutter web apps
- Use HTTPS in production
- Regularly rotate OAuth client secrets
- Monitor OAuth client usage in Google Cloud Console
