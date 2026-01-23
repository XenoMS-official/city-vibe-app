import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert'; 
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart'; 
// STRIPE IMPORTS
import 'package:flutter_stripe/flutter_stripe.dart' hide Card; 
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 
// HIVE IMPORT
import 'package:hive_flutter/hive_flutter.dart';

import '../auth_provider.dart'; 

// --- HELPER: SAFE IMAGE URL CHECK ---
bool isValidUrl(String? url) {
  if (url == null || url.isEmpty || url == "null") return false;
  return url.startsWith("http://") || url.startsWith("https://");
}

// --- HELPER: DATE PARSER ---
DateTime parseEventDate(dynamic rawDate) {
  if (rawDate is Timestamp) return rawDate.toDate();
  if (rawDate is int) return DateTime.fromMillisecondsSinceEpoch(rawDate);
  return DateTime.now();
}

// --- MAIN DASHBOARD ---
class AttendeeDashboard extends StatefulWidget {
  const AttendeeDashboard({super.key});

  @override
  State<AttendeeDashboard> createState() => _AttendeeDashboardState();
}

class _AttendeeDashboardState extends State<AttendeeDashboard> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
       const AttendeeHomeTab(),
       const AttendeeTicketsTab(), 
       const AttendeeProfileTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color navColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color selectedColor = const Color(0xFF6C35DE);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navColor,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: navColor,
          selectedItemColor: selectedColor,
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          selectedLabelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: "Explore"),
            BottomNavigationBarItem(icon: Icon(Icons.confirmation_number_outlined), label: "Tickets"),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "Profile"),
          ],
        ),
      ),
    );
  }
}

// --- NOTIFICATION SCREEN ---
class NotificationScreen extends StatefulWidget {
  final bool isTab; 
  const NotificationScreen({super.key, this.isTab = false}); 

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    _markNotificationsAsRead();
  }

  Future<void> _markNotificationsAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if(user != null) {
      final batch = FirebaseFirestore.instance.batch();
      final unread = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('notifications').where('read', isEqualTo: false).get();
      for(var doc in unread.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        automaticallyImplyLeading: !widget.isTab, 
      ),
      body: user == null ? const Center(child: Text("Login to see notifications")) : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('notifications').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if(snapshot.data!.docs.isEmpty) return const Center(child: Text("No notifications yet."));

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (ctx, index) {
              var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              bool isTicket = data['type'] == 'ticket';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isTicket ? Colors.green.withOpacity(0.1) : const Color(0xFF6C35DE).withOpacity(0.1), 
                  child: Icon(isTicket ? Icons.confirmation_number : Icons.event, color: isTicket ? Colors.green : const Color(0xFF6C35DE))
                ),
                title: Text(data['title'] ?? "Notification"),
                subtitle: Text(data['message'] ?? ""),
                trailing: Text(data['createdAt'] != null ? DateFormat('MM/dd HH:mm').format((data['createdAt'] as Timestamp).toDate()) : "", style: const TextStyle(fontSize: 10, color: Colors.grey)),
              );
            },
          );
        },
      ),
    );
  }
}

// --- TAB 1: HOME (EXPLORE) ---
class AttendeeHomeTab extends StatefulWidget {
  const AttendeeHomeTab({super.key});

  @override
  State<AttendeeHomeTab> createState() => _AttendeeHomeTabState();
}

class _AttendeeHomeTabState extends State<AttendeeHomeTab> with TickerProviderStateMixin {
  final User? user = FirebaseAuth.instance.currentUser;
  String _userName = "Guest";
  LatLng? _userLocation;
  
  String _selectedCategory = 'All';
  bool _isCategoryExpanded = false; 

  final List<String> _categories = [
    'All', 'Music', 'Business', 'Sports', 'Education', 'Technology', 
    'Art', 'Food & Drink', 'Health', 'Fashion', 'Community'
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _scanForNearbyNewEvents() async {
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    double? lat = prefs.getDouble('user_lat');
    double? lng = prefs.getDouble('user_lng');
    
    if (lat == null || lng == null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      if (doc.exists) {
        lat = (doc.data() as Map<String, dynamic>)['latitude'];
        lng = (doc.data() as Map<String, dynamic>)['longitude'];
      }
    }

    if(lat == null || lng == null) return; 

    final now = DateTime.now();
    final recentEvents = await FirebaseFirestore.instance.collection('events')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(now.subtract(const Duration(hours: 48))))
        .get();

    const Distance distance = Distance();
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    bool hasUpdates = false;

    for (var doc in recentEvents.docs) {
      var data = doc.data();
      if (data['latitude'] != null && data['longitude'] != null) {
        double km = distance.as(LengthUnit.Kilometer, LatLng(lat, lng), LatLng(data['latitude'], data['longitude']));
        
        if (km <= 50) {
          final notifRef = FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('notifications').doc('new_${doc.id}');
          final notifSnapshot = await notifRef.get();
          
          if (!notifSnapshot.exists) {
             hasUpdates = true;
             batch.set(notifRef, {
               'title': 'New Event Nearby!',
               'message': '${data['title']} is happening ${km.toStringAsFixed(1)}km away!',
               'type': 'event',
               'eventId': doc.id,
               'createdAt': Timestamp.now(),
               'read': false
             });
          }
        }
      }
    }

    if (hasUpdates) {
      await batch.commit();
    }
    await prefs.setInt('last_event_scan', now.millisecondsSinceEpoch);
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    double? lat = prefs.getDouble('user_lat');
    double? lng = prefs.getDouble('user_lng');

    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      if (doc.exists && mounted) {
        var userData = doc.data() as Map<String, dynamic>;
        setState(() => _userName = userData['name'] ?? "Guest");

        if (lat == null && userData['latitude'] != null && userData['longitude'] != null) {
          lat = userData['latitude'];
          lng = userData['longitude'];
          await prefs.setDouble('user_lat', lat!);
          await prefs.setDouble('user_lng', lng!);
          if(userData['city'] != null) {
            await prefs.setString('user_city', userData['city']);
          }
        }
      }
    }

