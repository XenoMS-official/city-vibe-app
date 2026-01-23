import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Add this package
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb 
        ? "857778603672-f4o3v80krvb1v6i8385qtt620uhnlq9b.apps.googleusercontent.com" 
        : null,
  );
  
  final LocalAuthentication _localAuth = LocalAuthentication();
  // Secure storage to remember email/pass for biometric login
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // 1. Sign Up
  Future<User?> signUp(String email, String password, String name, String role) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;

      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name,
          'email': email,
          'role': role,
          'createdAt': FieldValue.serverTimestamp(),
          'isVerified': false,
        });
        // Save credentials for future biometric login
        await _saveCredentials(email, password);
      }
      return user;
    } catch (e) {
      print("Sign Up Error: $e");
      rethrow; 
    }
  }

  // 2. Sign In (Updated to save credentials)
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Save credentials for future biometric login
      if (result.user != null) {
        await _saveCredentials(email, password);
      }

      return result.user;
    } catch (e) {
      print("Sign In Error: $e");
      rethrow; 
    }
  }

  // --- NEW: Forgot Password Functionality ---
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      print("Password Reset Error: $e");
      rethrow;
    }
  }

  // --- NEW: Smart Biometric Login ---
  Future<User?> signInWithBiometrics() async {
    if (kIsWeb) return null;

    try {
      // 1. Check if we have stored credentials
      String? savedEmail = await _storage.read(key: 'user_email');
      String? savedPass = await _storage.read(key: 'user_pass');

      if (savedEmail == null || savedPass == null) {
        throw FirebaseAuthException(
          code: 'no-credentials', 
          message: 'Please login with password once to enable biometrics.'
        );
      }

      // 2. Perform Biometric Check
      bool canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) throw FirebaseAuthException(code: 'bio-unavailable', message: 'Biometrics not available');

      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan fingerprint to login as $savedEmail',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );

      // 3. If Fingerprint matches, Log in to Firebase
      if (authenticated) {
        UserCredential result = await _auth.signInWithEmailAndPassword(
          email: savedEmail,
          password: savedPass,
        );
        return result.user;
      }
    } catch (e) {
      print("Biometric Logic Error: $e");
      rethrow;
    }
    return null;
  }

  // Helper: Save credentials securely
  Future<void> _saveCredentials(String email, String password) async {
    if (!kIsWeb) {
      await _storage.write(key: 'user_email', value: email);
      await _storage.write(key: 'user_pass', value: password);
    }
  }

  // 3. Google Sign In
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; 

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential result = await _auth.signInWithCredential(credential);
      User? user = result.user;

      if (user != null) {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (!userDoc.exists) {
          await _firestore.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'name': user.displayName ?? "No Name",
            'email': user.email,
            'role': 'attendee', 
            'createdAt': FieldValue.serverTimestamp(),
            'isVerified': false,
          });
        }
      }
      return user;
    } catch (e) {
      print("Google Sign In Error: $e");
      return null;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    // Kept for backward compatibility if needed, but signInWithBiometrics is better
    return false; 
  }

  Future<String?> getUserRole(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.get('role') as String?;
      }
    } catch (e) {
      print("Error fetching role: $e");
    }
    return 'attendee';
  }

  Future<bool> isOrganizerVerified(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        return data['isVerified'] == true;
      }
    } catch (e) {
      print("Error checking verification: $e");
    }
    return false;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {}
    await _auth.signOut();
  }
}