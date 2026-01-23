import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'package:image_picker/image_picker.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();
  
  bool _isOnboardingComplete = false;
  
  // Initialize loading as true to check status on app start
  bool _isLoading = true;
  
  User? _user;
  String _role = 'attendee'; 
  bool _isOrganizerVerified = false;
  ThemeMode _themeMode = ThemeMode.light;

  XFile? _profileImage; 
  XFile? get profileImage => _profileImage;

  bool get isOnboardingComplete => _isOnboardingComplete;
  bool get isLoading => _isLoading;
  User? get user => _user;
  String get role => _role;
  bool get isOrganizerVerified => _isOrganizerVerified;
  ThemeMode get themeMode => _themeMode;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    _auth.authStateChanges().listen((User? user) async {
      // --- FIX START: PREVENT SCREEN FLASH ---
      // If a user is detected, immediately set loading to true
      // This forces AuthChecker to show the spinner instead of the AttendeeDashboard
      // while we fetch the role from Firestore.
      if (user != null) {
        _isLoading = true;
        notifyListeners(); 
      }
      // --- FIX END ---

      _user = user;
      
      if (user != null) {
        // Logged In: Fetch Role
        // This await holds the execution here while _isLoading is true
        _role = await _authService.getUserRole(user.uid) ?? 'attendee';
        
        if (_role == 'organizer') {
          _isOrganizerVerified = await _authService.isOrganizerVerified(user.uid);
        }
      } else {
        // Logged Out: Reset
        _role = 'attendee';
        _isOrganizerVerified = false;
      }

      // Only AFTER the role is fetched do we stop loading
      _isLoading = false;
      notifyListeners();
    });
  }

  void completeOnboarding() {
    _isOnboardingComplete = true;
    notifyListeners();
  }

  void setProfileImage(XFile? image) {
    _profileImage = image;
    notifyListeners();
  }

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setRole(String role) {
    _role = role;
    notifyListeners();
  }

  void verifyOrganizer() {
    _isOrganizerVerified = true;
    notifyListeners();
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    await _authService.signOut();

    _role = 'attendee'; 
    _isOrganizerVerified = false;
    _profileImage = null;
    
    // The listener in _init will handle setting _user to null and _isLoading to false
  }
}