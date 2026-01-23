import 'package:flutter/material.dart';
import 'organizer_home_screen.dart'; // Import the file you just created above
import 'organizer_stats_screen.dart'; // The stats screen you already have
import 'organizer_profile_screen.dart'; // The profile screen you already have

class OrganizerDashboard extends StatefulWidget {
  const OrganizerDashboard({super.key});

  @override
  State<OrganizerDashboard> createState() => _OrganizerDashboardState();
}

class _OrganizerDashboardState extends State<OrganizerDashboard> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const OrganizerHomeScreen(),  // Tab 1: Calendar View
    const OrganizerStatsScreen(), // Tab 2: Stats & Notification View
    const OrganizerProfileScreen(),// Tab 3: Profile View
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined), 
            selectedIcon: Icon(Icons.calendar_month), 
            label: 'Schedule'
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined), 
            selectedIcon: Icon(Icons.dashboard), 
            label: 'Stats'
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline), 
            selectedIcon: Icon(Icons.person), 
            label: 'Profile'
          ),
        ],
      ),
    );
  }
}