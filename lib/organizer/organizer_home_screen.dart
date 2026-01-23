import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart'; 
import 'package:http/http.dart' as http;
import 'create_event_screen.dart';

class OrganizerHomeScreen extends StatefulWidget {
  const OrganizerHomeScreen({super.key});

  @override
  State<OrganizerHomeScreen> createState() => _OrganizerHomeScreenState();
}

class _OrganizerHomeScreenState extends State<OrganizerHomeScreen> {
  DateTime _selectedDate = DateTime.now();
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isCancelling = false;

  final List<String> _genres = [
    'All', 'Music', 'Business', 'Sports', 'Education', 'Technology', 
    'Art', 'Food & Drink', 'Health', 'Fashion', 'Community'
  ];

  List<DateTime> _getCalendarDays() {
    return List.generate(7, (index) => DateTime.now().add(Duration(days: index)));
  }

  // --- 1. CANCEL EVENT LOGIC ---
  void _confirmCancelEvent(String eventId, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Cancel Event?"),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Are you sure you want to cancel this event?"),
            SizedBox(height: 10),
            Text("⚠ 500 PKR Fine will be deducted.", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            Text("⚠ Attendees will receive a 100% refund.", style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text("Go Back", style: TextStyle(color: Colors.grey))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, 
              foregroundColor: Colors.white,
              // Fixed the "Trapped" look with padding and shape
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _processCancellation(eventId, title);
            },
            child: const Text("Confirm Cancel", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Future<void> _processCancellation(String eventId, String title) async {
    setState(() => _isCancelling = true);
    try {
      final organizerRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot orgSnap = await transaction.get(organizerRef);
        double currentBal = (orgSnap.data() as Map)['walletBalance']?.toDouble() ?? 0.0;
        transaction.update(organizerRef, {'walletBalance': currentBal - 500});
        
        DocumentReference histRef = organizerRef.collection('wallet_history').doc();
        transaction.set(histRef, {
          'type': 'debit', 'amount': 500, 'description': 'Fine: Cancelled "$title"', 'date': Timestamp.now()
        });
        
        transaction.set(organizerRef.collection('notifications').doc(), {
          'title': 'Event Cancelled', 'message': 'Cancelled "$title". 500 PKR fine deducted.', 'type': 'alert', 'createdAt': Timestamp.now(), 'read': false
        });
      });

      final ticketsSnapshot = await FirebaseFirestore.instance.collection('tickets').where('eventId', isEqualTo: eventId).get();
      if (ticketsSnapshot.docs.isNotEmpty) {
        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (var ticket in ticketsSnapshot.docs) {
          String userId = ticket['userId'];
          double price = (ticket['price'] ?? 0).toDouble();
          DocumentReference attendeeRef = FirebaseFirestore.instance.collection('users').doc(userId);
          
          batch.update(attendeeRef, {'walletBalance': FieldValue.increment(price)});
          batch.set(attendeeRef.collection('wallet_history').doc(), {
            'type': 'credit', 'amount': price, 'description': 'Refund: Cancelled "$title"', 'date': Timestamp.now()
          });
          batch.set(attendeeRef.collection('notifications').doc(), {
            'title': 'Event Cancelled', 'message': 'Event "$title" cancelled. Full refund added.', 'type': 'alert', 'createdAt': Timestamp.now(), 'read': false
          });
        }
        await batch.commit();
      }

      await FirebaseFirestore.instance.collection('events').doc(eventId).delete();
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Event Cancelled. Refunds Processed."), backgroundColor: Colors.red));

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if(mounted) setState(() => _isCancelling = false);
    }
  }