    if (lat != null && lng != null && mounted) {
      setState(() {
        _userLocation = LatLng(lat!, lng!);
      });
      _scanForNearbyNewEvents();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: Color(0xFF6C35DE), size: 28),
            const SizedBox(width: 8),
            Text("City Vibe", style: GoogleFonts.poppins(color: textColor, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        actions: [
          Center(child: Text("Hi, $_userName", style: GoogleFonts.poppins(color: textColor, fontWeight: FontWeight.w600))),
          const SizedBox(width: 15),

          StreamBuilder<QuerySnapshot>(
            stream: user != null 
              ? FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('notifications').where('read', isEqualTo: false).snapshots()
              : const Stream.empty(),
            builder: (context, snapshot) {
              bool hasUnread = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_outlined, size: 28),
                    color: textColor,
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen(isTab: false))), 
                  ),
                  if(hasUnread)
                    Positioned(
                      right: 12, top: 12,
                      child: Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      ),
                    )
                ],
              );
            }
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Discover Events", style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // --- CATEGORY BUTTON ---
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () {
                        setState(() {
                          _isCategoryExpanded = !_isCategoryExpanded;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: const Color(0xFF6C35DE).withOpacity(0.5)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C35DE).withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.filter_list_alt, color: Color(0xFF6C35DE), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Category: $_selectedCategory",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, 
                                color: textColor
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedRotation(
                              turns: _isCategoryExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 300),
                              child: Icon(Icons.keyboard_arrow_down, color: textColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topLeft,
                  child: _isCategoryExpanded 
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(top: 16, bottom: 4), 
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _categories.map((cat) {
                            bool isSelected = _selectedCategory == cat;
                            return ChoiceChip(
                              label: Text(cat),
                              selected: isSelected,
                              onSelected: (val) {
                                setState(() {
                                  _selectedCategory = cat;
                                  _isCategoryExpanded = false; 
                                });
                              },
                              selectedColor: const Color(0xFF6C35DE),
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : textColor, 
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                              ),
                              backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: isSelected ? Colors.transparent : Colors.grey.withOpacity(0.3)
                                )
                              ),
                            );
                          }).toList(),
                        ),
                      )
                    : const SizedBox(width: double.infinity), 
                ),
              ],
            ),
            
            const SizedBox(height: 24),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('events').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text("Error loading events");
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                var events = snapshot.data!.docs.map((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  data['id'] = doc.id;
                  return data;
                }).toList();

                DateTime now = DateTime.now();
                events = events.where((e) {
                   DateTime eDate = parseEventDate(e['date']);
                   return eDate.isAfter(now); 
                }).toList();

                if (_selectedCategory != 'All') {
                  events = events.where((e) => e['genre'] == _selectedCategory).toList();
                }

                if (events.isEmpty) return const Center(child: Text("No upcoming events found"));

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: events.length,
                  itemBuilder: (ctx, index) => EventCard(data: events[index]),
                );
              },
            ),

            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),

            Text("Nearby Events", style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            _userLocation == null 
              ? Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Row(children: [Icon(Icons.location_off, color: Colors.amber), SizedBox(width: 10), Expanded(child: Text("Set location in Profile to see nearby events."))]),
                )
              : StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('events').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox(); 
                    
                    var allEvents = snapshot.data!.docs.map((doc) {
                      var data = doc.data() as Map<String, dynamic>;
                      data['id'] = doc.id;
                      return data;
                    }).toList();

                    DateTime now = DateTime.now();
                    allEvents = allEvents.where((e) {
                       DateTime eDate = parseEventDate(e['date']);
                       return eDate.isAfter(now);
                    }).toList();

                    const Distance distance = Distance();
                    List<Map<String, dynamic>> nearby = [];

                    for (var e in allEvents) {
                      if (e['latitude'] != null && e['longitude'] != null) {
                        double km = distance.as(LengthUnit.Kilometer, _userLocation!, LatLng(e['latitude'], e['longitude']));
                        if (km <= 50) { 
                          e['distance'] = km; 
                          nearby.add(e);
                        }
                      }
                    }
                    nearby.sort((a, b) => (a['distance'] as double).compareTo(b['distance']));
                    if (nearby.isEmpty) return const Center(child: Text("No upcoming events found nearby."));

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: nearby.length,
                      itemBuilder: (ctx, index) => EventCard(data: nearby[index], showDistance: true),
                    );
                  },
                ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

