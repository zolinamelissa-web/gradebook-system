import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../database/database_helper.dart';
import '../models/announcement_model.dart';
import '../../core/services/auto_sync_service.dart';

class AnnouncementRepository {
  static final AnnouncementRepository instance = AnnouncementRepository._init();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;

  AnnouncementRepository._init();

  /// Create a new announcement in Firebase
  Future<String> createAnnouncement({
    required String teacherId,
    required String classId,
    required String title,
    required String content,
  }) async {
    if (kIsWeb) {
      return await _createWebAnnouncement(
        teacherId: teacherId,
        classId: classId,
        title: title,
        content: content,
      );
    }

    try {
      print(
        '[AnnouncementRepository] Creating announcement for class: $classId',
      );

      final announcement = Announcement(
        teacherId: teacherId,
        classId: classId,
        title: title,
        content: content,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save to Firebase
      final docRef = await _firestore
          .collection('announcements')
          .add(announcement.toFirebaseMap());

      print(
        '[AnnouncementRepository] Announcement created in Firebase with ID: ${docRef.id}',
      );

      // Save to local database with remote ID
      await _saveAnnouncementToLocal(
        announcement.copyWith(remoteId: docRef.id),
      );

      return docRef.id;
    } catch (e) {
      print('[AnnouncementRepository] Error creating announcement: $e');
      rethrow;
    }
  }

  Future<String> _createWebAnnouncement({
    required String teacherId,
    required String classId,
    required String title,
    required String content,
  }) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) throw Exception('No Firebase user');

    try {
      print(
        '[AnnouncementRepository] Creating web announcement for class: $classId',
      );

      final announcement = Announcement(
        teacherId: teacherId,
        classId: classId,
        title: title,
        content: content,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save to Firebase
      final docRef = await _firestore
          .collection('users/${firebaseUser.uid}/announcements')
          .add(announcement.toFirebaseMap());

      print(
        '[AnnouncementRepository] Web announcement created with ID: ${docRef.id}',
      );

      return docRef.id;
    } catch (e) {
      print('[AnnouncementRepository] Error creating web announcement: $e');
      rethrow;
    }
  }

  /// Update an existing announcement in Firebase
  Future<void> updateAnnouncement({
    required String announcementId,
    required String title,
    required String content,
  }) async {
    try {
      print('[AnnouncementRepository] Updating announcement: $announcementId');

      final updateData = {
        'title': title,
        'content': content,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      // Update in Firebase
      await _firestore
          .collection('announcements')
          .doc(announcementId)
          .update(updateData);

      print('[AnnouncementRepository] Announcement updated in Firebase');

      // Update local database
      await _updateAnnouncementInLocal(announcementId, title, content);
    } catch (e) {
      print('[AnnouncementRepository] Error updating announcement: $e');
      rethrow;
    }
  }

  /// Delete an announcement from Firebase
  Future<void> deleteAnnouncement(String announcementId) async {
    try {
      print('[AnnouncementRepository] Deleting announcement: $announcementId');

      // Delete from Firebase
      await _firestore.collection('announcements').doc(announcementId).delete();

      print('[AnnouncementRepository] Announcement deleted from Firebase');

      // Mark as deleted in local database
      await _deleteAnnouncementInLocal(announcementId);
    } catch (e) {
      print('[AnnouncementRepository] Error deleting announcement: $e');
      rethrow;
    }
  }

  /// Get all announcements for a specific class from Firebase
  Future<List<Announcement>> getAnnouncementsForClass(String classId) async {
    try {
      print(
        '[AnnouncementRepository] Fetching announcements for class: $classId',
      );

      final snapshot = await _firestore
          .collection('announcements')
          .where('classId', isEqualTo: classId)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      final announcements = snapshot.docs.map((doc) {
        return Announcement.fromFirebaseMap(doc.id, doc.data());
      }).toList();

      print(
        '[AnnouncementRepository] Found ${announcements.length} announcements',
      );

      // Cache announcements in local database
      await _cacheAnnouncementsInLocal(announcements);

      return announcements;
    } catch (e) {
      print('[AnnouncementRepository] Error fetching announcements: $e');
      // Fallback to local database if Firebase fails
      return await _getAnnouncementsFromLocal(classId);
    }
  }

  /// Get a single announcement by ID from Firebase
  Future<Announcement?> getAnnouncementById(String announcementId) async {
    try {
      print('[AnnouncementRepository] Fetching announcement: $announcementId');

      final doc = await _firestore
          .collection('announcements')
          .doc(announcementId)
          .get();

      if (!doc.exists) {
        print('[AnnouncementRepository] Announcement not found');
        return null;
      }

      final announcement = Announcement.fromFirebaseMap(doc.id, doc.data()!);

      // Cache in local database
      await _saveAnnouncementToLocal(announcement);

      return announcement;
    } catch (e) {
      print('[AnnouncementRepository] Error fetching announcement: $e');
      // Fallback to local database
      return await _getAnnouncementFromLocal(announcementId);
    }
  }

  // Local database methods for caching and offline support

  Future<void> _saveAnnouncementToLocal(Announcement announcement) async {
    try {
      final db = await _db.database;
      final map = announcement.toMap();

      // Check if announcement already exists
      final existing = await db.query(
        'announcements',
        where: 'remote_id = ?',
        whereArgs: [announcement.remoteId],
      );

      if (existing.isNotEmpty) {
        await db.update(
          'announcements',
          map,
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await db.insert('announcements', map);
      }
    } catch (e) {
      print('[AnnouncementRepository] Error saving announcement to local: $e');
    }
  }

  Future<void> _updateAnnouncementInLocal(
    String remoteId,
    String title,
    String content,
  ) async {
    try {
      final db = await _db.database;
      await db.update(
        'announcements',
        {
          'title': title,
          'content': content,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'remote_id = ?',
        whereArgs: [remoteId],
      );
    } catch (e) {
      print(
        '[AnnouncementRepository] Error updating announcement in local: $e',
      );
    }
  }

  Future<void> _deleteAnnouncementInLocal(String remoteId) async {
    try {
      final db = await _db.database;
      await db.update(
        'announcements',
        {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'remote_id = ?',
        whereArgs: [remoteId],
      );
    } catch (e) {
      print(
        '[AnnouncementRepository] Error deleting announcement in local: $e',
      );
    }
  }

  Future<void> _cacheAnnouncementsInLocal(
    List<Announcement> announcements,
  ) async {
    try {
      final db = await _db.database;

      for (final announcement in announcements) {
        await _saveAnnouncementToLocal(announcement);
      }
    } catch (e) {
      print(
        '[AnnouncementRepository] Error caching announcements in local: $e',
      );
    }
  }

  Future<List<Announcement>> _getAnnouncementsFromLocal(String classId) async {
    try {
      final db = await _db.database;
      final maps = await db.query(
        'announcements',
        where: 'class_id = ? AND is_active = 1',
        whereArgs: [classId],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => Announcement.fromMap(map)).toList();
    } catch (e) {
      print(
        '[AnnouncementRepository] Error fetching announcements from local: $e',
      );
      return [];
    }
  }

  Future<Announcement?> _getAnnouncementFromLocal(String remoteId) async {
    try {
      final db = await _db.database;
      final maps = await db.query(
        'announcements',
        where: 'remote_id = ? AND is_active = 1',
        whereArgs: [remoteId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return Announcement.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      print(
        '[AnnouncementRepository] Error fetching announcement from local: $e',
      );
      return null;
    }
  }
}
