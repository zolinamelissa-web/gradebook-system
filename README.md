# Gradebook

A comprehensive Flutter gradebook application for managing classes, students, attendance, grades, and lessons.

> **Author:** Melissa Zolina  
> **Platform:** Flutter (iOS, Android, Web, Desktop)  
> **Repository:** https://github.com/psworld143/gradebook.git

---

## Table of Contents

- [Features](#features)
- [Screens & Modules](#screens--modules)
- [Architecture](#architecture)
- [Setup & Installation](#setup--installation)
- [Firebase Configuration](#firebase-configuration)
- [Running the App](#running-the-app)
- [Project Structure](#project-structure)
- [Key Dependencies](#key-dependencies)
- [UI Guidelines](#ui-guidelines)
- [Contributing](#contributing)
- [License](#license)

---

## Features

### Core
- **Class Management:** Create, edit, archive classes; manage sections, schedules, rooms.
- **Student Management:** Enroll students, view profiles, manage student records.
- **Subject Management:** Subject codes, names, and descriptions displayed consistently.
- **Grading Periods:** Define active grading periods per class.
- **Attendance:** Track daily attendance per student with Present/Absent/Late.
- **Grades:** Record and view grades per grading period.
- **Lessons:** Create and manage lesson content per class.
- **At-Risk Analytics:** Identify students needing intervention.
- **Reports & Analytics:** Summary views and statistics.

### UI/UX
- **WaveHeader:** Consistent branded header with gradient, chips, and subtitle support.
- **Theme System:** Light/dark theme support via `ThemeProvider`.
- **Responsive Layouts:** Adaptive grids and lists.
- **Consistent Tables:** Uniform table styling across all pages.
- **Print/Console Logging:** API responses and key actions logged to console.

---

## Screens & Modules

| Module | Key Screens | Description |
|--------|-------------|-------------|
| **Auth** | `AuthScreen`, `LoginScreen`, `SetupPinScreen` | Secure login and PIN setup. |
| **Home** | `HomeScreen` | Dashboard and navigation hub. |
| **Classes** | `ClassListScreen`, `ClassDetailScreen`, `ClassFormScreen`, `EnrollStudentsScreen` | Class CRUD, student enrollment. |
| **Attendance** | `AttendanceScreen` | Daily attendance tracking per class. |
| **Grades** | `GradesScreen`, `StudentRecordsScreen` | Grade entry and student grade records. |
| **Grading** | `GradingPeriodsScreen`, `GradingCategoriesScreen` | Grading period/category management. |
| **Lessons** | `LessonsListScreen`, `LessonDetailScreen`, `LessonFormScreen` | Lesson content management. |
| **Students** | `StudentListScreen`, `StudentFormScreen`, `StudentProfileScreen` | Student CRUD and profiles. |
| **Analytics** | `AnalyticsScreen` | Reports and stats. |
| **Risk** | `RiskScreen` | At-risk student identification. |
| **Settings** | `SettingsScreen`, `ClearDataDialog`, `SyncModal` | App settings, data sync, and reset. |

---

## Architecture

- **Provider + BLoC-like pattern:** State management via `Provider` and custom repositories.
- **Repository Layer:** `*_repository.dart` files abstract data sources.
- **Firebase Backend:** Firestore for data, Firebase Auth for authentication.
- **Feature-First Folder Structure:** `lib/presentation/` grouped by feature.
- **Shared Widgets:** Reusable components in `lib/core/widgets/`.
- **Models:** `lib/data/models/` define data structures.
- **Theme:** Centralized `AppTheme` and `ThemeProvider`.

---

## Setup & Installation

### Prerequisites
- Flutter SDK (>=3.0)
- Dart SDK
- Firebase project (Firestore, Auth)
- Git

### Clone
```bash
git clone https://github.com/psworld143/gradebook.git
cd grade_book
```

### Install dependencies
```bash
flutter pub get
```

### Firebase Configuration
1. Create a Firebase project at [Firebase Console](https://console.firebase.google.com/).
2. Enable **Firestore Database** and **Authentication**.
3. Download platform-specific config files and place them:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`
   - Web: `web/firebase-config.js` (update `index.html` if needed)
4. Run:
   ```bash
   flutterfire configure
   ```

### Environment (optional)
If you use environment variables for keys, create `.env` in the project root (add to `.gitignore`).

---

## Running the App

```bash
# Run on connected device/emulator
flutter run

# Run on specific platform
flutter run -d chrome
flutter run -d macos
flutter run -d ios
```

---

## Project Structure

```
lib/
├── core/
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── theme_provider.dart
│   └── widgets/
│       └── wave_header.dart
├── data/
│   ├── models/
│   └── repositories/
├── presentation/
│   ├── auth/
│   ├── classes/
│   ├── attendance/
│   ├── grades/
│   ├── grading/
│   ├── lessons/
│   ├── students/
│   ├── analytics/
│   ├── risk/
│   ├── settings/
│   └── home/
└── main.dart
```

---

## Key Dependencies

- `flutter/material.dart`: UI framework
- `provider`: State management
- `firebase_core`, `firebase_auth`, `cloud_firestore`: Backend
- `intl`: Date formatting
- `path`, `path_provider`: File paths

---

## UI Guidelines

- **Tables:** Use consistent styling (borders, padding, colors) across all pages.
- **Headers:** Use `WaveHeader` for screen titles; subtitle shows subject description when available.
- **Colors:** Define in `AppTheme`; reuse semantic colors (`primary`, `success`, `warning`, `danger`).
- **Logging:** Always `print()` API responses and key actions for debugging.
- **Responsive:** Prefer `GridView.count`, `ListView`, `Wrap` for adaptive layouts.

---

## Contributing

1. Fork the repo.
2. Create a feature branch: `git checkout -b feature-name`.
3. Follow the existing code style and architecture.
4. Add/update tests if applicable.
5. Commit with a clear message.
6. Push and open a pull request.

---

## License

This project is licensed under the MIT License — see the LICENSE file for details.

---

## Acknowledgments

- Flutter team for the amazing framework.
- Firebase for backend services.
- All contributors and testers.
