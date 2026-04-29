📘 SYSTEM REQUIREMENTS SPECIFICATION (SRS)
GradeBook Mobile Application

Platform: Flutter
Database: SQFLite
User Type: Single User (Teacher Only)

1. INTRODUCTION
1.1 Purpose

The purpose of this system is to develop a mobile GradeBook application that allows a teacher to:

Record student information

Configure grading periods

Configure grading percentages

Compute grades automatically

Monitor attendance

Identify at-risk students

View analytics dashboard

The system is offline-first and uses local SQLite database.

2. SYSTEM OVERVIEW

The application is a standalone mobile system intended for a single teacher user only.

Architecture:

Flutter UI
⬇
Business Logic
⬇
SQFLite Database

No cloud login required.

3. USER CHARACTERISTICS
👩‍🏫 Teacher (Only User)

The teacher shall:

Manage students

Configure grading system

Input grades

Monitor attendance

View analytics

Record interventions

No multi-user support for now.

4. FUNCTIONAL REQUIREMENTS
4.1 Authentication (Optional / Simple Local Login)

Since single user only:

FR1: The system may allow a local password setup.

FR2: The teacher shall log in using local credentials.

FR3: The system shall allow password change.

FR4: Credentials shall be stored securely (hashed).

(If you want ultra simple, pwede rin remove login entirely.)

4.2 Student Management

FR5: Add student.

FR6: Edit student information.

FR7: Delete student.

FR8: Assign student to class.

FR9: View student academic profile.

FR10: Prevent duplicate student ID.

4.3 Subject and Class Management

FR11: Create subject.

FR12: Create class section.

FR13: Enroll students to class.

FR14: Archive class.

FR15: View class list.

4.4 Grading Period Management (Configurable)

FR16: Create grading period (Prelim, Midterm, Finals, etc.).

FR17: Edit grading period.

FR18: Activate grading period.

FR19: Lock grading period to prevent changes.

FR20: View grades per grading period.

FR21: Support multiple grading periods per subject.

4.5 Configurable Grading System (Updated – Required Feature)
Category Setup

FR22: Create grading category (Quiz, Exam, Project, Activity).

FR23: Assign percentage weight per category.

FR24: Edit category percentage before locking.

FR25: System shall validate total percentage = 100%.

FR26: Prevent saving if total ≠ 100%.

FR27: Display total percentage in real-time.

FR28: Allow different grading setup per subject.

Per Grading Period Configuration

FR29: Allow different grading percentage per grading period.

FR30: Auto-recompute grades when configuration changes.

FR31: Lock grading configuration when grading period is finalized.

4.6 Grade Recording and Automatic Computation

FR32: Input raw score per student.

FR33: Validate score ≤ maximum score.

FR34: Compute category average automatically.

FR35: Compute weighted grading period grade.

FR36: Compute cumulative grade.

FR37: Generate final grade.

FR38: Auto-update grades when percentage changes.

FR39: Prevent editing if grading period is locked.

Formula:

Period Grade =
(Category Average × Category Weight)

4.7 Attendance Monitoring

FR40: Record daily attendance.

FR41: Mark Present, Absent, Late.

FR42: Compute attendance percentage.

FR43: View attendance summary.

FR44: Display attendance per grading period.

4.8 At-Risk Student Identification

Based on academic monitoring principles 

Documentation

FR45: Allow teacher to set grade threshold.

FR46: Allow teacher to set attendance threshold.

FR47: Automatically flag students below threshold.

FR48: Display risk level indicator.

FR49: Auto-update risk status when grades change.

FR50: Show number of at-risk students per class.

4.9 Analytics Dashboard

FR51: Show class average per grading period.

FR52: Show grade distribution chart.

FR53: Show attendance trend.

FR54: Compare grading periods.

FR55: Display top performing students.

FR56: Display lowest performing students.

FR57: Display at-risk summary.

4.10 Intervention Notes

FR58: Add intervention note per student.

FR59: Record intervention date.

FR60: View intervention history.

FR61: Link intervention to grading period.

4.11 Data Management

FR62: Timestamp all grade changes.

FR63: Prevent duplicate grading categories.

FR64: Prevent negative scores.

FR65: Auto-save data locally.

FR66: Backup local database (export feature).

FR67: Restore backup file.

5. NON-FUNCTIONAL REQUIREMENTS

Aligned with ISO/IEC 25010

5.1 Functional Suitability

Accurate grade computation

Accurate attendance computation

Accurate risk detection

5.2 Performance

Grade computation < 1 second

Dashboard load < 3 seconds

5.3 Usability

Simple UI

Minimal navigation

Clear grading configuration interface

5.4 Reliability

No data loss

Local storage integrity

Crash recovery support

5.5 Security

Local password protection (optional)

Encrypted database recommended

No external data sharing

5.6 Maintainability

Modular Flutter structure

Clean architecture pattern

5.7 Portability

Android 8.0+

iOS supported via Flutter

6. DATABASE TABLES (SQFLite)

Required Tables:

students

subjects

classes

class_students

grading_periods

grading_categories

grading_configurations

grades

attendance

interventions

risk_flags

settings

(Removed users table since single user only.)

7. HARDWARE REQUIREMENTS

Development:

8GB RAM PC

Android Studio

Flutter SDK

Deployment:

Android device (3GB RAM recommended)

📌 FINAL SUMMARY (Single User Version)

The GradeBook Mobile Application shall:

✔ Be used by one teacher only
✔ Allow configurable grading percentages
✔ Allow configurable grading periods
✔ Automatically compute grades
✔ Monitor attendance
✔ Identify at-risk students
✔ Provide analytics dashboard
✔ Work completely offline
✔ Follow ISO 25010 quality standards