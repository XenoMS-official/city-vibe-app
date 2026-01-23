import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../auth_provider.dart'; 
import 'organizer_wallet_screen.dart'; 

class OrganizerProfileScreen extends StatefulWidget {
  const OrganizerProfileScreen({super.key});

  @override
  State<OrganizerProfileScreen> createState() => _OrganizerProfileScreenState();
}

class _OrganizerProfileScreenState extends State<OrganizerProfileScreen> {
  // --- CONTROLLERS ---
  final TextEditingController _personalNameController = TextEditingController();
  final TextEditingController _orgNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  
  String? _base64Image;
  bool _isLoading = false;
  
  // Verification Status
  bool _isVerified = false; 

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  // --- FETCH EXISTING DATA ---
  void _fetchProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if(doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _personalNameController.text = data['name'] ?? '';
          _orgNameController.text = data['orgName'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _cnicController.text = data['cnic'] ?? ''; 
          _addressController.text = data['address'] ?? '';
          _base64Image = data['profileImageBase64'];
          
          // Fetch Verified Status
          _isVerified = data['isVerified'] ?? false;
        });
      }
    }
  }

  // --- IMAGE PICKER ---
  Future<void> _pickImage() async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() => _base64Image = base64Encode(bytes));
      }
  }

  // --- SAVE PROFILE ---
  void _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'name': _personalNameController.text,
          'orgName': _orgNameController.text,
          'phone': _phoneController.text,
          'address': _addressController.text,
          'cnic': _cnicController.text, 
          'profileImageBase64': _base64Image,
        });
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Saved Successfully!"), backgroundColor: Colors.green));
      } catch (e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      } finally {
        if(mounted) setState(() => _isLoading = false);
      }
    }
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
      try {
        imageProvider = MemoryImage(base64Decode(_base64Image!));
      } catch (e) {
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Organizer Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. PROFILE IMAGE STACK
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60, 
                    backgroundColor: Colors.grey[300], 
                    backgroundImage: imageProvider, 
                    child: imageProvider == null ? const Icon(Icons.person, size: 60, color: Colors.white) : null
                  ),
                  
                  const Positioned(
                    bottom: 0, right: 0, 
                    child: CircleAvatar(backgroundColor: Color(0xFF6C35DE), radius: 18, child: Icon(Icons.camera_alt, color: Colors.white, size: 18))
                  ),

                  if (_isVerified)
                    Positioned(
                      top: 0, 
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white, 
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified, color: Colors.blue, size: 28),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // 2. ORG NAME DISPLAY
            Text(
              _orgNameController.text.isNotEmpty ? _orgNameController.text : "Organization Name", 
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
            ),
            
            const SizedBox(height: 30),

            // 3. WALLET BUTTON
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrganizerWalletScreen())),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6C35DE), Color(0xFF8B5FE3)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: const Color(0xFF6C35DE).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_wallet, color: Colors.white), 
                        SizedBox(width: 15), 
                        Text("Organizer Wallet", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
                      ]
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            // 4. INPUT FIELDS
            _buildTextField("Full Name", _personalNameController, Icons.person),
            const SizedBox(height: 15),
            _buildTextField("Organization Name", _orgNameController, Icons.business),
            const SizedBox(height: 15),
            _buildTextField("Phone Number", _phoneController, Icons.phone, type: TextInputType.phone),
            const SizedBox(height: 15),
            _buildTextField("CNIC Number", _cnicController, Icons.badge, type: TextInputType.number), 
            const SizedBox(height: 15),
            _buildTextField("Address / Location", _addressController, Icons.location_on),
            
            const SizedBox(height: 20),

            // --- 5. CHANGE PASSWORD BUTTON ---
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

            // 6. DARK MODE SWITCH
            SwitchListTile(
              title: const Text("Dark Mode"),
              value: isDark,
              onChanged: (val) => authProvider.toggleTheme(val),
            ),

            const SizedBox(height: 20),

            // 7. SAVE BUTTON
            SizedBox(
              width: double.infinity, 
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile, 
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C35DE),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                child: _isLoading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Text("Save Changes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))
              )
            ),
            const SizedBox(height: 15),

            // 8. LOGOUT BUTTON
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

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {TextInputType type = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C35DE))),
      ),
    );
  }
}