// --- EVENT CARD ---
class EventCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool showDistance;

  const EventCard({super.key, required this.data, this.showDistance = false});

  @override
  Widget build(BuildContext context) {
    DateTime date = parseEventDate(data['date']);
    String priceDisplay = (data['price']?.toString()) ?? "0";

    Widget imageWidget;
    if (data['imageBase64'] != null && data['imageBase64'].toString().isNotEmpty) {
      imageWidget = Image.memory(
        base64Decode(data['imageBase64']),
        height: 160,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (c,o,s) => Container(height: 160, color: Colors.grey[300], child: const Icon(Icons.broken_image)),
      );
    } else if (isValidUrl(data['imageUrl'])) {
      imageWidget = Image.network(
        data['imageUrl'], 
        height: 160, 
        width: double.infinity, 
        fit: BoxFit.cover,
        errorBuilder: (c,o,s) => Container(height: 160, color: Colors.grey[300], child: const Icon(Icons.broken_image)),
      );
    } else {
      imageWidget = Container(
        height: 160, 
        width: double.infinity, 
        color: Colors.grey[300], 
        child: const Icon(Icons.image, size: 50, color: Colors.grey)
      );
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailsScreen(eventData: data))),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: imageWidget,
                ),
                Positioned(
                  top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Text("Rs. $priceDisplay", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['title'] ?? "Event", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(children: [const Icon(Icons.calendar_month, size: 14, color: Colors.grey), const SizedBox(width: 4), Text(DateFormat('MMM dd • hh:mm a').format(date), style: const TextStyle(fontSize: 12, color: Colors.grey))]),
                  if (showDistance && data['distance'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [const Icon(Icons.location_on, size: 14, color: Color(0xFF6C35DE)), const SizedBox(width: 4), Text("${(data['distance'] as double).toStringAsFixed(1)} km away", style: const TextStyle(fontSize: 12, color: Color(0xFF6C35DE), fontWeight: FontWeight.bold))]),
                    )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- EVENT DETAILS SCREEN ---
class EventDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> eventData;
  const EventDetailsScreen({super.key, required this.eventData});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  bool _isLiked = false;
  bool _isBooking = false;
  final User? user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _checkIfLiked();
  }

  void _checkIfLiked() async {
    if(user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('favorites').doc(widget.eventData['id']).get();
    if(mounted) setState(() => _isLiked = doc.exists);
  }

  void _toggleLike() async {
    if(user == null) return;
    setState(() => _isLiked = !_isLiked);
    final ref = FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('favorites').doc(widget.eventData['id']);
    
    if(_isLiked) {
      await ref.set({
        'id': widget.eventData['id'],
        'title': widget.eventData['title'] ?? 'Unknown',
        'date': widget.eventData['date'], 
        'price': (widget.eventData['price'] ?? 0).toString(), 
        'imageUrl': widget.eventData['imageUrl'] ?? '',
        'imageBase64': widget.eventData['imageBase64'], 
        'locationName': widget.eventData['locationName'] ?? 'Unknown',
        'genre': widget.eventData['genre'] ?? 'Other',
        'likedAt': Timestamp.now()
      });
    } else {
      await ref.delete();
    }
  }

  void _shareEvent() async {
    Share.share("Check out this event: ${widget.eventData['title']} on City Vibe!");
    final eventRef = FirebaseFirestore.instance.collection('events').doc(widget.eventData['id']);
    final String? organizerId = widget.eventData['organizerId'];
    eventRef.update({'shares': FieldValue.increment(1)});
    if (organizerId != null) {
      FirebaseFirestore.instance.collection('users').doc(organizerId).collection('notifications').add({
        'title': 'Event Shared!',
        'message': 'Someone just shared your event "${widget.eventData['title']}"',
        'type': 'stat',
        'createdAt': Timestamp.now(),
        'read': false,
      });
    }
  }

  void _initiatePurchase() async {
    if (user == null) return;
    int quantity = 1;
    double unitPrice = double.tryParse(widget.eventData['price'].toString()) ?? 0.0;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("How many tickets?"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(onPressed: () => setStateSB(() { if(quantity>1) quantity--; }), icon: const Icon(Icons.remove_circle_outline)),
                      Text("$quantity", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => setStateSB(() { if(quantity<10) quantity++; }), icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text("Total: Rs. ${unitPrice * quantity}", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6C35DE))),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C35DE),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _processBooking(quantity, unitPrice * quantity);
                  },
                  child: const Text("Confirm", style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _processBooking(int quantity, double totalPrice) async {
    setState(() => _isBooking = true);

    try {
      final attendeeRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
      final eventRef = FirebaseFirestore.instance.collection('events').doc(widget.eventData['id']);
      final String? organizerId = widget.eventData['organizerId'];
      
      if(organizerId == null) throw Exception("Organizer ID missing");
      final organizerRef = FirebaseFirestore.instance.collection('users').doc(organizerId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot attendeeSnap = await transaction.get(attendeeRef);
        DocumentSnapshot eventSnap = await transaction.get(eventRef);
        
        if (!attendeeSnap.exists) throw Exception("User does not exist!");
        if (!eventSnap.exists) throw Exception("Event no longer exists!");

        double currentBalance = (attendeeSnap.data() as Map<String, dynamic>)['walletBalance']?.toDouble() ?? 0.0;
        if (currentBalance < totalPrice) throw Exception("Insufficient Funds");

        double platformFee = totalPrice * 0.02; // 2% Cut
        double organizerEarning = totalPrice - platformFee;

        // Deduct from Attendee
        transaction.update(attendeeRef, {'walletBalance': currentBalance - totalPrice});
        
        DocumentReference attHistRef = attendeeRef.collection('wallet_history').doc();
        transaction.set(attHistRef, {
          'type': 'debit',
          'amount': totalPrice,
          'description': 'Bought $quantity tickets for ${widget.eventData['title']}',
          'date': Timestamp.now()
        });

        // Add to Organizer
        transaction.update(organizerRef, {'walletBalance': FieldValue.increment(organizerEarning)});

        DocumentReference orgHistRef = organizerRef.collection('wallet_history').doc();
        transaction.set(orgHistRef, {
          'type': 'credit',
          'amount': organizerEarning,
          'description': 'Ticket Sales: ${widget.eventData['title']} ($quantity)',
          'fee_deducted': platformFee,
          'date': Timestamp.now()
        });

        // Update Event
        transaction.update(eventRef, {
          'sales': FieldValue.increment(quantity),
          'revenue': FieldValue.increment(organizerEarning)
        });

        // Generate Tickets
        for (int i = 0; i < quantity; i++) {
          String ticketId = FirebaseFirestore.instance.collection('tickets').doc().id;
          final ticketData = {
            'ticketId': ticketId,
            'eventId': widget.eventData['id'],
            'userId': user!.uid,
            'title': widget.eventData['title'],
            'date': widget.eventData['date'],
            'price': totalPrice / quantity,
            'imageUrl': widget.eventData['imageUrl'], 
            'imageBase64': widget.eventData['imageBase64'], 
            'location': widget.eventData['locationName'] ?? 'Unknown',
            'qrData': "$ticketId|${user!.uid}|${widget.eventData['id']}|Unique$i",
            'purchasedAt': Timestamp.now(),
            'status': 'active' // Default status
          };
          transaction.set(FirebaseFirestore.instance.collection('tickets').doc(ticketId), ticketData);
        }

        transaction.set(attendeeRef.collection('notifications').doc(), {
          'title': 'Tickets Purchased',
          'message': 'You bought $quantity tickets for ${widget.eventData['title']}',
          'type': 'ticket',
          'createdAt': Timestamp.now(),
          'read': false
        });

        transaction.set(organizerRef.collection('notifications').doc(), {
          'title': 'New Ticket Sale!',
          'message': 'Sold $quantity tickets for ${widget.eventData['title']}. You earned Rs. ${organizerEarning.toStringAsFixed(0)}',
          'type': 'sale',
          'amount': organizerEarning,
          'createdAt': Timestamp.now(),
          'read': false
        });
      });

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tickets Booked!"), backgroundColor: Colors.green));
        Navigator.pop(context); 
      }

    } catch (e) {
      if(mounted) {
        String msg = e.toString().contains("Insufficient Funds") ? "Insufficient Funds! Please Top Up." : "Booking Failed: $e";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } finally {
      if(mounted) setState(() => _isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime date = parseEventDate(widget.eventData['date']);
    String priceDisplay = widget.eventData['price']?.toString() ?? "0";

    Widget headerImage;
    if (widget.eventData['imageBase64'] != null && widget.eventData['imageBase64'].toString().isNotEmpty) {
      headerImage = Image.memory(
        base64Decode(widget.eventData['imageBase64']),
        height: 250,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (c,o,s) => Container(height: 250, color: Colors.grey[300], child: const Icon(Icons.broken_image)),
      );
    } else if (isValidUrl(widget.eventData['imageUrl'])) {
      headerImage = Image.network(
        widget.eventData['imageUrl'], 
        height: 250, 
        width: double.infinity, 
        fit: BoxFit.cover,
        errorBuilder: (c,o,s) => Container(height: 250, color: Colors.grey, child: const Icon(Icons.broken_image)),
      );
    } else {
      headerImage = Container(height: 250, width: double.infinity, color: Colors.grey[300], child: const Icon(Icons.image, size: 60, color: Colors.grey));
    }

    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                     headerImage,
                    Positioned(top: 40, left: 10, child: CircleAvatar(backgroundColor: Colors.white, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)))),
                    Positioned(top: 40, right: 10, child: Row(children: [CircleAvatar(backgroundColor: Colors.white, child: IconButton(icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, color: _isLiked ? Colors.red : Colors.grey), onPressed: _toggleLike)), const SizedBox(width: 8), CircleAvatar(backgroundColor: Colors.white, child: IconButton(icon: const Icon(Icons.share, color: Colors.black), onPressed: _shareEvent))])),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.eventData['title'] ?? "Event", style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(children: [const Icon(Icons.calendar_today, size: 16, color: Colors.grey), const SizedBox(width: 5), Text(DateFormat('EEEE, MMM d, yyyy • hh:mm a').format(date))]),
                      const SizedBox(height: 10),
                      Row(children: [const Icon(Icons.location_on, size: 16, color: Colors.grey), const SizedBox(width: 5), Expanded(child: Text(widget.eventData['locationName'] ?? "Unknown Location"))]),
                      const SizedBox(height: 20),
                      Text("About Event", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text(widget.eventData['description'] ?? "No description available.", style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 30),
                      
                      if(widget.eventData['latitude'] != null && widget.eventData['longitude'] != null)
                        Container(
                          height: 150,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: FlutterMap(
                              options: MapOptions(initialCenter: LatLng(widget.eventData['latitude'], widget.eventData['longitude']), initialZoom: 14),
                              children: [
                                TileLayer(urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"),
                                MarkerLayer(markers: [Marker(point: LatLng(widget.eventData['latitude'], widget.eventData['longitude']), child: const Icon(Icons.location_on, color: Colors.red, size: 40))])
                              ],
                            ),
                          ),
                        ),
                       const SizedBox(height: 80),
                    ],
                  ),
                )
              ],
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0,-5))]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Price", style: TextStyle(color: Colors.grey)),
                      Text("Rs. $priceDisplay", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF6C35DE))),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C35DE), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    onPressed: _isBooking ? null : _initiatePurchase,
                    child: _isBooking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Book Ticket", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

