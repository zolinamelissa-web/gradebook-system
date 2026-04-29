# Migrate Student Emails - Fix for Existing Students

This guide explains how to migrate existing student emails from `student_accounts` to the `students` collection in Firestore.

## Problem

Students who signed up **before** the email sync fix don't have their emails in the local SQLite database because:
1. Their email was saved to `student_accounts` collection only
2. The email was NOT saved to `users/{teacherUid}/students/{studentRemoteId}` collection
3. When sync runs, it can't find the email in the students collection
4. Local database never gets updated with the email

## Solution

Run the migration Cloud Function to copy all student emails from `student_accounts` to the `students` collection.

## Option 1: Run from Flutter App (Recommended)

### Step 1: Add a temporary button to your app

Add this code to any teacher screen (e.g., `home_screen.dart` or `settings_screen.dart`):

```dart
import '../../data/repositories/auth_repository.dart';

// Add this button somewhere in your UI
ElevatedButton(
  onPressed: () async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting migration...')),
      );
      
      final result = await AuthRepository().migrateStudentEmails();
      
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Migration Complete'),
          content: Text(
            'Updated: ${result['updated']}\n'
            'Skipped: ${result['skipped']}\n'
            'Errors: ${result['errors']}\n\n'
            '${result['message']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Migration failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  },
  child: const Text('Migrate Student Emails'),
)
```

### Step 2: Run the migration

1. Login as a teacher
2. Navigate to the screen with the migration button
3. Tap "Migrate Student Emails"
4. Wait for the migration to complete
5. Check the results in the dialog

### Step 3: Test the fix

1. Have the student (Ayco, Louise Antonnet) sync their data
2. Check if the email now appears in their profile

### Step 4: Remove the button

After migration is complete, remove the temporary button from your code.

## Option 2: Run via Firebase Console

### Step 1: Open Firebase Console

1. Go to: https://console.firebase.google.com/project/grade-book-99d84/functions
2. Find the `migrateStudentEmails` function
3. Click on it to view details

### Step 2: Test the function

1. Go to the "Testing" tab
2. Click "Run test"
3. Leave the data empty: `{}`
4. Click "Run the function"
5. Check the logs for results

## Option 3: Run via Firebase CLI

```bash
cd /Applications/XAMPP/xamppfiles/htdocs/FlutterApps/grade_book
firebase functions:shell

# In the shell, run:
migrateStudentEmails()
```

## What the Migration Does

The Cloud Function:
1. Reads all documents from `student_accounts` collection
2. For each student, gets all teacher links
3. For each teacher link with an email and student_remote_id:
   - Updates `users/{teacherUid}/students/{studentRemoteId}` with the email
   - Uses merge: true to preserve existing data
4. Returns statistics: updated, skipped, errors

## After Migration

Once the migration is complete:
1. All existing students will have their emails in the `students` collection
2. When students sync, their emails will be downloaded to local SQLite
3. The email will appear in the Student Profile screen
4. Future student signups will automatically include the email (due to the fix in `registerStudentAccount`)

## Troubleshooting

### "Cloud Function not deployed"
- Run: `firebase deploy --only functions:migrateStudentEmails`

### "Must be authenticated"
- Make sure you're logged in as a teacher in the app

### "No internet connection"
- The migration requires internet to call the Cloud Function

### Migration shows "0 updated"
- Check Firebase Console logs for errors
- Verify students have `student_remote_id` in their teacher links
- Verify students have emails in `student_accounts/{studentId}/teachers/{teacherUid}`

## Verification

After migration, verify in Firebase Console:
1. Go to Firestore Database
2. Navigate to: `users/{teacherUid}/students/{studentRemoteId}`
3. Check that the `email` field is populated
4. The `updated_at` timestamp should be recent

## Notes

- The migration is **safe to run multiple times** (uses merge: true)
- It only updates students who have emails in `student_accounts`
- It preserves all existing data in the students collection
- Students without `student_remote_id` will be skipped
