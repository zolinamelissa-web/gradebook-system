import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../data/database/database_helper.dart';

class ThemeProvider extends ChangeNotifier {
  Color _primaryColor = const Color(0xFF1565C0);
  Color _secondaryColor = const Color(0xFF42A5F5);
  bool _isLoading = true;

  Color get primaryColor => _primaryColor;
  Color get secondaryColor => _secondaryColor;
  bool get isLoading => _isLoading;

  // Predefined color schemes
  static const Map<String, Map<String, Color>> colorSchemes = {
    'Blue': {'primary': Color(0xFF1565C0), 'secondary': Color(0xFF42A5F5)},
    'Purple': {'primary': Color(0xFF7C3AED), 'secondary': Color(0xFFA78BFA)},
    'Green': {'primary': Color(0xFF059669), 'secondary': Color(0xFF10B981)},
    'Orange': {'primary': Color(0xFFEA580C), 'secondary': Color(0xFFFB923C)},
    'Pink': {'primary': Color(0xFFDB2777), 'secondary': Color(0xFFF472B6)},
    'Teal': {'primary': Color(0xFF0F766E), 'secondary': Color(0xFF14B8A6)},
    'Indigo': {'primary': Color(0xFF4F46E5), 'secondary': Color(0xFF818CF8)},
    'Red': {'primary': Color(0xFFDC2626), 'secondary': Color(0xFFEF4444)},
  };

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      // Only try to load from database on non-web platforms
      if (!kIsWeb) {
        final db = await DatabaseHelper.instance.database;
        final result = await db.query(
          'settings',
          columns: ['theme_primary_color', 'theme_secondary_color'],
          limit: 1,
        );

        if (result.isNotEmpty) {
          final row = result.first;
          if (row['theme_primary_color'] != null) {
            _primaryColor = Color(row['theme_primary_color'] as int);
          }
          if (row['theme_secondary_color'] != null) {
            _secondaryColor = Color(row['theme_secondary_color'] as int);
          }
        }
      }
    } catch (e) {
      print('[ThemeProvider] Error loading theme: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setColors(Color primary, Color secondary) async {
    _primaryColor = primary;
    _secondaryColor = secondary;
    notifyListeners();

    try {
      final db = await DatabaseHelper.instance.database;
      await db.update('settings', {
        'theme_primary_color': primary.value,
        'theme_secondary_color': secondary.value,
      });
      print('[ThemeProvider] Theme colors saved');
    } catch (e) {
      print('[ThemeProvider] Error saving theme: $e');
    }
  }

  Future<void> setColorScheme(String schemeName) async {
    final scheme = colorSchemes[schemeName];
    if (scheme != null) {
      await setColors(scheme['primary']!, scheme['secondary']!);
    }
  }

  String getCurrentSchemeName() {
    for (final entry in colorSchemes.entries) {
      if (entry.value['primary'] == _primaryColor &&
          entry.value['secondary'] == _secondaryColor) {
        return entry.key;
      }
    }
    return 'Custom';
  }

  List<Color> getGradientColors() {
    return [_primaryColor, _secondaryColor];
  }

  ThemeData getThemeData() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Poppins',
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryColor,
        primary: _primaryColor,
        secondary: _secondaryColor,
      ),
      primaryColor: _primaryColor,
      scaffoldBackgroundColor: const Color(0xFFF4F6FB),
      appBarTheme: AppBarTheme(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _primaryColor, width: 2),
        ),
      ),
    );
  }
}