// --- TAB 2: TICKETS (UPDATED WITH CANCEL & REFUND) ---
class AttendeeTicketsTab extends StatefulWidget {
  const AttendeeTicketsTab({super.key});

  @override
  State<AttendeeTicketsTab> createState() => _AttendeeTicketsTabState();
}

class _AttendeeTicketsTabState extends State<AttendeeTicketsTab> {
  final User? user = FirebaseAuth.instance.currentUser;
  Box? _ticketsBox;
  bool _isProcessingCancellation = false;

  @override
  void initState() {
    super.initState();
    _openBox();
    _checkForCancelledEvents();
  }

  Future<void> _openBox() async {
    var box = await Hive.openBox('tickets_cache');
    setState(() {
      _ticketsBox = box;
    });
  }

  // --- Check Event Status & Refund (System Cancellation) ---
  Future<void> _checkForCancelledEvents() async {
    if(user == null) return;
    try {
      var ticketsSnap = await FirebaseFirestore.instance.collection('tickets')
          .where('userId', isEqualTo: user!.uid)
          .get(); 

      for (var ticketDoc in ticketsSnap.docs) {
        var data = ticketDoc.data();
        if (data['status'] == 'cancelled') continue; 

        String eventId = data['eventId'];
        var eventSnap = await FirebaseFirestore.instance.collection('events').doc(eventId).get();
        if(eventSnap.exists && eventSnap.data()?['status'] == 'cancelled') {
            await FirebaseFirestore.instance.runTransaction((transaction) async {
                 DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
                 DocumentSnapshot userSnap = await transaction.get(userRef);
                 double currentBalance = (userSnap.data() as Map<String, dynamic>)['walletBalance']?.toDouble() ?? 0.0;
                 double refundAmount = (data['price'] ?? 0).toDouble();

                 transaction.update(userRef, {'walletBalance': currentBalance + refundAmount});
                 
                 DocumentReference histRef = userRef.collection('wallet_history').doc();
                 transaction.set(histRef, {
                     'type': 'credit',
                     'amount': refundAmount,
                     'description': 'Refund: ${data['title']} (Cancelled)',
                     'date': Timestamp.now()
                 });

                 transaction.update(ticketDoc.reference, {
                     'status': 'cancelled',
                     'refunded': true
                 });
            });
            
            if(mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Refunded: ${data['title']} was cancelled."), backgroundColor: Colors.red));
            }
        }
      }
    } catch(e) {
      debugPrint("Error checking cancellations: $e");
    }
  }

