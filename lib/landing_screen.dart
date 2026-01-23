import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data'; // Needed for Uint8List
import 'dart:convert';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'guest/event_details_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  String _selectedCategory = 'All Categories';

  final Map<String, IconData> _categoryIcons = {
    'All Categories': Icons.grid_view,
    'Music': Icons.music_note,
    'Business': Icons.business_center,
    'Sports': Icons.sports_soccer,
    'Education': Icons.school,
    'Technology': Icons.computer,
    'Art': Icons.palette,
    'Food & Drink': Icons.restaurant,
    'Health': Icons.health_and_safety,
    'Fashion': Icons.checkroom,
    'Community': Icons.groups,
  };

  bool isValidUrl(String? url) {
    if (url == null || url.isEmpty || url == "null") return false;
    return url.startsWith("http://") || url.startsWith("https://");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: Color(0xFF6C35DE), size: 28),
            const SizedBox(width: 8),
            Text("City Vibe", style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C35DE),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text("Get Started", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 60),
            const Icon(Icons.calendar_month, size: 60, color: Color(0xFF6C35DE)),
            const SizedBox(height: 16),
            Text("City Vibe", style: GoogleFonts.poppins(fontSize: 40, fontWeight: FontWeight.bold, color: const Color(0xFF2D2D2D))),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Your ultimate platform for discovering amazing events and creating unforgettable experiences",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600], height: 1.5),
              ),
            ),
            const SizedBox(height: 40),
            Container(
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: const Color(0xFF5B67F1).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B67F1),
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Go to Dashboard", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text("Everything You Need\nfor Events", textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, height: 1.2)),
                  const SizedBox(height: 16),
                  Text("From creation to execution, we provide all the tools you need for successful events", textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 40),
                  _buildFeatureCard(Icons.calendar_today, "Event Creation", "Create and manage events with ease.", Colors.blue),
                  const SizedBox(height: 20),
                  _buildFeatureCard(Icons.confirmation_number, "Ticket Management", "Flexible ticketing options.", Colors.purple),
                  const SizedBox(height: 20),
                  _buildFeatureCard(Icons.bar_chart, "Real-time Analytics", "Track event performance instantly.", Colors.green),
                ],
              ),
            ),
            const SizedBox(height: 100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text("Discover Events", style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text("Find amazing events happening in your city", style: GoogleFonts.poppins(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCategory,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.grey), 
                        items: _categoryIcons.keys.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Row(
                              children: [
                                Icon(_categoryIcons[value], size: 18, color: _selectedCategory == value ? const Color(0xFF6C35DE) : Colors.grey),
                                const SizedBox(width: 12),
                                Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: _selectedCategory == value ? const Color(0xFF6C35DE) : Colors.black87)),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCategory = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            
            // REDUCED SIZE HERE
            SizedBox(
              height: 280, // Reduced from 340 to 280
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('events').where('date', isGreaterThanOrEqualTo: Timestamp.now()).orderBy('date').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final events = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (_selectedCategory == 'All Categories') return true;
                    return data['genre'] == _selectedCategory;
                  }).toList();
                  if (events.isEmpty) {
                    return Center(child: Text("No events found in $_selectedCategory", style: const TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: events.length,
                    itemBuilder: (ctx, index) {
                      return _buildEventCard(context, events[index].data() as Map<String, dynamic>);
                    },
                  );
                },
              ),
            ),
            
            const SizedBox(height: 80),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 30),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF6C35DE), Color(0xFF5B67F1)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              ),
              child: Column(
                children: [
                  Text("Ready to Get Started?", textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  Text("Join thousands of event organizers and attendees on City Vibe", textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF6C35DE), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text("Get Started Now", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String desc, Color iconColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white, size: 28)),
          const SizedBox(height: 20),
          Text(title, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(desc, style: GoogleFonts.poppins(color: Colors.grey, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, Map<String, dynamic> data) {
    DateTime date = (data['date'] as Timestamp).toDate();
    
    // REDUCED IMAGE HEIGHT LOGIC
    double imgHeight = 280; // Matches container height

    Widget imageWidget;
    Uint8List? imageBytes;
    
    try {
      if (data['imageBase64'] != null && data['imageBase64'].toString().isNotEmpty) {
        imageBytes = base64Decode(data['imageBase64']);
      }
    } catch (e) {
      print("Error decoding image: $e");
    }

    if (imageBytes != null) {
      imageWidget = Image.memory(imageBytes, height: imgHeight, width: double.infinity, fit: BoxFit.cover, errorBuilder: (c,o,s) => Container(color: Colors.grey.shade200));
    } else if (isValidUrl(data['imageUrl'])) {
      imageWidget = Image.network(data['imageUrl'], height: imgHeight, width: double.infinity, fit: BoxFit.cover, errorBuilder: (c,o,s) => Container(color: Colors.grey.shade200));
    } else {
      imageWidget = Container(height: imgHeight, width: double.infinity, color: Colors.grey.shade200, child: const Icon(Icons.image, size: 50, color: Colors.grey));
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailsScreen(eventData: data))),
      child: Container(
        width: 200, // Reduced from 260 to 200
        margin: const EdgeInsets.only(right: 16, bottom: 20), // Slightly tighter margin
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(20), child: imageWidget),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.9)], stops: const [0.5, 1.0]),
                ),
              ),
            ),
            Positioned(
              top: 12, left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(8)),
                child: Text("Rs. ${data['price']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ),
            Positioned(
              bottom: 14, left: 14, right: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['genre'] ?? 'Event', style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  // Font size reduced from 18 to 16 to fit smaller card
                  Text(data['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  
                  // DATE ROW
                  Row(children: [
                    const Icon(Icons.calendar_month, color: Colors.white70, size: 12),
                    const SizedBox(width: 4),
                    Text(DateFormat('MMM dd, yyyy').format(date), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),

                  // LOCATION ROW 
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on, color: Colors.white70, size: 12),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        (data['locationName'] != null && data['locationName'].toString().isNotEmpty) ? data['locationName'] : "Lahore, Pakistan", 
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 11)
                      ),
                    ),
                  ]),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}