  // --- 2. EDIT DIALOG ---
  void _editEventDialog(String eventId, Map<String, dynamic> data) {
    final titleCtl = TextEditingController(text: data['title']);
    final priceCtl = TextEditingController(text: data['price'].toString());
    final descCtl = TextEditingController(text: data['description']);
    final locationNameCtl = TextEditingController(text: data['locationName'] ?? 'Pinned Location');
    
    String editGenre = _genres.contains(data['genre']) ? data['genre'] : 'Music';
    DateTime editDate = (data['date'] as Timestamp).toDate();
    TimeOfDay editTime = TimeOfDay.fromDateTime(editDate);
    LatLng editLoc = LatLng(data['latitude'] ?? 31.5, data['longitude'] ?? 74.3);
    
    // Existing image (could be base64 or url)
    String? currentBase64 = data['imageBase64'];
    String? newBase64ToUpload;

    final MapController editMapCtl = MapController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setStateModal) {

          // --- PICK NEW IMAGE IN EDIT ---
          Future<void> pickNewImage() async {
            final picker = ImagePicker();
            final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
            if (picked != null) {
              final bytes = await picked.readAsBytes();
              setStateModal(() {
                newBase64ToUpload = base64Encode(bytes);
              });
            }
          }

          Future<void> showSearch() async {
            TextEditingController searchCtl = TextEditingController();
            List<dynamic> searchResults = [];
            bool isLoading = false;

            await showDialog(
              context: context,
              builder: (innerCtx) {
                return StatefulBuilder(builder: (c, setInnerState) {
                  Future<void> performSearch() async {
                    if (searchCtl.text.trim().isEmpty) return;
                    setInnerState(() => isLoading = true);
                    try {
                      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${searchCtl.text}&format=json&limit=5&addressdetails=1');
                      final response = await http.get(url, headers: {'User-Agent': 'CityVibeApp/1.0'});
                      
                      if (response.statusCode == 200) {
                        setInnerState(() { 
                          searchResults = json.decode(response.body); 
                          isLoading = false;
                        });
                      } else {
                         setInnerState(() => isLoading = false);
                      }
                    } catch (e) {
                      setInnerState(() => isLoading = false);
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
                              hintText: "e.g. Wapda Town",
                              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: performSearch),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if(isLoading) const CircularProgressIndicator()
                          else if(searchResults.isNotEmpty)
                            Expanded(
                              child: ListView.separated(
                                itemCount: searchResults.length,
                                separatorBuilder: (c,i) => const Divider(),
                                itemBuilder: (c, i) {
                                  final place = searchResults[i];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.location_on, color: Colors.red),
                                    title: Text(place['display_name'].split(',')[0], style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(place['display_name'], maxLines: 2, overflow: TextOverflow.ellipsis),
                                    onTap: () => Navigator.pop(innerCtx, place),
                                  );
                                },
                              ),
                            )
                        ],
                      ),
                    ),
                  );
                });
              }
            ).then((place) {
              if (place != null) {
                setStateModal(() {
                  double lat = double.parse(place['lat']);
                  double lon = double.parse(place['lon']);
                  editLoc = LatLng(lat, lon);
                  locationNameCtl.text = place['display_name'].split(',')[0];
                  editMapCtl.move(editLoc, 14); 
                });
              }
            });
          }

          // Decide what image to show in Edit Dialog
          ImageProvider displayImage;
          if (newBase64ToUpload != null) {
            displayImage = MemoryImage(base64Decode(newBase64ToUpload!));
          } else if (currentBase64 != null && currentBase64.isNotEmpty) {
            displayImage = MemoryImage(base64Decode(currentBase64));
          } else if (data['imageUrl'] != null) {
            displayImage = NetworkImage(data['imageUrl']);
          } else {
             displayImage = const AssetImage('assets/placeholder.png'); // Fallback
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text("Edit Event"),
              actions: [
                IconButton(
                  icon: const Icon(Icons.check), 
                  onPressed: () async {
                    DateTime finalDT = DateTime(editDate.year, editDate.month, editDate.day, editTime.hour, editTime.minute);
                    
                    Map<String, dynamic> updateData = {
                      'title': titleCtl.text,
                      'price': int.tryParse(priceCtl.text) ?? 0,
                      'description': descCtl.text,
                      'genre': editGenre,
                      'date': Timestamp.fromDate(finalDT),
                      'locationName': locationNameCtl.text,
                      'latitude': editLoc.latitude, 
                      'longitude': editLoc.longitude,
                    };

                    // Only update image if changed
                    if (newBase64ToUpload != null) {
                      updateData['imageBase64'] = newBase64ToUpload;
                    }

                    await FirebaseFirestore.instance.collection('events').doc(eventId).update(updateData);
                    if(mounted) Navigator.pop(context);
                  }
                )
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // --- CLICKABLE IMAGE IN EDIT ---
                  GestureDetector(
                    onTap: pickNewImage,
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(image: displayImage, fit: BoxFit.cover),
                      ),
                      child: const Center(
                        child: CircleAvatar(
                          backgroundColor: Colors.white70,
                          child: Icon(Icons.edit, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(controller: titleCtl, decoration: const InputDecoration(labelText: "Title")),
                  const SizedBox(height: 10),
                  TextFormField(controller: priceCtl, decoration: const InputDecoration(labelText: "Price")),
                  const SizedBox(height: 10),
                  DropdownButtonFormField(
                    value: editGenre,
                    items: _genres.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setStateModal(() => editGenre = v!),
                    decoration: const InputDecoration(labelText: "Genre"),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: Text(DateFormat('MMM dd').format(editDate)),
                        onPressed: () async {
                          final d = await showDatePicker(context: context, initialDate: editDate, firstDate: DateTime.now(), lastDate: DateTime(2030));
                          if(d!=null) setStateModal(()=> editDate = d);
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.access_time),
                        label: Text(editTime.format(context)),
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: editTime);
                          if(t!=null) setStateModal(()=> editTime = t);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  TextFormField(
                    controller: locationNameCtl, 
                    readOnly: true, 
                    onTap: showSearch, 
                    decoration: const InputDecoration(
                      labelText: "Location Name (Tap to Search)", 
                      prefixIcon: Icon(Icons.location_on),
                      suffixIcon: Icon(Icons.search, color: Color(0xFF6C35DE))
                    )
                  ),
                  const SizedBox(height: 10),
                  
                  TextFormField(controller: descCtl, maxLines: 2, decoration: const InputDecoration(labelText: "Description")),
                  const SizedBox(height: 10),
                  
                  SizedBox(
                    height: 150,
                    child: FlutterMap(
                      mapController: editMapCtl, 
                      options: MapOptions(initialCenter: editLoc, initialZoom: 13, onTap: (_, p) => setStateModal(() => editLoc = p)),
                      children: [
                        TileLayer(urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"),
                        MarkerLayer(markers: [Marker(point: editLoc, child: const Icon(Icons.location_on, color: Colors.red, size: 40))]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    List<DateTime> calendarDays = _getCalendarDays();

    return Scaffold(
      appBar: AppBar(title: const Text("My Schedule"), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateEventScreen())),
        backgroundColor: Theme.of(context).primaryColor,
        label: const Text("Create Event", style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isCancelling 
      ? const Center(child: CircularProgressIndicator())
      : Column(
        children: [
          Container(
            height: 100,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: calendarDays.length,
              itemBuilder: (context, index) {
                DateTime date = calendarDays[index];
                bool isSelected = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDate = date),
                  child: Container(
                    width: 65,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isSelected ? Colors.transparent : Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('EEE').format(date).toUpperCase(), style: TextStyle(fontSize: 11, color: isSelected?Colors.white:Colors.grey)),
                        Text(DateFormat('dd').format(date), style: TextStyle(fontSize: 18, color: isSelected?Colors.white:Colors.black, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('events').where('organizerId', isEqualTo: user?.uid).snapshots(), 
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final events = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['date'] == null) return false;
                  DateTime eventDate = (data['date'] as Timestamp).toDate().toLocal();
                  return eventDate.year == _selectedDate.year && eventDate.month == _selectedDate.month && eventDate.day == _selectedDate.day;
                }).toList();

                if (events.isEmpty) return const Center(child: Text("No events on this day.", style: TextStyle(color: Colors.grey)));

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: events.length,
                  itemBuilder: (ctx, index) {
                    final data = events[index].data() as Map<String, dynamic>;
                    
                    // --- DETERMINE IMAGE TYPE ---
                    Widget imageWidget;
                    if (data['imageBase64'] != null && data['imageBase64'].toString().isNotEmpty) {
                      imageWidget = Image.memory(base64Decode(data['imageBase64']), width: 60, height: 60, fit: BoxFit.cover);
                    } else if (data['imageUrl'] != null) {
                      imageWidget = Image.network(data['imageUrl'], width: 60, height: 60, fit: BoxFit.cover);
                    } else {
                      imageWidget = const Icon(Icons.image, size: 40, color: Colors.grey);
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: imageWidget, // Updated Image Logic
                        ),
                        title: Text(data['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${DateFormat('hh:mm a').format((data['date'] as Timestamp).toDate())} • ${data['locationName'] ?? 'Unknown'}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editEventDialog(events[index].id, data),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              tooltip: "Cancel Event",
                              onPressed: () => _confirmCancelEvent(events[index].id, data['title']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}