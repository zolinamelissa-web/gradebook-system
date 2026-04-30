import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('gradebook.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 11,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add theme columns to settings table if they don't already exist
      try {
        final columns = await db.rawQuery('PRAGMA table_info(settings)');
        final hasPrimary = columns.any(
          (c) => c['name'] == 'theme_primary_color',
        );
        final hasSecondary = columns.any(
          (c) => c['name'] == 'theme_secondary_color',
        );

        if (!hasPrimary) {
          await db.execute(
            'ALTER TABLE settings ADD COLUMN theme_primary_color INTEGER',
          );
        }

        if (!hasSecondary) {
          await db.execute(
            'ALTER TABLE settings ADD COLUMN theme_secondary_color INTEGER',
          );
        }

        print(
          '[DatabaseHelper] Upgraded database to version 2: ensured theme columns exist',
        );
      } catch (e) {
        // Log but do not crash app on upgrade
        // This will help avoid hard failures if schema already matches.
        // ignore: avoid_print
        print('[DatabaseHelper] Error during DB upgrade v2: $e');
      }
    }

    if (oldVersion < 3) {
      // Add sync columns for Firebase cloud sync
      try {
        final tables = [
          'students',
          'subjects',
          'classes',
          'grading_periods',
          'grading_categories',
          'grading_configurations',
          'grades',
          'attendance',
          'interventions',
          'risk_flags',
        ];

        for (final table in tables) {
          final columns = await db.rawQuery('PRAGMA table_info($table)');
          final hasRemoteId = columns.any((c) => c['name'] == 'remote_id');
          final hasDeleted = columns.any((c) => c['name'] == 'deleted');

          if (!hasRemoteId) {
            await db.execute('ALTER TABLE $table ADD COLUMN remote_id TEXT');
          }

          if (!hasDeleted) {
            await db.execute(
              'ALTER TABLE $table ADD COLUMN deleted INTEGER DEFAULT 0',
            );
          }
        }

        print(
          '[DatabaseHelper] Upgraded database to version 3: added sync columns (remote_id, deleted)',
        );
      } catch (e) {
        print('[DatabaseHelper] Error during DB upgrade v3: $e');
      }
    }

    if (oldVersion < 4) {
      // Add lessons table for weekly class lessons
      try {
        print(
          '[DatabaseHelper] Upgrade to version 4 skipped table creation (handled by onCreate)',
        );
      } catch (e) {
        print('[DatabaseHelper] Error during DB upgrade v4: $e');
      }
    }

    if (oldVersion < 5) {
      // Add grading assessments (items within a grading category) + per-student item scores
      try {
        print(
          '[DatabaseHelper] Upgrade to version 5 skipped table creation (handled by onCreate)',
        );
      } catch (e) {
        print('[DatabaseHelper] Error during DB upgrade v5: $e');
      }
    }

    if (oldVersion < 6) {
      // Ensure all tables have remote_id and deleted columns for sync
      try {
        final tables = [
          'students',
          'subjects',
          'classes',
          'grading_periods',
          'grading_categories',
          'grading_configurations',
          'grades',
          'attendance',
          'interventions',
          'risk_flags',
        ];

        for (final table in tables) {
          final columns = await db.rawQuery('PRAGMA table_info($table)');
          final hasRemoteId = columns.any((c) => c['name'] == 'remote_id');
          final hasDeleted = columns.any((c) => c['name'] == 'deleted');

          if (!hasRemoteId) {
            await db.execute('ALTER TABLE $table ADD COLUMN remote_id TEXT');
            print('[DatabaseHelper] Added remote_id to $table');
          }

          if (!hasDeleted) {
            await db.execute(
              'ALTER TABLE $table ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            print('[DatabaseHelper] Added deleted to $table');
          }
        }

        print(
          '[DatabaseHelper] Upgraded database to version 6: ensured all sync columns exist',
        );
      } catch (e) {
        print('[DatabaseHelper] Error during DB upgrade v6: $e');
      }
    }

    if (oldVersion < 7) {
      // Add remote_id and deleted columns to users and class_students tables for sync
      try {
        // Add to users table
        final usersColumns = await db.rawQuery('PRAGMA table_info(users)');
        final usersHasRemoteId = usersColumns.any(
          (c) => c['name'] == 'remote_id',
        );
        final usersHasDeleted = usersColumns.any((c) => c['name'] == 'deleted');

        if (!usersHasRemoteId) {
          await db.execute('ALTER TABLE users ADD COLUMN remote_id TEXT');
          print('[DatabaseHelper] Added remote_id to users');
        }

        if (!usersHasDeleted) {
          await db.execute(
            'ALTER TABLE users ADD COLUMN deleted INTEGER DEFAULT 0',
          );
          print('[DatabaseHelper] Added deleted to users');
        }

        // Add to class_students table
        final classStudentsColumns = await db.rawQuery(
          'PRAGMA table_info(class_students)',
        );
        final classStudentsHasRemoteId = classStudentsColumns.any(
          (c) => c['name'] == 'remote_id',
        );
        final classStudentsHasDeleted = classStudentsColumns.any(
          (c) => c['name'] == 'deleted',
        );

        if (!classStudentsHasRemoteId) {
          await db.execute(
            'ALTER TABLE class_students ADD COLUMN remote_id TEXT',
          );
          print('[DatabaseHelper] Added remote_id to class_students');
        }

        if (!classStudentsHasDeleted) {
          await db.execute(
            'ALTER TABLE class_students ADD COLUMN deleted INTEGER DEFAULT 0',
          );
          print('[DatabaseHelper] Added deleted to class_students');
        }

        print(
          '[DatabaseHelper] Upgraded database to version 7: added sync columns to users and class_students tables',
        );
      } catch (e) {
        print('[DatabaseHelper] Error during DB upgrade v7: $e');
      }
    }

    if (oldVersion < 8) {
      // Add student account support columns to users table
      try {
        final usersColumns = await db.rawQuery('PRAGMA table_info(users)');
        final hasUserRole = usersColumns.any((c) => c['name'] == 'user_role');
        final hasLinkedStudentId = usersColumns.any(
          (c) => c['name'] == 'linked_student_id',
        );

        if (!hasUserRole) {
          await db.execute(
            'ALTER TABLE users ADD COLUMN user_role TEXT DEFAULT \'teacher\'',
          );
          print('[DatabaseHelper] Added user_role to users');
        }

        if (!hasLinkedStudentId) {
          await db.execute(
            'ALTER TABLE users ADD COLUMN linked_student_id INTEGER',
          );
          print('[DatabaseHelper] Added linked_student_id to users');
        }

        // Create index for student lookups
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_users_linked_student ON users(linked_student_id)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_students_student_id ON students(student_id)',
        );

        print(
          '[DatabaseHelper] Upgraded database to version 8: added student account support',
        );
      } catch (e) {
        print('[DatabaseHelper] Error during DB upgrade v8: $e');
      }
    }

    if (oldVersion < 9) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS counseling_reasons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            teacher_uid TEXT NOT NULL,
            student_remote_id TEXT NOT NULL,
            class_remote_id TEXT NOT NULL,
            subject_code TEXT,
            reason TEXT NOT NULL,
            remote_id TEXT,
            deleted INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        print(
          '[DatabaseHelper] Upgraded database to version 9: added counseling_reasons',
        );
      } catch (e) {
        print('[DatabaseHelper] Error during DB upgrade v9: $e');
      }
    }

    if (oldVersion < 10) {
      try {
        // Add CHECK constraints to prevent invalid data
        // SQLite doesn't support adding CHECK constraints to existing tables
        // So we need to recreate the tables

        // Backup data
        final assessments = await db.query('grading_assessments');
        final scores = await db.query('assessment_scores');

        // Drop and recreate grading_assessments with CHECK constraint
        await db.execute('DROP TABLE IF EXISTS grading_assessments');
        await db.execute('''
          CREATE TABLE grading_assessments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            grading_period_id INTEGER NOT NULL,
            category_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            max_score REAL NOT NULL DEFAULT 100,
            order_num INTEGER NOT NULL DEFAULT 0,
            remote_id TEXT,
            deleted INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE,
            FOREIGN KEY (grading_period_id) REFERENCES grading_periods (id) ON DELETE CASCADE,
            FOREIGN KEY (category_id) REFERENCES grading_categories (id) ON DELETE CASCADE,
            UNIQUE(grading_period_id, category_id, name),
            CHECK (max_score > 0)
          )
        ''');

        // Drop and recreate assessment_scores with CHECK constraint
        await db.execute('DROP TABLE IF EXISTS assessment_scores');
        await db.execute('''
          CREATE TABLE assessment_scores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            assessment_id INTEGER NOT NULL,
            student_id INTEGER NOT NULL,
            score REAL NOT NULL DEFAULT 0,
            remarks TEXT,
            remote_id TEXT,
            deleted INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (assessment_id) REFERENCES grading_assessments (id) ON DELETE CASCADE,
            FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
            UNIQUE(assessment_id, student_id),
            CHECK (score >= 0)
          )
        ''');

        // Restore data
        final batch = db.batch();
        for (final assessment in assessments) {
          // Ensure max_score is valid before restoring
          final maxScore = (assessment['max_score'] as num?)?.toDouble() ?? 0.0;
          if (maxScore <= 0) {
            assessment['max_score'] = 100.0; // Default to 100 if invalid
          }
          batch.insert('grading_assessments', assessment);
        }
        for (final score in scores) {
          // Ensure score is not negative before restoring
          final scoreValue = (score['score'] as num?)?.toDouble() ?? 0.0;
          if (scoreValue < 0) {
            score['score'] = 0.0; // Default to 0 if negative
          }
          batch.insert('assessment_scores', score);
        }
        await batch.commit(noResult: true);

        print(
          '[DatabaseHelper] Upgraded database to version 10: added CHECK constraints',
        );
      } catch (e) {
        print('[DatabaseHelper] Error during DB upgrade v10: $e');
      }
    }

    if (oldVersion < 11) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS announcements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            teacher_id TEXT NOT NULL,
            class_id TEXT NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            is_active INTEGER DEFAULT 1,
            remote_id TEXT,
            deleted INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        print(
          '[DatabaseHelper] Upgraded database to version 11: added announcements table',
        );
      } catch (e) {
        print('[DatabaseHelper] Error during DB upgrade v11: $e');
      }
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT NOT NULL UNIQUE,
        email TEXT,
        display_name TEXT,
        photo_url TEXT,
        provider TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        user_role TEXT DEFAULT 'teacher',
        linked_student_id INTEGER,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL UNIQUE,
        value TEXT NOT NULL,
        theme_primary_color INTEGER,
        theme_secondary_color INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id TEXT NOT NULL UNIQUE,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        middle_name TEXT,
        email TEXT,
        phone TEXT,
        gender TEXT,
        birth_date TEXT,
        address TEXT,
        photo_path TEXT,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        description TEXT,
        units INTEGER DEFAULT 3,
        is_archived INTEGER DEFAULT 0,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subject_id INTEGER NOT NULL,
        section TEXT NOT NULL,
        school_year TEXT NOT NULL,
        semester TEXT,
        schedule TEXT,
        room TEXT,
        is_archived INTEGER DEFAULT 0,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE class_students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        student_id INTEGER NOT NULL,
        enrolled_at TEXT NOT NULL,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
        FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
        UNIQUE(class_id, student_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE grading_periods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        order_num INTEGER NOT NULL,
        is_active INTEGER DEFAULT 0,
        is_locked INTEGER DEFAULT 0,
        start_date TEXT,
        end_date TEXT,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE grading_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        grading_period_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        weight REAL NOT NULL DEFAULT 0,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (grading_period_id) REFERENCES grading_periods(id) ON DELETE CASCADE,
        UNIQUE(grading_period_id, name)
      )
    ''');

    await db.execute('''
      CREATE TABLE grading_configurations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        grading_period_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        max_score REAL NOT NULL DEFAULT 100,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (grading_period_id) REFERENCES grading_periods(id) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES grading_categories(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE grading_assessments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        grading_period_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        max_score REAL NOT NULL DEFAULT 100,
        order_num INTEGER NOT NULL DEFAULT 0,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE,
        FOREIGN KEY (grading_period_id) REFERENCES grading_periods (id) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES grading_categories (id) ON DELETE CASCADE,
        UNIQUE(grading_period_id, category_id, name),
        CHECK (max_score > 0)
      )
    ''');

    await db.execute('''
      CREATE TABLE assessment_scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        assessment_id INTEGER NOT NULL,
        student_id INTEGER NOT NULL,
        score REAL NOT NULL DEFAULT 0,
        remarks TEXT,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        recorded_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assessment_id) REFERENCES grading_assessments (id) ON DELETE CASCADE,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        UNIQUE(assessment_id, student_id),
        CHECK (score >= 0)
      )
    ''');

    await db.execute('''
      CREATE TABLE grades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        class_id INTEGER NOT NULL,
        grading_period_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        score REAL NOT NULL DEFAULT 0,
        max_score REAL NOT NULL DEFAULT 100,
        remarks TEXT,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        recorded_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
        FOREIGN KEY (grading_period_id) REFERENCES grading_periods(id) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES grading_categories(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        class_id INTEGER NOT NULL,
        grading_period_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'present',
        remarks TEXT,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
        FOREIGN KEY (grading_period_id) REFERENCES grading_periods(id) ON DELETE CASCADE,
        UNIQUE(student_id, class_id, date)
      )
    ''');

    await db.execute('''
      CREATE TABLE interventions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        class_id INTEGER NOT NULL,
        grading_period_id INTEGER,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        intervention_date TEXT NOT NULL,
        follow_up_date TEXT,
        status TEXT DEFAULT 'open',
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE risk_flags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        class_id INTEGER NOT NULL,
        grading_period_id INTEGER NOT NULL,
        risk_level TEXT NOT NULL DEFAULT 'low',
        grade_score REAL,
        attendance_percentage REAL,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        flagged_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE lessons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        week_number INTEGER NOT NULL,
        title TEXT NOT NULL,
        pdf_path TEXT,
        content TEXT,
        objectives TEXT,
        refs TEXT,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE counseling_reasons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        teacher_uid TEXT NOT NULL,
        student_id TEXT NOT NULL,
        student_remote_id TEXT,
        class_remote_id TEXT NOT NULL,
        subject_code TEXT,
        reason TEXT NOT NULL,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE announcements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        teacher_id TEXT NOT NULL,
        class_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        remote_id TEXT,
        deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    final now = DateTime.now().toIso8601String();
    await db.insert('settings', {
      'key': 'teacher_name',
      'value': '',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('settings', {
      'key': 'school_name',
      'value': '',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('settings', {
      'key': 'pin_hash',
      'value': '',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('settings', {
      'key': 'grade_threshold',
      'value': '75',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('settings', {
      'key': 'attendance_threshold',
      'value': '80',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('settings', {
      'key': 'onboarding_complete',
      'value': 'false',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> seedSampleData() async {
    final db = await database;
    await _seedSampleData(db);
  }

  Future<void> _seedSampleData(Database db) async {
    final studentCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM students'),
        ) ??
        0;
    final classCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM classes'),
        ) ??
        0;

    if (studentCount > 0 || classCount > 0) {
      print('[DatabaseHelper] Seed skip: existing data detected');
      return;
    }

    final now = DateTime.now().toIso8601String();

    Future<int> ensureSubject({
      required String code,
      required String name,
      String? description,
    }) async {
      final existing = await db.query(
        'subjects',
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return existing.first['id'] as int;
      }
      return await db.insert('subjects', {
        'code': code,
        'name': name,
        'description': description ?? '',
        'units': 3,
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
      });
    }

    final subjectIds = <String, int>{
      'MATH7': await ensureSubject(
        code: 'MATH7',
        name: 'Mathematics 7',
        description: 'Number sense, algebraic reasoning, and problem solving.',
      ),
      'ENG7': await ensureSubject(
        code: 'ENG7',
        name: 'English 7',
        description: 'Reading comprehension, grammar, and writing skills.',
      ),
      'SCI7': await ensureSubject(
        code: 'SCI7',
        name: 'Science 7',
        description: 'Life science, earth science, and scientific inquiry.',
      ),
    };

    final students = [
      {
        'student_id': 'STD-001',
        'first_name': 'Miguel',
        'last_name': 'Santos',
        'gender': 'Male',
        'email': 'miguel.santos@classroom.edu',
      },
      {
        'student_id': 'STD-002',
        'first_name': 'Alyssa',
        'last_name': 'Rivera',
        'gender': 'Female',
        'email': 'alyssa.rivera@classroom.edu',
      },
      {
        'student_id': 'STD-003',
        'first_name': 'Jerome',
        'last_name': 'Villanueva',
        'gender': 'Male',
        'email': 'jerome.villanueva@classroom.edu',
      },
      {
        'student_id': 'STD-004',
        'first_name': 'Sophia',
        'last_name': 'Garcia',
        'gender': 'Female',
        'email': 'sophia.garcia@classroom.edu',
      },
      {
        'student_id': 'STD-005',
        'first_name': 'Lorenzo',
        'last_name': 'Navarro',
        'gender': 'Male',
        'email': 'lorenzo.navarro@classroom.edu',
      },
      {
        'student_id': 'STD-006',
        'first_name': 'Patricia',
        'last_name': 'Del Rosario',
        'gender': 'Female',
        'email': 'patricia.delrosario@classroom.edu',
      },
    ];

    final studentIds = <int>[];
    for (final student in students) {
      final id = await db.insert('students', {
        ...student,
        'middle_name': '',
        'phone': '',
        'birth_date': '',
        'address': '',
        'photo_path': '',
        'created_at': now,
        'updated_at': now,
      });
      studentIds.add(id);
    }

    final classes = [
      {
        'subject_code': 'MATH7',
        'section': 'Grade 7 - St. Augustine',
        'schedule': 'Mon/Wed/Fri 8:00-9:00 AM',
        'room': 'Room 201',
      },
      {
        'subject_code': 'ENG7',
        'section': 'Grade 7 - St. Benedict',
        'schedule': 'Mon/Wed/Fri 9:00-10:00 AM',
        'room': 'Room 202',
      },
      {
        'subject_code': 'SCI7',
        'section': 'Grade 7 - St. Catherine',
        'schedule': 'Tue/Thu 10:00-11:30 AM',
        'room': 'Science Lab',
      },
    ];

    final classIds = <int>[];
    for (final cls in classes) {
      final classId = await db.insert('classes', {
        'subject_id': subjectIds[cls['subject_code']]!,
        'section': cls['section'],
        'school_year': '2024-2025',
        'semester': '1st',
        'schedule': cls['schedule'],
        'room': cls['room'],
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
      });
      classIds.add(classId);
    }

    final enrollments = <Map<String, int>>[];
    for (var i = 0; i < studentIds.length; i++) {
      final classId = classIds[i % classIds.length];
      enrollments.add({'class_id': classId, 'student_id': studentIds[i]});
    }

    for (final enrollment in enrollments) {
      await db.insert('class_students', {
        'class_id': enrollment['class_id'],
        'student_id': enrollment['student_id'],
        'enrolled_at': now,
      });
    }

    print('[DatabaseHelper] Seeded sample students and classes');
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('settings', {
      'key': key,
      'value': value,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Clear selected tables from local database
  /// Useful for resetting data before syncing from cloud
  Future<void> clearSelectedTables(List<String> tableNames) async {
    final db = await database;
    print('[DatabaseHelper] Clearing ${tableNames.length} tables: $tableNames');

    for (final tableName in tableNames) {
      try {
        final count = await db.delete(tableName);
        print('[DatabaseHelper] Cleared $count rows from $tableName');
      } catch (e) {
        print('[DatabaseHelper] Error clearing table $tableName: $e');
        rethrow;
      }
    }

    print('[DatabaseHelper] Successfully cleared all selected tables');
  }

  /// Reset the entire local database
  /// Deletes the database file and recreates it from scratch
  Future<void> resetDatabase() async {
    try {
      print('[DatabaseHelper] Starting database reset');

      // Close existing database connection
      await closeDB();

      // Delete the database file
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'gradebook.db');
      await deleteDatabase(path);
      print('[DatabaseHelper] Deleted database file: $path');

      // Reset the database instance to force recreation
      _database = null;

      // Initialize fresh database
      await database;
      print('[DatabaseHelper] Database reset completed successfully');
    } catch (e) {
      print('[DatabaseHelper] Error during database reset: $e');
      rethrow;
    }
  }

  Future<void> closeDB() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