  // --- USER INITIATED CANCELLATION LOGIC ---
  Future<void> _cancelTicket(String ticketId, String eventId, double price, String eventTitle) async {
    // 1. CONFIRMATION DIALOG
    double refundAmount = price * 0.60;
    
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Cancel Ticket?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Are you sure you want to cancel this ticket?"),
            const SizedBox(height: 10),
            Text("Original Price: Rs. $price", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 5),
            Text("Refund Amount (60%): Rs. ${refundAmount.toStringAsFixed(0)}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 5),
            const Text("Organizer keeps 40%.", style: TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Keep Ticket")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, // Cancel implies red/danger
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Confirm Cancel", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      )
    );

    if (confirm != true) return;

    setState(() => _isProcessingCancellation = true);

    try {
      // 2. FETCH EVENT TO GET ORGANIZER ID
      DocumentSnapshot eventDoc = await FirebaseFirestore.instance.collection('events').doc(eventId).get();
      if (!eventDoc.exists) throw "Event not found";
      
      String? organizerId = (eventDoc.data() as Map<String, dynamic>)['organizerId'];
      if (organizerId == null) throw "Organizer not found";

      // 3. EXECUTE TRANSACTION
      await FirebaseFirestore.instance.runTransaction((transaction) async {
         DocumentReference attendeeRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
         DocumentReference organizerRef = FirebaseFirestore.instance.collection('users').doc(organizerId);
         DocumentReference ticketRef = FirebaseFirestore.instance.collection('tickets').doc(ticketId);

         // Get current balances (optional strict check, but usually deduction is forced)
         DocumentSnapshot orgSnap = await transaction.get(organizerRef);
         if (!orgSnap.exists) throw "Organizer data missing";
         double orgBalance = (orgSnap.data() as Map<String, dynamic>)['walletBalance']?.toDouble() ?? 0.0;

         // Logic: Deduct 60% from Organizer, Add 60% to Attendee
         // This ensures Attendee gets 60%, Organizer effectively keeps the rest (40%) they already have.
         
         // Update Organizer
         transaction.update(organizerRef, {'walletBalance': orgBalance - refundAmount});
         DocumentReference orgHistRef = organizerRef.collection('wallet_history').doc();
         transaction.set(orgHistRef, {
           'type': 'debit',
           'amount': refundAmount,
           'description': 'Refund: User cancelled $eventTitle ticket',
           'date': Timestamp.now()
         });
         transaction.set(organizerRef.collection('notifications').doc(), {
           'title': 'Ticket Cancelled',
           'message': 'A user cancelled their ticket for $eventTitle. Rs. ${refundAmount.toStringAsFixed(0)} refunded (60%). You kept 40%.',
           'type': 'cancel',
           'createdAt': Timestamp.now(),
           'read': false
         });

         // Update Attendee
         transaction.update(attendeeRef, {'walletBalance': FieldValue.increment(refundAmount)});
         DocumentReference attHistRef = attendeeRef.collection('wallet_history').doc();
         transaction.set(attHistRef, {
           'type': 'credit',
           'amount': refundAmount,
           'description': 'Refund: Cancelled $eventTitle ticket (60%)',
           'date': Timestamp.now()
         });
         transaction.set(attendeeRef.collection('notifications').doc(), {
           'title': 'Ticket Cancelled',
           'message': 'You cancelled your ticket for $eventTitle. Rs. ${refundAmount.toStringAsFixed(0)} (60%) refunded to wallet.',
           'type': 'ticket',
           'createdAt': Timestamp.now(),
           'read': false
         });

         // Update Ticket
         transaction.update(ticketRef, {'status': 'cancelled'});
      });

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ticket Cancelled. Refund processed."), backgroundColor: Colors.green));

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cancellation Failed: $e"), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isProcessingCancellation = false);
    }
  }

  Map<String, dynamic> _prepareForCache(Map<String, dynamic> data) {
    Map<String, dynamic> cleanData = Map.from(data);
    if (cleanData['date'] is Timestamp) {
      cleanData['date'] = (cleanData['date'] as Timestamp).millisecondsSinceEpoch;
    }
    if (cleanData['purchasedAt'] is Timestamp) {
      cleanData['purchasedAt'] = (cleanData['purchasedAt'] as Timestamp).millisecondsSinceEpoch;
    }
    return cleanData;
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) return const Center(child: Text("Please login to view tickets"));
    if (_ticketsBox == null) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text("My Tickets"), automaticallyImplyLeading: false),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tickets')
                .where('userId', isEqualTo: user!.uid)
                .snapshots(),
            builder: (context, snapshot) {
              List<Map<String, dynamic>> ticketsList = [];
              bool isOffline = false;

              if (snapshot.hasData) {
                var docs = snapshot.data!.docs;
                ticketsList = docs.map((d) {
                  return d.data() as Map<String, dynamic>;
                }).toList();

                List<Map<String, dynamic>> cacheData = ticketsList.map((t) => _prepareForCache(t)).toList();
                _ticketsBox!.put('user_${user!.uid}', cacheData);

              } else if (snapshot.hasError || snapshot.connectionState == ConnectionState.waiting) {
                var cachedData = _ticketsBox!.get('user_${user!.uid}');
                
                if (cachedData != null) {
                  List<dynamic> rawList = cachedData;
                  ticketsList = rawList.map((e) => Map<String, dynamic>.from(e)).toList();
                  
                  if (snapshot.hasError) isOffline = true;
                } else if (snapshot.connectionState == ConnectionState.waiting) {
                   return const Center(child: CircularProgressIndicator());
                }
              }

              ticketsList.sort((a, b) {
                int t1 = 0; 
                int t2 = 0;
                if (a['purchasedAt'] is Timestamp) t1 = (a['purchasedAt'] as Timestamp).millisecondsSinceEpoch;
                else if (a['purchasedAt'] is int) t1 = a['purchasedAt'];
                if (b['purchasedAt'] is Timestamp) t2 = (b['purchasedAt'] as Timestamp).millisecondsSinceEpoch;
                else if (b['purchasedAt'] is int) t2 = b['purchasedAt'];
                return t2.compareTo(t1); 
              });

              if (ticketsList.isEmpty) {
                return const Center(child: Text("No tickets found."));
              }

              return Column(
                children: [
                  if (isOffline)
                    Container(
                      width: double.infinity,
                      color: Colors.red[100],
                      padding: const EdgeInsets.all(8),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_off, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text("Offline Mode - Showing saved tickets", style: TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: ticketsList.length,
                      itemBuilder: (ctx, index) {
                        var t = ticketsList[index];
                        
                        DateTime date = parseEventDate(t['date']);
                        bool isExpired = date.isBefore(DateTime.now());
                        bool isCancelled = t['status'] == 'cancelled';
                        bool isUpcoming = !isExpired && !isCancelled;

                        // Determine Card Color and Icon
                        Color iconColor = const Color(0xFF6C35DE);
                        Color statusColor = Colors.black;
                        if (isCancelled) {
                          iconColor = Colors.red;
                          statusColor = Colors.red;
                        } else if (isExpired) {
                          iconColor = Colors.grey;
                          statusColor = Colors.grey;
                        }
                
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          color: isCancelled ? Colors.red.shade50 : null,
                          child: ExpansionTile(
                            leading: Icon(
                              isCancelled ? Icons.cancel : (isExpired ? Icons.event_busy : Icons.qr_code),
                              color: iconColor
                            ),
                            title: Text(t['title'] ?? 'Ticket', style: TextStyle(decoration: isCancelled ? TextDecoration.lineThrough : null, color: isCancelled ? Colors.red : null)),
                            subtitle: Text(
                              isCancelled ? "CANCELLED - REFUNDED" : "${DateFormat('MMM dd, yyyy').format(date)} (Ticket #${index + 1})",
                              style: TextStyle(color: statusColor, fontWeight: isCancelled ? FontWeight.bold : FontWeight.normal),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: isCancelled
                                ? const Column(
                                    children: [
                                      Icon(Icons.money_off, size: 60, color: Colors.red),
                                      SizedBox(height: 10),
                                      Text("Event Cancelled", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
                                      Text("Amount has been refunded to your wallet.", style: TextStyle(color: Colors.grey)),
                                    ],
                                  )
                                : (isExpired 
                                    ? const Column(
                                        children: [
                                          Icon(Icons.history, size: 60, color: Colors.grey),
                                          SizedBox(height: 10),
                                          Text("Event Ended", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                        ],
                                      )
                                    : Column(
                                        children: [
                                          QrImageView(
                                            data: t['qrData'] ?? 'error',
                                            version: QrVersions.auto,
                                            size: 200.0,
                                          ),
                                          const SizedBox(height: 10),
                                          Text("ID: ${t['ticketId']}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                          
                                          // --- CANCEL BUTTON ADDED HERE ---
                                          if (isUpcoming) 
                                            Padding(
                                              padding: const EdgeInsets.only(top: 20),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: OutlinedButton.icon(
                                                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                                                  label: const Text("Cancel Ticket", style: TextStyle(color: Colors.red)),
                                                  style: OutlinedButton.styleFrom(
                                                    side: const BorderSide(color: Colors.red),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                                  ),
                                                  onPressed: () => _cancelTicket(
                                                    t['ticketId'], 
                                                    t['eventId'], 
                                                    (t['price'] ?? 0).toDouble(),
                                                    t['title'] ?? 'Unknown Event'
                                                  ), 
                                                ),
                                              ),
                                            )
                                        ],
                                      )
                                  ),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          
          if (_isProcessingCancellation)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            )
        ],
      ),
    );
  }
}

// --- WALLET SCREEN ---
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _isProcessing = false;
  final CardEditController _cardEditController = CardEditController();

  Future<void> _handleStripeTopUp(double amount) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isProcessing = true);
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('createPaymentIntent');
      final result = await callable.call(<String, dynamic>{'amount': (amount * 100).toInt(), 'currency': 'pkr'});
      final clientSecret = result.data['clientSecret'];
      if (kIsWeb) { await _payOnWeb(clientSecret); } else { await _payOnMobile(clientSecret); }
      await _updateWalletBalance(amount);
      if(mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payment Successful!"), backgroundColor: Colors.green)); }
    } on StripeException catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Stripe Error: ${e.error.localizedMessage}"), backgroundColor: Colors.red));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _payOnMobile(String clientSecret) async {
    await Stripe.instance.initPaymentSheet(paymentSheetParameters: SetupPaymentSheetParameters(paymentIntentClientSecret: clientSecret, merchantDisplayName: 'City Vibes', style: ThemeMode.system));
    await Stripe.instance.presentPaymentSheet();
  }

  Future<void> _payOnWeb(String clientSecret) async {
    if (!_cardEditController.complete) throw "Please enter valid card details";
    await Stripe.instance.confirmPayment(paymentIntentClientSecret: clientSecret, data: const PaymentMethodParams.card(paymentMethodData: PaymentMethodData()));
  }

  Future<void> _updateWalletBalance(double amount) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      transaction.update(userRef, {'walletBalance': FieldValue.increment(amount)});
      DocumentReference historyRef = userRef.collection('wallet_history').doc();
      transaction.set(historyRef, {'type': 'credit', 'amount': amount, 'description': 'Stripe Top Up', 'date': Timestamp.now()});
    });
  }

  void _showCustomAmountDialog(BuildContext context, {double? initialAmount}) {
    TextEditingController controller = TextEditingController();
    if(initialAmount != null) controller.text = initialAmount.toStringAsFixed(0);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Top Up Wallet"),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(prefixText: "PKR ", hintText: "Amount"),
              ),
              if(kIsWeb) ...[
                const SizedBox(height: 20),
                const Align(alignment: Alignment.centerLeft, child: Text("Card Details", style: TextStyle(fontWeight: FontWeight.bold))),
                const SizedBox(height: 10),
                Container(
                  height: 50,
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                  child: CardField(controller: _cardEditController, enablePostalCode: false),
                ),
              ]
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _isProcessing ? null : () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            // --- UPDATED STYLE HERE ---
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(140, 45), 
              backgroundColor: const Color(0xFF6C35DE), 
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            // --------------------------
            onPressed: _isProcessing ? null : () { double? val = double.tryParse(controller.text); if (val != null && val > 0) _handleStripeTopUp(val); },
            child: _isProcessing 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text("Pay Now"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text("My Wallet"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
              builder: (context, snapshot) {
                double balance = 0.0;
                if(snapshot.hasData && snapshot.data!.exists) {
                   balance = (snapshot.data!.data() as Map<String, dynamic>)['walletBalance']?.toDouble() ?? 0.0;
                }
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(color: const Color(0xFF1E232C), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Total Balance", style: TextStyle(color: Colors.grey, fontSize: 14)), const SizedBox(height: 8), Text("PKR ${balance.toStringAsFixed(0)}", style: GoogleFonts.poppins(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold))]),
                );
              }
            ),
            const SizedBox(height: 30),
            const Text("Top Up Wallet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildTopUpChip(500), _buildTopUpChip(1000), _buildTopUpChip(2000)]),
            const SizedBox(height: 15),
            TextField(readOnly: true, onTap: _isProcessing ? null : () => _showCustomAmountDialog(context), decoration: InputDecoration(hintText: "Enter Custom Amount", filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16))),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE91E63), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                onPressed: _isProcessing ? null : () => _showCustomAmountDialog(context),
                child: _isProcessing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Text("Top Up Now", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            const Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock, size: 14, color: Colors.grey), SizedBox(width: 5), Text("Secure Payment via Stripe", style: TextStyle(color: Colors.grey, fontSize: 12))])),
            const SizedBox(height: 30),
            const Text("Transaction History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).collection('wallet_history').orderBy('date', descending: true).snapshots(),
              builder: (context, snapshot) {
                if(!snapshot.hasData) return const SizedBox();
                var docs = snapshot.data!.docs;
                if(docs.isEmpty) return const Text("No transactions yet.");
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (ctx, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    bool isCredit = data['type'] == 'credit';
                    return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: CircleAvatar(backgroundColor: isCredit ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: isCredit ? Colors.green : Colors.red)), title: Text(data['description'] ?? "Transaction"), subtitle: Text(DateFormat('MMM dd, yyyy • hh:mm a').format((data['date'] as Timestamp).toDate())), trailing: Text("${isCredit ? '+' : '-'} Rs. ${data['amount']}", style: TextStyle(fontWeight: FontWeight.bold, color: isCredit ? Colors.green : Colors.red))));
                  },
                );
              }
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTopUpChip(double amount) {
    return GestureDetector(
      onTap: _isProcessing ? null : () => _showCustomAmountDialog(context, initialAmount: amount),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10), color: Theme.of(context).cardColor), child: Text("+$amount", style: const TextStyle(fontWeight: FontWeight.bold))),
    );
  }
}

