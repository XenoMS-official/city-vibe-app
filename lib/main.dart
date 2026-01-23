import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_stripe/flutter_stripe.dart';
// ADD HIVE IMPORT
import 'package:hive_flutter/hive_flutter.dart';

// IMPORTS
import 'auth_provider.dart';
import 'login_screen.dart';
import 'landing_screen.dart'; 

// ORGANIZER IMPORTS
import 'organizer/organizer_verification_screen.dart';
import 'organizer/organizer_dashboard.dart';

// ATTENDEE IMPORT
import 'attendee/attendee_dashboard.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- 1. FIREBASE INITIALIZATION ---
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyBxB7uK_RqTZVqiG0fR-RX4Q8KZ2emZgPw",
          authDomain: "city-vibes-8452e.firebaseapp.com",
          projectId: "city-vibes-8452e",
          storageBucket: "city-vibes-8452e.firebasestorage.app",
          messagingSenderId: "857778603672",
          appId: "1:857778603672:web:706dfb53627ec6203772ed",
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    print("Firebase Init Error: $e");
  }

  // --- 2. HIVE INITIALIZATION (OFFLINE STORAGE) ---
  await Hive.initFlutter();

  // --- 3. STRIPE INITIALIZATION ---
  Stripe.publishableKey = 'pk_test_51SXRu0L12FBOAN0hHYBEPiQncQfByBWIGCagmXvraa9s2rEMDyH7JURaY2dvekmiO9OZegXRsLdCjqMEzyUVWXQN00WGvP1zu6'; 
  await Stripe.instance.applySettings();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    final BorderRadius globalRadius = BorderRadius.circular(24);
    final InputBorder globalInputBorder = OutlineInputBorder(
      borderRadius: globalRadius,
      borderSide: BorderSide.none,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'City Vibe',
      
      // Connect Theme Mode from Provider
      themeMode: authProvider.themeMode,

      // 1. LIGHT THEME
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: GoogleFonts.poppins().fontFamily,
        primaryColor: const Color(0xFF6C35DE),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: const StadiumBorder(), 
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: const Color(0xFF6C35DE),
            foregroundColor: Colors.white,
          ),
        ),
        
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: globalInputBorder,
          enabledBorder: globalInputBorder,
          focusedBorder: globalInputBorder.copyWith(
            borderSide: const BorderSide(color: Color(0xFF6C35DE), width: 1.5),
          ),
        ),

        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
        ),
      ),

      // 2. DARK THEME
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: GoogleFonts.poppins().fontFamily,
        primaryColor: const Color(0xFF8E2DE2),
        scaffoldBackgroundColor: const Color(0xFF121212),
        
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: const Color(0xFF8E2DE2),
            foregroundColor: Colors.white,
          ),
        ),
        
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2C2C2C),
          border: globalInputBorder,
          enabledBorder: globalInputBorder,
          focusedBorder: globalInputBorder.copyWith(
            borderSide: const BorderSide(color: Color(0xFF8E2DE2), width: 1.5),
          ),
        ),
      ),
      
      home: const AuthChecker(),
    );
  }
}

class AuthChecker extends StatelessWidget {
  const AuthChecker({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    // 1. Loading State
    if (authProvider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 2. NOT LOGGED IN? -> Show Landing Screen
    if (authProvider.user == null) {
      return const LandingScreen(); 
    }

    // 3. LOGGED IN? -> Check Role
    if (authProvider.role == 'organizer') {
      if (authProvider.isOrganizerVerified) {
        return const OrganizerDashboard(); // Go to Dashboard
      } else {
        return const OrganizerVerificationScreen(); // Go to ID Check
      }
    }

    // 4. Logged In Attendee
    return const AttendeeDashboard();
  }
}