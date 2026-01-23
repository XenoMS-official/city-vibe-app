import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../attendee/attendee_dashboard.dart'; // For Notification Screen

class OrganizerStatsScreen extends StatefulWidget {
  const OrganizerStatsScreen({super.key});

  @override
  State<OrganizerStatsScreen> createState() => _OrganizerStatsScreenState();
}

class _OrganizerStatsScreenState extends State<OrganizerStatsScreen> {
  final User? user = FirebaseAuth.instance.currentUser;

  Future<Map<String, dynamic>> _calculateStats() async {
    double totalRevenue = 0;
    int totalSold = 0;
    int totalShares = 0;
    final events = await FirebaseFirestore.instance.collection('events').where('organizerId', isEqualTo: user!.uid).get();
    
    for (var doc in events.docs) {
      final data = doc.data();
      totalRevenue += (data['revenue'] ?? 0);
      totalSold += (data['sales'] ?? 0) as int;
      totalShares += (data['shares'] ?? 0) as int;
    }
    return {'revenue': totalRevenue, 'sold': totalSold, 'shares': totalShares, 'count': events.docs.length};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Stats & Analytics"), 
        automaticallyImplyLeading: false,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('notifications').where('read', isEqualTo: false).snapshots(),
            builder: (context, snapshot) {
              bool hasUnread = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
              return IconButton(
                icon: Stack(children: [const Icon(Icons.notifications_outlined), if(hasUnread) const Positioned(right: 0, top: 0, child: CircleAvatar(radius: 5, backgroundColor: Colors.red))]),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen(isTab: false))),
              );
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _calculateStats(),
          builder: (context, snapshot) {
            if(!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            var stats = snapshot.data!;
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP CARDS (KEEPING THE NUMBERS AS REQUESTED)
                Row(
                  children: [
                    _statCard("Revenue", "Rs.${(stats['revenue'] as double).toInt()}", Icons.attach_money, Colors.green),
                    const SizedBox(width: 15),
                    _statCard("Tickets", "${stats['sold']}", Icons.confirmation_number, Colors.blue),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    _statCard("Shares", "${stats['shares']}", Icons.share, Colors.orange),
                    const SizedBox(width: 15),
                    _statCard("Events", "${stats['count']}", Icons.event, Colors.purple),
                  ],
                ),

                const SizedBox(height: 30),
                const Text("Performance Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),

                // 2. NEW BAR CHART (Replacing the previous vertical list box style)
                Container(
                  height: 250,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Normalized heights for display
                      _chartBar(context, "Revenue", stats['revenue'] / 5000, Colors.green, "Rs.${stats['revenue'].toInt()}"),
                      _chartBar(context, "Sales", stats['sold'].toDouble(), Colors.blue, "${stats['sold']}"),
                      _chartBar(context, "Shares", stats['shares'].toDouble(), Colors.orange, "${stats['shares']}"),
                    ],
                  ),
                ),
              ],
            );
          }
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color), const SizedBox(height: 10), Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
      ),
    );
  }

  Widget _chartBar(BuildContext context, String label, double normalizedValue, Color color, String displayValue) {
    // Clamping height so it fits in the container (Max height 150)
    double height = (normalizedValue * 20).clamp(10.0, 150.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(displayValue, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
        const SizedBox(height: 5),
        Container(width: 40, height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8))),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}