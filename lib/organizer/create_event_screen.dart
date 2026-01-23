import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart'; // Added for picking images
import 'package:http/http.dart' as http; 

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  final TextEditingController _locationNameController = TextEditingController();

  final List<String> _genres = [
    'Music', 'Business', 'Sports', 'Education', 'Technology', 
    'Art', 'Food & Drink', 'Health', 'Fashion', 'Community'
  ];
  String _selectedGenre = 'Music';

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  
  // Changed from URL string to Base64 String
  String? _base64Image; 
  
  LatLng _location = const LatLng(31.5204, 74.3587); 
  final MapController _mapController = MapController();
  bool _isUploading = false;

  // --- NEW IMAGE PICKER LOGIC (Like Profile) ---
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // imageQuality: 50 is important to keep Firestore document size low
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50); 
    
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _base64Image = base64Encode(bytes);
      });
    }
  }

  // --- SEARCH LOGIC ---
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
          _location = LatLng(lat, lon);
          _locationNameController.text = place['display_name'].split(',')[0]; 
          _mapController.move(_location, 14);
        });
      }
    });
  }

  void _publishEvent() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Check for _base64Image instead of URL
    if (_base64Image == null || _selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cover Photo, Date and Time are required")));
      return;
    }

    if(_locationNameController.text.isEmpty) {
      _locationNameController.text = "Pinned Location";
    }

    setState(() => _isUploading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      
      final DateTime finalDateTime = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
        _selectedTime!.hour, _selectedTime!.minute,
      );

      await FirebaseFirestore.instance.collection('events').add({
        'organizerId': uid,
        'title': _titleController.text,
        'genre': _selectedGenre,
        'price': int.parse(_priceController.text),
        'description': _descController.text,
        'date': Timestamp.fromDate(finalDateTime), 
        
        // Save Base64 Image
        'imageBase64': _base64Image, 
        
        'latitude': _location.latitude,
        'longitude': _location.longitude,
        'locationName': _locationNameController.text, 
        'sales': 0, 
        'revenue': 0,
        'shares': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Event Created Successfully!"), backgroundColor: Colors.green));
        _titleController.clear(); _priceController.clear(); _descController.clear(); _locationNameController.clear();
        setState(() { 
          _base64Image = null; _selectedDate = null; _selectedTime = null; _isUploading = false; 
        });
      }
    } catch (e) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prepare Image Provider for display
    ImageProvider? coverImage;
    if (_base64Image != null) {
      coverImage = MemoryImage(base64Decode(_base64Image!));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Create New Event")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 50),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- UPDATED IMAGE DISPLAY ---
              GestureDetector(
                onTap: _pickImage, // Opens PC/Mobile Gallery
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                    // Display Memory Image if selected
                    image: coverImage != null ? DecorationImage(image: coverImage, fit: BoxFit.cover) : null,
                  ),
                  child: _base64Image == null 
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center, 
                        children: [
                          Icon(Icons.add_photo_alternate, size: 40, color: Color(0xFF6C35DE)), 
                          SizedBox(height: 10),
                          Text("Upload Cover Photo (PC/Gallery)")
                        ]
                      ) 
                    : null,
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(controller: _titleController, decoration: const InputDecoration(labelText: "Event Title", prefixIcon: Icon(Icons.title)), validator: (v)=>v!.isEmpty?"Required":null),
              const SizedBox(height: 16),

              Row(children: [
                Expanded(
                  child: DropdownButtonFormField(
                    value: _selectedGenre, 
                    isExpanded: true,
                    items: _genres.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(), 
                    onChanged: (v)=>setState(()=>_selectedGenre=v!), 
                    decoration: const InputDecoration(
                      labelText: "Genre", 
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                      isDense: true
                    )
                  )
                ),
                const SizedBox(width: 8), 
                Expanded(
                  child: TextFormField(
                    controller: _priceController, 
                    keyboardType: TextInputType.number, 
                    decoration: const InputDecoration(
                      labelText: "Price (Rs.)", 
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                      isDense: true
                    ), 
                    validator: (v)=>v!.isEmpty?"Required":null
                  )
                ),
              ]),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2030));
                        if (d != null) setState(() => _selectedDate = d);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [const Icon(Icons.calendar_month, color: Color(0xFF6C35DE)), const SizedBox(width: 8), Text(_selectedDate == null ? "Select Date" : DateFormat('MMM dd').format(_selectedDate!))]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                        if (t != null) setState(() => _selectedTime = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [const Icon(Icons.access_time_rounded, color: Color(0xFF6C35DE)), const SizedBox(width: 8), Text(_selectedTime == null ? "Select Time" : _selectedTime!.format(context))]),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              TextFormField(controller: _descController, maxLines: 3, decoration: const InputDecoration(labelText: "Description", alignLabelWithHint: true)),
              const SizedBox(height: 20),

              TextFormField(
                controller: _locationNameController,
                readOnly: true, 
                onTap: _showLocationSearchDialog, 
                decoration: const InputDecoration(
                  labelText: "Location Name (Tap to Search)", 
                  prefixIcon: Icon(Icons.location_on),
                  suffixIcon: Icon(Icons.search, color: Color(0xFF6C35DE))
                ),
              ),
              const SizedBox(height: 10),

              Container(
                height: 180,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey.withOpacity(0.3))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(initialCenter: _location, initialZoom: 13, onTap: (_, p) => setState(() => _location = p)),
                    children: [
                      TileLayer(urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"),
                      MarkerLayer(markers: [Marker(point: _location, child: const Icon(Icons.location_on, color: Colors.red, size: 40))]),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 30),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _isUploading ? null : _publishEvent, child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text("Publish Event"))),
            ],
          ),
        ),
      ),
    );
  }
}