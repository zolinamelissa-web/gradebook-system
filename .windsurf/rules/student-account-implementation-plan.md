# Student Account System - Implementation Plan

## 📊 Current System Analysis

### Database Structure (SQLite)

#### Core Tables
1. **users** - Currently stores teacher accounts only
   - `uid` (Firebase Auth UID)
   - `email`, `display_name`, `provider`
   - `is_active`, `remote_id`, `deleted`

2. **students** - Student master data
   - `student_id` (UNIQUE) - **This is the key for registration**
   - `first_name`, `last_name`, `middle_name`
   - `email`, `phone`, `gender`, `birth_date`, `address`
   - `remote_id`, `deleted`

3. **Student-Related Data Tables**
   - `class_students` - Enrollment records
   - `grades` - Student grades
   - `attendance` - Attendance records
   - `assessment_scores` - Task/quiz scores
   - `interventions` - Interventions for students
   - `risk_flags` - At-risk student flags

### Firestore Structure
```
users/
  {teacher_uid}/
    students/
      {student_remote_id}/
        - student_id, first_name, last_name, email, etc.
    classes/
      {class_remote_id}/
    class_students/
      {enrollment_remote_id}/
        - student_remote_id, class_remote_id
    grades/
      {grade_remote_id}/
        - student_remote_id, class_remote_id, score, etc.
    attendance/
      {attendance_remote_id}/
        - student_remote_id, class_remote_id, date, status
    assessment_scores/
      {score_remote_id}/
        - student_remote_id, assessment_remote_id, score
    interventions/
      {intervention_remote_id}/
        - student_remote_id, class_remote_id
    risk_flags/
      {risk_remote_id}/
        - student_remote_id, class_remote_id
```

### Current Authentication Flow (Teachers Only)
1. Teacher signs in with Google/Email
2. Firebase Auth creates user with UID
3. User saved to local SQLite `users` table
4. Auto-sync pulls teacher's data from Firestore `users/{teacher_uid}/`

---

## 🎯 Student Account System Requirements

### Registration Flow
1. Student enters their **Student ID** (e.g., "2021-12345")
2. System checks if Student ID exists in Firestore (teacher must have synced it first)
3. If found, student creates account with:
   - Email/password or Google sign-in
   - Links Firebase Auth UID to Student ID
4. Student can now view their own records

### Data Access Pattern
- **Teachers**: Full access to all students in their classes
- **Students**: Read-only access to their own records only
  - Grades
  - Attendance
  - Assessment scores
  - Interventions
  - Risk flags
  - Class enrollments

### Offline/Online Sync
- **Online**: Student fetches latest data from Firestore
- **Offline**: Student views cached data from local SQLite
- **Sync**: Similar to teacher sync, but filtered by `student_remote_id`

---

## 🏗️ Implementation Architecture

### 1. Database Schema Changes

#### Add `user_role` to users table
```sql
ALTER TABLE users ADD COLUMN user_role TEXT DEFAULT 'teacher';
-- Values: 'teacher' or 'student'
```

#### Add `linked_student_id` to users table
```sql
ALTER TABLE users ADD COLUMN linked_student_id INTEGER;
-- Foreign key to students.id (for student accounts)
```

#### Add index for student lookups
```sql
CREATE INDEX idx_students_student_id ON students(student_id);
CREATE INDEX idx_users_linked_student ON users(linked_student_id);
```

### 2. Firestore Structure Changes

#### New collection: `student_accounts`
```
student_accounts/
  {student_id}/  # e.g., "2021-12345"
    - student_remote_id: "abc123"  # Links to students collection
    - teacher_uid: "teacher123"     # Which teacher added this student
    - firebase_uid: "student_uid"   # Firebase Auth UID (set after registration)
    - is_registered: true/false
    - registered_at: timestamp
    - email: "student@example.com"
```

This allows:
- Students to find their data using Student ID
- Teachers to see which students have registered
- Prevent duplicate registrations

### 3. New Models

#### StudentAccount Model
```dart
class StudentAccount {
  final String studentId;           // "2021-12345"
  final String studentRemoteId;     // Firestore remote_id
  final String teacherUid;          // Which teacher owns this student
  final String? firebaseUid;        // Firebase Auth UID (null until registered)
  final bool isRegistered;
  final String? email;
  final DateTime? registeredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

#### Update User Model
```dart
class User {
  // ... existing fields
  final String userRole;            // 'teacher' or 'student'
  final int? linkedStudentId;       // Local student.id (for students)
  final String? linkedStudentRemoteId; // For sync
}
```

### 4. New Repositories

#### StudentAccountRepository
```dart
class StudentAccountRepository {
  // Check if student ID exists in Firestore
  Future<StudentAccountInfo?> checkStudentIdExists(String studentId);
  
