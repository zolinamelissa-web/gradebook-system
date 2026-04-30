import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../presentation/auth/login_screen.dart';

class AuthService {
  static Future<void> signOutAndGoToLogin(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();

      if (!context.mounted) return;

      // Navigate to Login and clear back stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[AuthService] Sign out error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
      }
    }
  }
}
