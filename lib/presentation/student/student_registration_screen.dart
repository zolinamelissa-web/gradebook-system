import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_icons.dart';
import '../../core/widgets/wave_header.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/student_account_repository.dart';
import '../auth/setup_pin_screen.dart';

class StudentRegistrationScreen extends StatefulWidget {
  const StudentRegistrationScreen({super.key});

  @override
  State<StudentRegistrationScreen> createState() =>
      _StudentRegistrationScreenState();
}

class _StudentRegistrationScreenState extends State<StudentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _studentIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  StudentAccountInfo? _studentInfo;
  bool _studentIdVerified = false;

  @override
  void dispose() {
    _studentIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _verifyStudentId() async {
    final studentId = _studentIdController.text.trim();
    if (studentId.isEmpty) {
      _showError('Please enter your Student ID');
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('[StudentRegistration] Verifying Student ID: $studentId');
      final studentInfo = await StudentAccountRepository.checkStudentIdExists(
        studentId,
      );

      if (studentInfo == null) {
        _showError('Student ID not found. Please contact your teacher.');
        setState(() => _studentIdVerified = false);
      } else if (studentInfo.isRegistered) {
        _showError(
          'This Student ID is already registered. Please login instead.',
        );
        setState(() => _studentIdVerified = false);
      } else {
        setState(() {
          _studentInfo = studentInfo;
          _studentIdVerified = true;
          _displayNameController.text = studentInfo.displayName;
        });
        _showSuccess('Student ID verified! Please complete your registration.');
      }
      print(
        '[StudentRegistration] Student ID verification result studentId=$studentId verified=$_studentIdVerified registered=${studentInfo?.isRegistered}',
      );
    } on FirebaseException catch (e) {
      print('[StudentRegistration] Student ID verification Firebase error: $e');
      if (e.code == 'unavailable' || e.code == 'network-request-failed') {
        _showError(
          'Unable to verify Student ID. Please check your internet connection and try again.',
        );
      } else {
        _showError('Error verifying Student ID: ${e.message ?? e.code}');
      }
      setState(() => _studentIdVerified = false);
    } catch (e) {
      print('[StudentRegistration] Student ID verification error: $e');
      _showError('Error verifying Student ID: $e');
      setState(() => _studentIdVerified = false);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_studentIdVerified) {
      _showError('Please verify your Student ID first');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authRepo = AuthRepository();
      final user = await authRepo.registerStudentAccount(
        studentId: _studentIdController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
      );

      if (user != null) {
        final verifiedStudentId = _studentIdController.text.trim();
        final verifiedName = _displayNameController.text.trim().isEmpty
            ? (_studentInfo?.displayName ?? '')
            : _displayNameController.text.trim();

        if (kIsWeb) {
          _showSuccess('Registration successful! Setup your PIN...');
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => SetupPinScreen(
                  isOnboarding: true,
                  isStudent: true,
                  prefilledStudentId: verifiedStudentId,
                  prefilledName: verifiedName,
                  onComplete: () {
                    Navigator.of(
                      context,
                    ).pushReplacementNamed('/student-dashboard');
                  },
                ),
              ),
            );
          }
          return;
        }

        await DatabaseHelper.instance.setSetting(
          'student_id',
          verifiedStudentId,
        );
        if (verifiedName.isNotEmpty) {
          await DatabaseHelper.instance.setSetting(
            'student_name',
            verifiedName,
          );
        }

        _showSuccess('Registration successful! Setup your PIN...');

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SetupPinScreen(
                isOnboarding: true,
                isStudent: true,
                prefilledStudentId: verifiedStudentId,
                prefilledName: verifiedName,
                onComplete: () {
                  Navigator.of(
                    context,
                  ).pushReplacementNamed('/student-dashboard');
                },
              ),
            ),
          );
        }
      } else {
        _showError('Registration failed. Please try again.');
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      String message = 'Registration failed';
      switch (e.code) {
        case 'weak-password':
          message = 'Password is too weak. Please use a stronger password.';
          break;
        case 'email-already-in-use':
          message =
              'This email is already registered. Please use a different email.';
          break;
        case 'invalid-email':
          message = 'Invalid email address.';
          break;
        default:
          message = 'Registration failed: ${e.message}';
      }
      _showError(message);
    } catch (e) {
      _showError('Registration failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const WaveHeader(
              title: 'Student Registration',
              subtitle: 'Create your account to view your records',
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Student ID Verification Section
                    _buildSectionTitle('Student Information'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _studentIdController,
                            decoration: InputDecoration(
                              labelText: 'Student ID',
                              hintText: 'e.g., 2021-12345',
                              prefixIcon: Icon(PlatformIcons.badge),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              enabled: !_isLoading,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your Student ID';
                              }
                              return null;
                            },
                            enabled: !_isLoading && !_studentIdVerified,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _isLoading || _studentIdVerified
                              ? null
                              : _verifyStudentId,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text('Verify'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Student Info Display (after verification)
                    if (_studentInfo != null && _studentIdVerified) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  PlatformIcons.verified,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Student Verified',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Name: ${_studentInfo!.fullName}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            if (_studentInfo!.email != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'School Email: ${_studentInfo!.email}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Account Creation Section
                    if (_studentIdVerified) ...[
                      _buildSectionTitle('Create Account'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'Enter your email',
                          prefixIcon: Icon(PlatformIcons.email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!RegExp(
                            r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                          ).hasMatch(value)) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _displayNameController,
                        decoration: InputDecoration(
                          labelText: 'Display Name (Optional)',
                          hintText: 'How you want to be addressed',
                          prefixIcon: Icon(PlatformIcons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: 'Create a strong password',
                          prefixIcon: Icon(PlatformIcons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? PlatformIcons.eye
                                  : PlatformIcons.eyeSlash,
                            ),
                            onPressed: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          hintText: 'Re-enter your password',
                          prefixIcon: Icon(PlatformIcons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? PlatformIcons.eye
                                  : PlatformIcons.eyeSlash,
                            ),
                            onPressed: () {
                              setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              );
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        obscureText: _obscureConfirmPassword,
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Creating Account...'),
                                  ],
                                )
                              : const Text(
                                  'Create Account',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],

                    // Login Link
                    if (_studentIdVerified) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Already have an account?',
                            style: TextStyle(color: Colors.grey),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pushReplacementNamed('/student-login');
                            },
                            child: Text(
                              'Sign In',
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}