  // Register student account (link Firebase UID to Student ID)
  Future<void> registerStudentAccount(
    String studentId,
    String firebaseUid,
    String email,
  );
  
  // Get student account by Firebase UID
  Future<StudentAccountInfo?> getStudentAccountByUid(String firebaseUid);
}
```

#### StudentSyncService
```dart
class StudentSyncService {
  // Sync only data for a specific student
  static Future<SyncResult> syncStudentData(
    String studentRemoteId,
    String teacherUid,
  );
  
  // Download student's grades
  static Future<void> _syncStudentGrades(...);
  
  // Download student's attendance
  static Future<void> _syncStudentAttendance(...);
  
  // Download student's assessment scores
  static Future<void> _syncStudentAssessmentScores(...);
  
  // etc.
}
```

### 5. Authentication Flow Updates

#### Student Registration Screen
```dart
class StudentRegistrationScreen extends StatefulWidget {
  // Step 1: Enter Student ID
  // Step 2: Verify Student ID exists in Firestore
  // Step 3: Create Firebase Auth account (Email/Google)
  // Step 4: Link Firebase UID to Student ID in Firestore
  // Step 5: Sync student data to local SQLite
}
```

#### Student Login Screen
```dart
class StudentLoginScreen extends StatefulWidget {
  // Login with Email/Password or Google
  // Fetch student account info from Firestore
  // Sync student data to local SQLite
  // Navigate to Student Dashboard
}
```

### 6. UI Screens for Students

#### Student Dashboard
- View profile
- View enrolled classes
- View grades by class/period
- View attendance summary
- View assessment scores
- View interventions (if any)

#### Student Records Screen
- Filter by class
- Filter by grading period
- View detailed grades
- View attendance history
- View assessment scores

---

## 📝 Implementation Steps

### Phase 1: Database & Model Updates
1. ✅ Update `users` table schema (add `user_role`, `linked_student_id`)
2. ✅ Create `StudentAccount` model
3. ✅ Update `User` model to include role and linked student
4. ✅ Create database migration script

### Phase 2: Firestore Structure
1. ✅ Create `student_accounts` collection structure
2. ✅ Update teacher sync to create student account entries
3. ✅ Add Firestore security rules for student access

### Phase 3: Student Registration
1. ✅ Create `StudentAccountRepository`
2. ✅ Create `StudentRegistrationScreen`
3. ✅ Implement Student ID verification
4. ✅ Implement Firebase Auth account creation
5. ✅ Link Firebase UID to Student ID in Firestore

### Phase 4: Student Sync Service
1. ✅ Create `StudentSyncService`
2. ✅ Implement filtered sync for student data
3. ✅ Download only student's own records
4. ✅ Handle offline caching

### Phase 5: Student UI
1. ✅ Create `StudentLoginScreen`
2. ✅ Create `StudentDashboardScreen`
3. ✅ Create `StudentRecordsScreen`
4. ✅ Create `StudentProfileScreen`

### Phase 6: Testing & Security
1. ✅ Test registration flow
2. ✅ Test sync (online/offline)
3. ✅ Verify data isolation (students can't see others' data)
4. ✅ Test on multiple devices

---

## 🔒 Security Considerations

### Firestore Security Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Teacher access (existing)
    match /users/{teacherUid}/{document=**} {
      allow read, write: if request.auth.uid == teacherUid;
    }
    
    // Student account registration
    match /student_accounts/{studentId} {
      // Anyone can read to verify Student ID exists
      allow read: if request.auth != null;
      
      // Only the linked student can update their own account
      allow update: if request.auth.uid == resource.data.firebase_uid;
      
      // Teachers can create student account entries
      allow create: if request.auth != null;
    }
    
    // Student data access (read-only for students)
    match /users/{teacherUid}/students/{studentRemoteId} {
      allow read: if isStudentOwner(studentRemoteId);
    }
    
    match /users/{teacherUid}/grades/{gradeId} {
      allow read: if isStudentOwnerOfGrade(gradeId);
    }
    
    match /users/{teacherUid}/attendance/{attendanceId} {
      allow read: if isStudentOwnerOfAttendance(attendanceId);
    }
    
    // Helper functions
    function isStudentOwner(studentRemoteId) {
      let studentAccount = get(/databases/$(database)/documents/student_accounts/$(getStudentIdFromUid())).data;
      return request.auth != null && 
             studentAccount.firebase_uid == request.auth.uid &&
             studentAccount.student_remote_id == studentRemoteId;
    }
    
    function getStudentIdFromUid() {
      // Query student_accounts where firebase_uid == request.auth.uid
      // Return student_id
    }
  }
}
```

