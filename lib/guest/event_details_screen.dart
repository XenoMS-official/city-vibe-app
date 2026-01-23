import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:typed_data'; // Needed for Uint8List

// --- HELPER FUNCTIONS ---
bool isValidUrl(String? url) {
  if (url == null || url.isEmpty || url == "null") return false;
  return url.startsWith("http://") || url.startsWith("https://");
}

DateTime parseEventDate(dynamic rawDate) {
  if (rawDate is Timestamp) return rawDate.toDate();
  if (rawDate is int) return DateTime.fromMillisecondsSinceEpoch(rawDate);
  return DateTime.now();
}

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
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('favorites')
          .doc(widget.eventData['id'])
          .get();
      if (mounted) setState(() => _isLiked = doc.exists);
    } catch (e) {
      print("Error checking like: $e");
    }
  }

  void _toggleLike() async {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login to favorite events!")));
      return;
    }
    setState(() => _isLiked = !_isLiked);
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('favorites')
        .doc(widget.eventData['id']);

    if (_isLiked) {
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

  void _shareEvent() {
    Share.share(
        "Check out this event: ${widget.eventData['title']} on City Vibe!");
  }

  void _initiatePurchase() async {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login to book tickets!")));
      return;
    }
    int quantity = 1;
    double unitPrice =
        double.tryParse(widget.eventData['price'].toString()) ?? 0.0;

    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text("How many tickets?"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                          onPressed: () =>
                              setStateSB(() { if (quantity > 1) quantity--; }),
                          icon: const Icon(Icons.remove_circle_outline)),
                      Text("$quantity",
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                      IconButton(
                          onPressed: () =>
                              setStateSB(() { if (quantity < 10) quantity++; }),
                          icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text("Total: Rs. ${unitPrice * quantity}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6C35DE))),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _processBooking(quantity, unitPrice * quantity);
                  },
                  child: const Text("Confirm"),
                )
              ],
            );
          });
        });
  }

  Future<void> _processBooking(int quantity, double totalPrice) async {
    setState(() => _isBooking = true);

    try {
      final attendeeRef =
          FirebaseFirestore.instance.collection('users').doc(user!.uid);
      final eventRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventData['id']);
      final String? organizerId = widget.eventData['organizerId'];

      if (organizerId == null) throw Exception("Organizer ID missing");
      final organizerRef =
          FirebaseFirestore.instance.collection('users').doc(organizerId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot attendeeSnap = await transaction.get(attendeeRef);
        DocumentSnapshot eventSnap = await transaction.get(eventRef);

        if (!attendeeSnap.exists) throw Exception("User does not exist!");
        if (!eventSnap.exists) throw Exception("Event no longer exists!");

        double currentBalance = (attendeeSnap.data()
                as Map<String, dynamic>)['walletBalance']?.toDouble() ?? 0.0;
        if (currentBalance < totalPrice) throw Exception("Insufficient Funds");

        double platformFee = totalPrice * 0.02; // 2% Cut
        double organizerEarning = totalPrice - platformFee;

        // Deduct from Attendee
        transaction.update(
            attendeeRef, {'walletBalance': currentBalance - totalPrice});

        // Add to Organizer
        transaction.update(organizerRef,
            {'walletBalance': FieldValue.increment(organizerEarning)});

        // Update Event
        transaction.update(eventRef, {
          'sales': FieldValue.increment(quantity),
          'revenue': FieldValue.increment(organizerEarning)
        });

        // Generate Tickets
        for (int i = 0; i < quantity; i++) {
          String ticketId =
              FirebaseFirestore.instance.collection('tickets').doc().id;
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
            'qrData':
                "$ticketId|${user!.uid}|${widget.eventData['id']}|Unique$i",
            'purchasedAt': Timestamp.now(),
            'status': 'active'
          };
          transaction.set(
              FirebaseFirestore.instance.collection('tickets').doc(ticketId),
              ticketData);
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Tickets Booked!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString().contains("Insufficient Funds")
            ? "Insufficient Funds! Please Top Up."
            : "Booking Failed: $e";
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime date = parseEventDate(widget.eventData['date']);
    String priceDisplay = widget.eventData['price']?.toString() ?? "0";

    // --- FIX 1: LOCATION TEXT ---
    // If the event doesn't have a name, default to "Lahore, Pakistan"
    String locationText = "Lahore, Pakistan"; 
    if (widget.eventData['locationName'] != null) {
      String val = widget.eventData['locationName'].toString().trim();
      if (val.isNotEmpty && val != "null") {
        locationText = val;
      }
    }

    // --- FIX 2: IMAGE CRASH PROTECTION ---
    Widget headerImage;
    Uint8List? imageBytes;

    try {
      if (widget.eventData['imageBase64'] != null &&
          widget.eventData['imageBase64'].toString().isNotEmpty) {
        imageBytes = base64Decode(widget.eventData['imageBase64']);
      }
    } catch (e) {
      print("Image Decode Error: $e"); // Logs error but prevents crash
    }

    if (imageBytes != null) {
      headerImage = Image.memory(
        imageBytes,
        height: 250,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (c, o, s) => Container(
            height: 250,
            color: Colors.grey[300],
            child: const Icon(Icons.broken_image)),
      );
    } else if (isValidUrl(widget.eventData['imageUrl'])) {
      headerImage = Image.network(
        widget.eventData['imageUrl'],
        height: 250,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (c, o, s) => Container(
            height: 250,
            color: Colors.grey,
            child: const Icon(Icons.broken_image)),
      );
    } else {
      headerImage = Container(
          height: 250,
          width: double.infinity,
          color: Colors.grey[300],
          child: const Icon(Icons.image, size: 60, color: Colors.grey));
    }

    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Image and Buttons
                Stack(
                  children: [
                    headerImage,
                    Positioned(
                        top: 40,
                        left: 10,
                        child: CircleAvatar(
                            backgroundColor: Colors.white,
                            child: IconButton(
                                icon: const Icon(Icons.arrow_back,
                                    color: Colors.black),
                                onPressed: () => Navigator.pop(context)))),
                    Positioned(
                        top: 40,
                        right: 10,
                        child: Row(children: [
                          CircleAvatar(
                              backgroundColor: Colors.white,
                              child: IconButton(
                                  icon: Icon(
                                      _isLiked
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color:
                                          _isLiked ? Colors.red : Colors.grey),
                                  onPressed: _toggleLike)),
                          const SizedBox(width: 8),
                          CircleAvatar(
                              backgroundColor: Colors.white,
                              child: IconButton(
                                  icon: const Icon(Icons.share,
                                      color: Colors.black),
                                  onPressed: _shareEvent))
                        ])),
                  ],
                ),
                
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(widget.eventData['title'] ?? "Event",
                          style: GoogleFonts.poppins(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      
                      // Date
                      Row(children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 5),
                        Text(DateFormat('EEEE, MMM d, yyyy • hh:mm a')
                            .format(date))
                      ]),
                      const SizedBox(height: 10),

                      // --- LOCATION TEXT DISPLAYED HERE ---
                      Row(children: [
                        const Icon(Icons.location_on,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 5),
                        Expanded(
                            child: Text(locationText, // Shows "Lahore..." if empty
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)))
                      ]),

                      const SizedBox(height: 20),
                      Text("About Event",
                          style: GoogleFonts.poppins(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text(
                          widget.eventData['description'] ??
                              "No description available.",
                          style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 30),

                      // Map Section
                      if (widget.eventData['latitude'] != null &&
                          widget.eventData['longitude'] != null)
                        Container(
                          height: 150,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.grey.shade300)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: FlutterMap(
                              options: MapOptions(
                                  initialCenter: LatLng(
                                      widget.eventData['latitude'],
                                      widget.eventData['longitude']),
                                  initialZoom: 14),
                              children: [
                                TileLayer(
                                    urlTemplate:
                                        "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"),
                                MarkerLayer(markers: [
                                  Marker(
                                      point: LatLng(
                                          widget.eventData['latitude'],
                                          widget.eventData['longitude']),
                                      child: const Icon(Icons.location_on,
                                          color: Colors.red, size: 40))
                                ])
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
          
          // Bottom Price Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: const Offset(0, -5))
                  ]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Price",
                          style: TextStyle(color: Colors.grey)),
                      Text("Rs. $priceDisplay",
                          style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF6C35DE))),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C35DE),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: _isBooking ? null : _initiatePurchase,
                    child: _isBooking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text("Book Ticket",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
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