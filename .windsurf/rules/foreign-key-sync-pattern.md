# Foreign Key Synchronization Pattern for Cross-Device Sync

## Overview
All tables with foreign key relationships MUST use stable `*_remote_id` fields in Firestore to ensure correct FK mapping across devices with different local SQLite auto-increment IDs.

## Pattern Requirements

### 1. Upload (Local → Firestore)
When uploading a row with foreign keys:
```dart
// Get remote_id for each FK
final localStudentId = localRow['student_id'] as int?;
final studentRemoteId = localStudentId == null
    ? null
    : await _getRemoteIdForLocalId(db, 'students', localStudentId);

// Include BOTH local ID and remote_id in Firestore payload
await collection.doc(remoteId).update({
  'student_id': localRow['student_id'],           // Legacy/fallback
  'student_remote_id': studentRemoteId ?? '',     // Cross-device stable reference
  // ... other fields
});
```

### 2. Download (Firestore → Local)
When downloading a row with foreign keys:
```dart
// Resolve remote_id to local SQLite ID
final remoteStudentRemoteId = remote['student_remote_id']?.toString() ?? '';
if (remoteStudentRemoteId.isEmpty) {
  print('[SyncService] Skipping download (legacy-only row): missing student_remote_id');
  continue;  // Skip legacy rows without stable FK references
}

final resolvedStudentId = await _getLocalIdForRemoteId(
  db,
  'students',
  remoteStudentRemoteId,
);
if (resolvedStudentId == null) {
  print('[SyncService] Skipping download: student_remote_id not found locally remote_id=$remoteStudentRemoteId');
  continue;  // Skip if parent record doesn't exist locally yet
}

// Use resolved local ID for SQLite insert/update
await db.insert('table_name', {
  'student_id': resolvedStudentId,  // Resolved local SQLite ID
  // ... other fields
});
```

## Tables with FK Mapping (Complete List)

### Full-Sync Tables
1. **grading_periods** → `class_remote_id`
2. **grading_categories** → `grading_period_remote_id`
3. **grading_configurations** → `grading_period_remote_id`, `category_remote_id`
4. **grading_assessments** → `class_remote_id`, `grading_period_remote_id`, `category_remote_id`
5. **assessment_scores** → `assessment_remote_id`, `student_remote_id`
6. **grades** → `student_remote_id`, `class_remote_id`, `grading_period_remote_id`, `category_remote_id`
7. **attendance** → `student_remote_id`, `class_remote_id`, `grading_period_remote_id`
8. **interventions** → `student_remote_id`, `class_remote_id`, `grading_period_remote_id`
9. **risk_flags** → `student_remote_id`, `class_remote_id`, `grading_period_remote_id`
10. **lessons** → `class_remote_id`

### Per-Class Sync Tables
11. **class_students** → `class_remote_id`, `student_remote_id`

### Tables WITHOUT Foreign Keys
- **users** (no FKs)
- **settings** (no FKs)
- **students** (no FKs)
- **subjects** (no FKs)
- **classes** → uses `subject_code` + `subject_remote_id` (special case, already handled)

## Adding a New Table with Foreign Keys

### Step 1: Database Schema
Ensure the table has `remote_id` and `deleted` columns:
```sql
CREATE TABLE new_table (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  parent_id INTEGER NOT NULL,
  -- other columns --
  remote_id TEXT,
  deleted INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (parent_id) REFERENCES parent_table (id) ON DELETE CASCADE
)
```

