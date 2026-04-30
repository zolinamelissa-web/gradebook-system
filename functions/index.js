/**
 * Firebase Cloud Functions for Grade Book App
 *
 * This file contains Cloud Functions for the Grade Book application,
 * including student password reset functionality.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin SDK
admin.initializeApp();

const findStudentAccountByEmail = async (email) => {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!normalizedEmail) return null;

  const db = admin.firestore();
  const studentAccounts = await db.collection("student_accounts").get();

  for (const studentDoc of studentAccounts.docs) {
    const legacyData = studentDoc.data() || {};
    const legacyEmail = String(legacyData.email || "").trim().toLowerCase();
    const legacyTeacherUid = String(legacyData.teacher_uid || "").trim();
    const legacyStudentRemoteId = String(
        legacyData.student_remote_id || "",
    ).trim();
    const legacyRegistered = legacyData.is_registered === 1 ||
        legacyData.is_registered === true;

    if (legacyEmail === normalizedEmail &&
        legacyRegistered &&
        legacyTeacherUid &&
        legacyStudentRemoteId) {
      return {
        studentId: studentDoc.id,
        teacherUid: legacyTeacherUid,
        studentRemoteId: legacyStudentRemoteId,
      };
    }

    const teachersSnap = await studentDoc.ref.collection("teachers").get();
    for (const teacherDoc of teachersSnap.docs) {
      const teacherData = teacherDoc.data() || {};
      const teacherEmail = String(teacherData.email || "").trim().toLowerCase();
      const teacherUid = String(
          teacherData.teacher_uid || teacherDoc.id || "",
      ).trim();
      const studentRemoteId = String(
          teacherData.student_remote_id || "",
      ).trim();
      const isRegistered = teacherData.is_registered === 1 ||
          teacherData.is_registered === true;

      if (teacherEmail === normalizedEmail &&
          isRegistered &&
          teacherUid &&
          studentRemoteId) {
        return {
          studentId: studentDoc.id,
          teacherUid: teacherUid,
          studentRemoteId: studentRemoteId,
        };
      }
    }
  }

  return null;
};

/**
 * Reset student password to temporary password "TempPassword123"
 * This function can only be called by authenticated users (teachers)
 *
 * @param {Object} data - Contains the student's email
 * @param {Object} context - Authentication context
 * @returns {Object} Success status
 */
exports.resetStudentPassword = functions.https.onCall(
    async (request, response) => {
      const data = request && request.data ? request.data : request;
      const auth = request && request.auth ? request.auth :
        (response && response.auth ? response.auth : null);

      console.log(
          `[resetStudentPassword] authPresent=${!!auth} ` +
          `uid=${auth && auth.uid ? auth.uid : "null"}`,
      );

      if (!auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Must be authenticated to reset student password",
        );
      }

      const email = data.email;

      // Validate email parameter
      if (!email || typeof email !== "string") {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Email is required and must be a string",
        );
      }

      try {
        // Get the user by email
        const user = await admin.auth().getUserByEmail(email);

        // Update the user's password
        await admin.auth().updateUser(user.uid, {
          password: "TempPassword123",
        });

        const msg = `Password reset successful for user: ${email}`;
        console.log(msg);

        return {
          success: true,
          message: "Password reset successfully",
        };
      } catch (error) {
        console.error("Error resetting password:", error);

        if (error.code === "auth/user-not-found") {
          const studentAccount = await findStudentAccountByEmail(email);
          console.log(
              `[resetStudentPassword] lookup studentAccount=` +
              `${JSON.stringify(studentAccount)}`,
          );

          if (!studentAccount) {
            throw new functions.https.HttpsError(
                "not-found",
                "No user found with this email address",
            );
          }

          const createdUser = await admin.auth().createUser({
            email: email,
            password: "TempPassword123",
          });

          const now = new Date().toISOString();
          await admin.firestore()
              .collection("student_accounts")
              .doc(studentAccount.studentId)
              .set({
                teacher_uid: studentAccount.teacherUid,
                student_remote_id: studentAccount.studentRemoteId,
                firebase_uid: createdUser.uid,
                email: email,
                is_registered: 1,
                updated_at: now,
              }, {merge: true});

          await admin.firestore()
              .collection("student_accounts")
              .doc(studentAccount.studentId)
              .collection("teachers")
              .doc(studentAccount.teacherUid)
              .set({
                teacher_uid: studentAccount.teacherUid,
                student_remote_id: studentAccount.studentRemoteId,
                firebase_uid: createdUser.uid,
                email: email,
                is_registered: 1,
                updated_at: now,
              }, {merge: true});

          const result = {
            success: true,
            message: "Missing student auth account created and password reset",
            created: true,
          };
          console.log(
              `[resetStudentPassword] API Returned message: ${result.message}`,
          );
          return result;
        }

        throw new functions.https.HttpsError(
            "internal",
            `Failed to reset password: ${error.message}`,
        );
      }
    },
);

/**
 * Migrate student emails from student_accounts to students collection
 * This fixes existing students who signed up before the email sync fix
 *
 * @param {Object} data - Empty object (no parameters needed)
 * @param {Object} context - Authentication context
 * @returns {Object} Migration results
 */
exports.migrateStudentEmails = functions.https.onCall(
    async (request, response) => {
      const auth = request && request.auth ? request.auth :
        (response && response.auth ? response.auth : null);

      console.log(
          `[migrateStudentEmails] authPresent=${!!auth} ` +
          `uid=${auth && auth.uid ? auth.uid : "null"}`,
      );

      const db = admin.firestore();
      let updated = 0;
      let skipped = 0;
      let errors = 0;

      try {
        console.log("Starting student email migration...");

        // Get all student_accounts documents
        const studentAccountsSnapshot = await db
            .collection("student_accounts")
            .get();

        for (const studentDoc of studentAccountsSnapshot.docs) {
          const studentId = studentDoc.id;

          // Get all teacher links for this student
          const teachersSnapshot = await studentDoc.ref
              .collection("teachers")
              .get();

          for (const teacherDoc of teachersSnapshot.docs) {
            const teacherData = teacherDoc.data();
            const teacherUid = teacherData.teacher_uid;
            const email = teacherData.email;
            const studentRemoteId = teacherData.student_remote_id;

            // Skip if no email or no student_remote_id
            if (!email || !studentRemoteId) {
              skipped++;
              continue;
            }

            try {
              // Update the student document in students collection
              await db
                  .collection(`users/${teacherUid}/students`)
                  .doc(studentRemoteId)
                  .set({
                    email: email,
                    updated_at: admin.firestore.Timestamp.now(),
                  }, {merge: true});

              console.log(
                  `Updated email for student ${studentId} ` +
                  `(${studentRemoteId}) under teacher ${teacherUid}`,
              );
              updated++;
            } catch (error) {
              console.error(
                  `Error updating student ${studentId}: ${error.message}`,
              );
              errors++;
            }
          }
        }

        const result = {
          success: true,
          updated: updated,
          skipped: skipped,
          errors: errors,
          message: `Migration complete: ${updated} updated, ` +
                   `${skipped} skipped, ${errors} errors`,
        };

        console.log(result.message);
        return result;
      } catch (error) {
        console.error("Migration error:", error);
        throw new functions.https.HttpsError(
            "internal",
            `Migration failed: ${error.message}`,
        );
      }
    },
);