// --- TAB 4: PROFILE (WITH CHANGE PASSWORD UPDATED) ---
class AttendeeProfileTab extends StatefulWidget {
  const AttendeeProfileTab({super.key});

  @override
  State<AttendeeProfileTab> createState() => _AttendeeProfileTabState();
}

class _AttendeeProfileTabState extends State<AttendeeProfileTab> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _addressController = TextEditingController(); 
  
  LatLng _selectedLocation = const LatLng(31.5204, 74.3587); 
  final MapController _mapController = MapController();
  
  bool _isLoading = false;
  String? _base64Image; 
  
  int _activeTickets = 0;
  int _favoriteEvents = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    
    if(user != null) {
      _emailController.text = user.email ?? "";
    }

    double? lat = prefs.getDouble('user_lat');
    double? lng = prefs.getDouble('user_lng');
    String? city = prefs.getString('user_city');

    if(lat != null && lng != null) {
      setState(() {
         _selectedLocation = LatLng(lat, lng);
         _addressController.text = city ?? "Selected Location";
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if(mounted) _mapController.move(_selectedLocation, 14);
      });
    }

    if(user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().listen((doc) {
        if(doc.exists && mounted) {
          var data = doc.data() as Map<String, dynamic>;
          setState(() {
            if (_nameController.text.isEmpty) _nameController.text = data['name'] ?? "";
            if (_phoneController.text.isEmpty) _phoneController.text = data['phone'] ?? "";
            if (_emailController.text.isEmpty) _emailController.text = data['email'] ?? user.email ?? "";
            
            _base64Image = data['profileImageBase64']; 
            
            if(lat == null && data['latitude'] != null) {
               _selectedLocation = LatLng(data['latitude'], data['longitude']);
               _addressController.text = data['city'] ?? "Saved Location";
               _mapController.move(_selectedLocation, 14);
            }
          });
        }
      });

      FirebaseFirestore.instance.collection('tickets').where('userId', isEqualTo: user.uid).snapshots().listen((snap) {
        if(mounted) setState(() => _activeTickets = snap.docs.length);
      });

      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('favorites').snapshots().listen((snap) {
        if(mounted) setState(() => _favoriteEvents = snap.docs.length);
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 20, maxWidth: 400);
    if(pickedFile != null) {
      final bytes = await pickedFile.readAsBytes(); 
      setState(() {
        _base64Image = base64Encode(bytes);
      });
    }
  }

  Future<void> _showLocationSearchDialog() async {
    TextEditingController searchCtl = TextEditingController();
    List<dynamic> searchResults = [];
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setStateSB) {
          
          Future<void> performSearch() async {
            if (searchCtl.text.trim().isEmpty) return;
            setStateSB(() => isLoading = true);
            
            try {
              final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${searchCtl.text}&format=json&limit=5&addressdetails=1');
              final response = await http.get(
                url,
                headers: {'User-Agent': 'CityVibeApp/1.0'},
              );

              if (response.statusCode == 200) {
                final data = json.decode(response.body);
                setStateSB(() { 
                  searchResults = data; 
                  isLoading = false;
                });
              } else {
                setStateSB(() => isLoading = false);
              }
            } catch (e) {
              setStateSB(() => isLoading = false);
            }
          }

          return AlertDialog(
            title: const Text("Search Location"),
            content: SizedBox(
              width: double.maxFinite,
              height: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => performSearch(),
                    decoration: InputDecoration(
                      hintText: "e.g. Emporium Mall",
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: performSearch,
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  if (isLoading)
                    const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())
                  else if (searchResults.isNotEmpty)
                    Expanded(
                      child: ListView.separated(
                        itemCount: searchResults.length,
                        separatorBuilder: (c, i) => const Divider(),
                        itemBuilder: (ctx, i) {
                          final place = searchResults[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.location_on, color: Colors.red),
                            title: Text(place['display_name'].split(',')[0], style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(place['display_name'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            onTap: () => Navigator.pop(ctx, place),
                          );
                        },
                      ),
                    )
                  else 
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Text("Enter a location and tap search.", style: TextStyle(color: Colors.grey)),
                    )
                ],
              ),
            ),
          );
        });
      }
    ).then((place) {
      if (place != null) {
        setState(() {
          double lat = double.parse(place['lat']);
          double lon = double.parse(place['lon']);
          _selectedLocation = LatLng(lat, lon);
          _addressController.text = place['display_name'].split(',')[0]; 
          _mapController.move(_selectedLocation, 14);
        });
      }
    });
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;

      await prefs.setDouble('user_lat', _selectedLocation.latitude);
      await prefs.setDouble('user_lng', _selectedLocation.longitude);
      await prefs.setString('user_city', _addressController.text);

      if(user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': _nameController.text,
          'phone': _phoneController.text,
          'email': _emailController.text, 
          'role': 'attendee', 
          'profileImageBase64': _base64Image, 
          'latitude': _selectedLocation.latitude, 
          'longitude': _selectedLocation.longitude,
          'city': _addressController.text
        }, SetOptions(merge: true));
      }
      
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Saved!"), backgroundColor: Colors.green));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearAllFavorites() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    bool? confirm = await showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("Clear Favorites?"),
        content: const Text("This will remove all liked events. This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Clear", style: TextStyle(color: Colors.red))),
        ],
      )
    );

    if (confirm == true) {
      try {
        var collection = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('favorites');
        var snapshots = await collection.get();
        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (var doc in snapshots.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All favorites cleared!")));
      } catch(e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _openFavorites() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold( 
      appBar: AppBar(
        title: const Text("Favorite Events"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            tooltip: "Clear All",
            onPressed: _clearAllFavorites,
          )
        ],
      ),
      body: const FavoritesList(),
    )));
  }

  // --- UPDATED: CHANGE PASSWORD LOGIC WITH EYE ICONS & PADDING ---
  void _showChangePasswordDialog() {
    final TextEditingController currentPassController = TextEditingController();
    final TextEditingController newPassController = TextEditingController();
    final TextEditingController confirmPassController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isUpdating = false;

    // Visibility States
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Change Password", style: TextStyle(fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("For security, please enter your current password.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 15),
                    
                    // Current Password
                    TextFormField(
                      controller: currentPassController,
                      obscureText: obscureCurrent,
                      decoration: InputDecoration(
                        labelText: "Current Password",
                        prefixIcon: const Icon(Icons.lock_outline),
                        // --- SHOW PASSWORD ICON ---
                        suffixIcon: IconButton(
                          icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      validator: (val) => val!.isEmpty ? "Required" : null,
                    ),
                    const SizedBox(height: 10),

                    // New Password
                    TextFormField(
                      controller: newPassController,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: "New Password",
                        prefixIcon: const Icon(Icons.key),
                        // --- SHOW PASSWORD ICON ---
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      validator: (val) => val!.length < 6 ? "Min 6 chars" : null,
                    ),
                    const SizedBox(height: 10),

                    // Confirm Password
                    TextFormField(
                      controller: confirmPassController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: "Confirm Password",
                        prefixIcon: const Icon(Icons.check_circle_outline),
                        // --- SHOW PASSWORD ICON ---
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      validator: (val) => val != newPassController.text ? "Passwords do not match" : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isUpdating ? null : () async {
                    if (formKey.currentState!.validate()) {
                      setDialogState(() => isUpdating = true);
                      try {
                        User? user = FirebaseAuth.instance.currentUser;
                        String email = user!.email!;
                        
                        AuthCredential credential = EmailAuthProvider.credential(
                          email: email, 
                          password: currentPassController.text.trim()
                        );
                        await user.reauthenticateWithCredential(credential);

                        await user.updatePassword(newPassController.text.trim());

                        if(mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Password updated successfully!"), backgroundColor: Colors.green)
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isUpdating = false);
                        String errorMsg = e.toString();
                        if(errorMsg.contains('wrong-password')) errorMsg = "Current password is incorrect.";
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red)
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C35DE),
                    foregroundColor: Colors.white,
                    // --- ADDED WIDTH/PADDING HERE ---
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isUpdating 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : const Text("Update", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ImageProvider? imageProvider;
    if (_base64Image != null) {
      try { imageProvider = MemoryImage(base64Decode(_base64Image!)); } catch(e) {}
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50, 
                      backgroundColor: Colors.grey[300], 
                      backgroundImage: imageProvider,
                      child: imageProvider == null ? const Icon(Icons.person, size: 50, color: Colors.white) : null
                    ),
                    const Positioned(bottom: 0, right: 0, child: CircleAvatar(backgroundColor: Color(0xFF6C35DE), radius: 15, child: Icon(Icons.camera_alt, size: 15, color: Colors.white)))
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6C35DE), Color(0xFF8B5FE3)]), borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: const Color(0xFF6C35DE).withOpacity(0.3), blurRadius: 8)]),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(children: [Icon(Icons.account_balance_wallet, color: Colors.white), SizedBox(width: 10), Text("My Wallet", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16)
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Active Tickets", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 5),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text("$_activeTickets", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const Icon(Icons.confirmation_number_outlined, color: Colors.green)
                        ])
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: GestureDetector(
                    onTap: _openFavorites,
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Favorite Events", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 5),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text("$_favoriteEvents", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            const Icon(Icons.favorite, color: Colors.red)
                          ])
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),

            _buildLabel("Full Name"),
            TextFormField(controller: _nameController, decoration: _inputDeco(Icons.person)),
            const SizedBox(height: 16),

            _buildLabel("Contact Phone"),
            TextFormField(
              controller: _phoneController, 
              keyboardType: TextInputType.phone,
              maxLength: 11,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDeco(Icons.phone).copyWith(counterText: ""),
            ),
            const SizedBox(height: 16),
            
            _buildLabel("Email"),
            TextFormField(controller: _emailController, readOnly: true, decoration: _inputDeco(Icons.email)),
            const SizedBox(height: 16),
            
            _buildLabel("Location"),
            TextFormField(
              readOnly: true,
              controller: _addressController,
              onTap: _showLocationSearchDialog,
              decoration: const InputDecoration(labelText: "Location Name (Tap to Search)", prefixIcon: Icon(Icons.location_on), suffixIcon: Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
            ),
            const SizedBox(height: 10),
            
            Container(
              height: 180, 
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withOpacity(0.3))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation, 
                    initialZoom: 13,
                    onTap: (_, p) => setState(() => _selectedLocation = p) 
                  ),
                  children: [
                    TileLayer(urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"), 
                    MarkerLayer(markers: [Marker(point: _selectedLocation, child: const Icon(Icons.location_on, color: Colors.red, size: 40))])
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // --- CHANGE PASSWORD BUTTON ---
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.lock_reset, color: Color(0xFF6C35DE)),
                label: const Text("Change Password", style: TextStyle(color: Color(0xFF6C35DE), fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFF6C35DE)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 20),
            SwitchListTile(title: const Text("Dark Mode"), value: isDark, onChanged: (val) => authProvider.toggleTheme(val)),

            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _isLoading ? null : _saveProfile, child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Save Changes"))),
            
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  authProvider.signOut();
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red), 
                  padding: const EdgeInsets.symmetric(vertical: 16), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)) 
                ),
                child: const Text("Logout", style: TextStyle(color: Colors.red)) 
              )
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)));

  InputDecoration _inputDeco(IconData icon) {
    return InputDecoration(prefixIcon: Icon(icon), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));
  }
}

// --- FAVORITES LIST ---
class FavoritesList extends StatelessWidget {
  const FavoritesList({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please login to view favorites"));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('favorites').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text("No favorites yet."));
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (ctx, index) {
            var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return EventCard(data: data); 
          },
        );
      },
    );
  }
}