### Step 2: Sync Method Implementation
```dart
static Future<void> _syncNewTable(String userId, SyncResult result) async {
  print('[SyncService] Syncing new_table...');
  final db = await DatabaseHelper.instance.database;
  final collection = _firestore.collection('users/$userId/new_table');

  final localRows = await db.query('new_table', where: 'deleted = 0');
  final remoteSnapshot = await collection.get();
  final remoteMap = <String, Map<String, dynamic>>{};
  for (final doc in remoteSnapshot.docs) {
    remoteMap[doc.id] = {...doc.data(), 'doc_id': doc.id};
  }

  // UPLOAD: Local → Firestore
  for (final localRow in localRows) {
    final localId = localRow['id'] as int;
    final remoteId = localRow['remote_id'] as String?;
    final localUpdated = DateTime.parse(localRow['updated_at'] as String);

    // Get FK remote_ids
    final localParentId = localRow['parent_id'] as int?;
    final parentRemoteId = localParentId == null
        ? null
        : await _getRemoteIdForLocalId(db, 'parent_table', localParentId);

    if (remoteId != null && remoteMap.containsKey(remoteId)) {
      final remote = remoteMap[remoteId]!;
      final remoteUpdated = (remote['updated_at'] as Timestamp).toDate();

      if (localUpdated.isAfter(remoteUpdated)) {
        // UPDATE: Include FK remote_ids
        await collection.doc(remoteId).update({
          'parent_id': localRow['parent_id'],
          'parent_remote_id': parentRemoteId ?? '',  // ← FK remote_id
          // ... other fields
          'updated_at': Timestamp.fromDate(localUpdated),
        });
        result.uploaded++;
      } else if (remoteUpdated.isAfter(localUpdated)) {
        // DOWNLOAD UPDATE: Resolve FK remote_ids
        final remoteParentRemoteId = remote['parent_remote_id']?.toString() ?? '';
        if (remoteParentRemoteId.isEmpty) {
          print('[SyncService] Skipping new_table download/update (legacy-only row): missing parent_remote_id');
          remoteMap.remove(remoteId);
          continue;
        }
        final resolvedParentId = await _getLocalIdForRemoteId(
          db,
          'parent_table',
          remoteParentRemoteId,
        );
        if (resolvedParentId == null) {
          print('[SyncService] Skipping new_table download/update: parent_remote_id not found locally remote_id=$remoteParentRemoteId');
          remoteMap.remove(remoteId);
          continue;
        }
        await db.update(
          'new_table',
          {
            'parent_id': resolvedParentId,  // ← Resolved local ID
            // ... other fields
            'updated_at': remoteUpdated.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        result.downloaded++;
      }
      remoteMap.remove(remoteId);
    } else {
      // INSERT NEW: Include FK remote_ids
      final docRef = await collection.add({
        'parent_id': localRow['parent_id'],
        'parent_remote_id': parentRemoteId ?? '',  // ← FK remote_id
        // ... other fields
        'updated_at': Timestamp.fromDate(localUpdated),
        'created_at': Timestamp.fromDate(
          DateTime.parse(localRow['created_at'] as String),
        ),
      });
      await db.update(
        'new_table',
        {'remote_id': docRef.id},
        where: 'id = ?',
        whereArgs: [localId],
      );
      result.uploaded++;
    }
  }

  // DOWNLOAD INSERT: Resolve FK remote_ids
  for (final remote in remoteMap.values) {
    final remoteParentRemoteId = remote['parent_remote_id']?.toString() ?? '';
    if (remoteParentRemoteId.isEmpty) {
      print('[SyncService] Skipping new_table insert (legacy-only row): missing parent_remote_id');
      continue;
    }
    final resolvedParentId = await _getLocalIdForRemoteId(
      db,
      'parent_table',
      remoteParentRemoteId,
    );
    if (resolvedParentId == null) {
      print('[SyncService] Skipping new_table insert: parent_remote_id not found locally remote_id=$remoteParentRemoteId');
      continue;
    }
    await db.insert('new_table', {
      'parent_id': resolvedParentId,  // ← Resolved local ID
      // ... other fields
      'remote_id': remote['doc_id'],
      'created_at': (remote['created_at'] as Timestamp).toDate().toIso8601String(),
      'updated_at': (remote['updated_at'] as Timestamp).toDate().toIso8601String(),
    });
    result.downloaded++;
  }
  print('[SyncService] New_table sync complete');
}
```

### Step 3: Add to syncAll()
```dart
onStatusUpdate?.call('Syncing New Table...');
await _syncNewTable(userId, result);
```

## Helper Methods
```dart
// Get Firestore remote_id for a local SQLite ID
static Future<String?> _getRemoteIdForLocalId(
  Database db,
  String tableName,
  int localId,
) async {
  final rows = await db.query(
    tableName,
    columns: ['remote_id'],
    where: 'id = ?',
    whereArgs: [localId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first['remote_id'] as String?;
}

// Get local SQLite ID for a Firestore remote_id
static Future<int?> _getLocalIdForRemoteId(
  Database db,
  String tableName,
  String remoteId,
) async {
  final rows = await db.query(
    tableName,
    columns: ['id'],
    where: 'remote_id = ?',
    whereArgs: [remoteId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first['id'] as int?;
}
```

## Testing Checklist
- [ ] Device A: Create data with FK relationships
- [ ] Device A: Sync to Firestore
- [ ] Firestore: Verify `*_remote_id` fields are present
- [ ] Device B: Fresh install or clear local DB
- [ ] Device B: Sync from Firestore
- [ ] Device B: Verify FK relationships are correct (no broken references)
- [ ] Check logs for "Skipping ... download" messages (indicates missing parent records or legacy data)

## Common Issues
1. **Missing `*_remote_id` in Firestore**: Device A needs to re-sync after code update
2. **Parent record not synced yet**: Sync order matters - parent tables sync before child tables
3. **Legacy data without `remote_id`**: Old rows are skipped on download to prevent FK mismatches