### Data Isolation
- Students can ONLY read their own data
- Students CANNOT write/update any data
- Students CANNOT see other students' records
- Teachers maintain full read/write access to their students

---

## 🔄 Sync Flow Comparison

### Teacher Sync (Existing)
```
1. Teacher logs in with Firebase Auth
2. Get teacher UID
3. Sync all data from users/{teacher_uid}/*
4. Download all students, classes, grades, etc.
5. Store in local SQLite
```

### Student Sync (New)
```
1. Student logs in with Firebase Auth
2. Get student Firebase UID
3. Query student_accounts to find student_remote_id and teacher_uid
4. Sync only data where student_remote_id matches
   - users/{teacher_uid}/students/{student_remote_id}
   - users/{teacher_uid}/grades?student_remote_id={id}
   - users/{teacher_uid}/attendance?student_remote_id={id}
   - users/{teacher_uid}/assessment_scores?student_remote_id={id}
   - etc.
5. Store in local SQLite (filtered data only)
```

---

## 📱 Example User Flows

### Teacher Flow (Unchanged)
1. Teacher adds student "John Doe" with Student ID "2021-12345"
2. Teacher syncs to Firestore
3. Firestore creates:
   - `users/{teacher_uid}/students/{student_remote_id}`
   - `student_accounts/2021-12345` (with student_remote_id, teacher_uid)

### Student Registration Flow
1. Student opens app → "Register as Student"
2. Student enters Student ID: "2021-12345"
3. App queries `student_accounts/2021-12345`
4. If found:
   - Show student name: "John Doe"
   - Ask: "Is this you?"
5. Student confirms → Create account screen
6. Student signs up with Email/Google
7. App links Firebase UID to `student_accounts/2021-12345`
8. App syncs student data to local SQLite
9. Student sees dashboard with their records

### Student Login Flow (Returning User)
1. Student opens app → "Login as Student"
2. Student logs in with Email/Google
3. App gets Firebase UID
4. App queries `student_accounts` where `firebase_uid == {uid}`
5. App gets `student_remote_id` and `teacher_uid`
6. App syncs student data (online) or loads from cache (offline)
7. Student sees dashboard

---

## 🛠️ Code Structure

```
lib/
  data/
    models/
      student_account_model.dart          # NEW
      user_model.dart                     # UPDATED (add role, linked_student_id)
    repositories/
      student_account_repository.dart     # NEW
      auth_repository.dart                # UPDATED (handle student auth)
  core/
    services/
      student_sync_service.dart           # NEW
      sync_service.dart                   # EXISTING (teacher sync)
  presentation/
    student/                              # NEW FOLDER
      student_registration_screen.dart
      student_login_screen.dart
      student_dashboard_screen.dart
      student_records_screen.dart
      student_profile_screen.dart
    auth/
      auth_screen.dart                    # UPDATED (add student option)
```

---

## ✅ Next Steps

1. **Confirm this architecture** with you
2. **Implement Phase 1**: Database schema changes
3. **Implement Phase 2**: Firestore structure
4. **Implement Phase 3**: Student registration
5. **Implement Phase 4**: Student sync service
6. **Implement Phase 5**: Student UI screens
7. **Test thoroughly** on multiple devices

---

## 🎯 Key Benefits

✅ **Secure**: Students can only see their own data
✅ **Offline-capable**: Students can view cached data without internet
✅ **Scalable**: Works with multiple teachers and thousands of students
✅ **Simple registration**: Just need Student ID (teacher must add them first)
✅ **Real-time**: Students see updates when teachers sync
✅ **Privacy**: No student can see another student's records

---

## ❓ Questions to Confirm

1. Should students be able to update their profile (email, phone, photo)?
2. Should students receive notifications when grades are posted?
3. Should there be a parent/guardian account option?
4. Should students be able to see their class schedule?
5. What happens if a teacher deletes a student? (Disable student account?)
