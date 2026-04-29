# Firebase Cloud Function Setup for Password Reset

This document explains how to deploy the Firebase Cloud Function required for the student password reset feature.

## Prerequisites

1. Firebase CLI installed (`npm install -g firebase-tools`)
2. Node.js installed (v16 or higher recommended)
3. Firebase project initialized in your app
4. Firebase Admin SDK access

## Setup Instructions

### 1. Initialize Firebase Functions (if not already done)

```bash
cd /Applications/XAMPP/xamppfiles/htdocs/FlutterApps/grade_book
firebase init functions
```

Select:
- Use existing project (select your Firebase project)
- Language: JavaScript or TypeScript
- Install dependencies: Yes

### 2. Create the Cloud Function

Navigate to the functions directory and edit `index.js` (or `index.ts` for TypeScript):

```bash
cd functions
```

Add the following code to `functions/index.js`:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
admin.initializeApp();

/**
 * Reset student password to temporary password "TempPassword123"
 * This function can only be called by authenticated users (teachers)
 * 
 * @param {Object} data - Contains the student's email
 * @param {Object} context - Authentication context
 * @returns {Object} Success status
 */
exports.resetStudentPassword = functions.https.onCall(async (data, context) => {
  // Verify the caller is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Must be authenticated to reset student password'
    );
  }

  const email = data.email;

  // Validate email parameter
  if (!email || typeof email !== 'string') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Email is required and must be a string'
    );
  }

  try {
    // Get the user by email
    const user = await admin.auth().getUserByEmail(email);
    
    // Update the user's password
    await admin.auth().updateUser(user.uid, {
      password: 'TempPassword123'
    });

    console.log(`Password reset successful for user: ${email} (UID: ${user.uid})`);

    return {
      success: true,
      message: 'Password reset successfully'
    };
  } catch (error) {
    console.error('Error resetting password:', error);
    
    if (error.code === 'auth/user-not-found') {
      throw new functions.https.HttpsError(
        'not-found',
        'No user found with this email address'
      );
    }
    
    throw new functions.https.HttpsError(
      'internal',
      `Failed to reset password: ${error.message}`
    );
  }
});
```

### 3. Update package.json

Ensure your `functions/package.json` includes the required dependencies:

```json
{
  "name": "functions",
  "description": "Cloud Functions for Firebase",
  "scripts": {
    "serve": "firebase emulators:start --only functions",
    "shell": "firebase functions:shell",
    "start": "npm run shell",
    "deploy": "firebase deploy --only functions",
    "logs": "firebase functions:log"
  },
  "engines": {
    "node": "16"
  },
  "main": "index.js",
  "dependencies": {
    "firebase-admin": "^11.8.0",
    "firebase-functions": "^4.3.1"
  }
}
```

### 4. Install Dependencies

```bash
cd functions
npm install
```

### 5. Deploy the Cloud Function

```bash
firebase deploy --only functions:resetStudentPassword
```

Or deploy all functions:

```bash
firebase deploy --only functions
```

### 6. Verify Deployment

After deployment, you should see output like:

```
✔  functions[resetStudentPassword(us-central1)] Successful create operation.
Function URL (resetStudentPassword): https://us-central1-YOUR-PROJECT.cloudfunctions.net/resetStudentPassword
```

## Testing the Function

### Using Firebase Emulator (Local Testing)

```bash
cd functions
npm run serve
```

Then update your app to point to the local emulator in development mode.

### Using Firebase Console

1. Go to Firebase Console → Functions
2. You should see `resetStudentPassword` listed
3. Check the logs to verify it's working

## Security Considerations

1. **Authentication Required**: Only authenticated users can call this function
2. **Teacher Verification**: Consider adding additional checks to verify the caller is a teacher
3. **Rate Limiting**: Consider implementing rate limiting to prevent abuse
4. **Audit Logging**: The function logs all password reset attempts

## Troubleshooting

### Error: "Cloud Function not deployed"

- Verify the function is deployed: `firebase functions:list`
- Check Firebase Console → Functions to see if it's listed
- Redeploy: `firebase deploy --only functions:resetStudentPassword`

### Error: "Permission denied"

- Ensure the caller is authenticated
- Check Firebase Authentication is enabled
- Verify Firebase Admin SDK has proper permissions

### Error: "User not found"

- Verify the student email exists in Firebase Authentication
- Check the email is correctly formatted

## Additional Security (Optional)

To add teacher role verification, modify the function:

```javascript
exports.resetStudentPassword = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }

  // Verify caller is a teacher (check custom claims or Firestore)
  const callerDoc = await admin.firestore()
    .collection('users')
    .doc(context.auth.uid)
    .get();
  
  if (!callerDoc.exists || callerDoc.data().userRole !== 'teacher') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only teachers can reset student passwords'
    );
  }

  // Rest of the function...
});
```

## Cost Considerations

- Cloud Functions are billed based on invocations, compute time, and network egress
- This function should have minimal cost as it's a simple operation
- Free tier includes 2 million invocations per month

## Support

For issues or questions:
1. Check Firebase Functions logs: `firebase functions:log`
2. Review Firebase Console → Functions → Logs
3. Ensure all dependencies are up to date
