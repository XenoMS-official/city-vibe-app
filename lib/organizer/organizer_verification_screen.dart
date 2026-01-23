import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Needed for InputFormatter
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../auth_provider.dart';

class OrganizerVerificationScreen extends StatefulWidget {
  const OrganizerVerificationScreen({super.key});

  @override
  State<OrganizerVerificationScreen> createState() => _OrganizerVerificationScreenState();
}

class _OrganizerVerificationScreenState extends State<OrganizerVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _agreedToPolicy = false;
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String? _validateCNIC(String? value) {
    if (value == null || value.isEmpty) return "CNIC is required";
    if (value.length != 15) return "Invalid CNIC Format";
    return null;
  }

  void _submitVerification() async {
    if (_formKey.currentState!.validate() && _agreedToPolicy) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'isVerified': true,
            'cnic': _cnicController.text,
            'phone': _phoneController.text,
          });
        }
        if (mounted) {
           context.read<AuthProvider>().verifyOrganizer();
           // Show success dialog...
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } else if (!_agreedToPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please accept the terms to proceed.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verification Center")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Identity Verification", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Text("To ensure safety, we require valid identification.", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              
              // -- CNIC FIELD WITH AUTO-HYPHEN --
              TextFormField(
                controller: _cnicController,
                keyboardType: TextInputType.number,
                // THE AUTO FORMATTER IS ADDED HERE
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  CnicInputFormatter(), // Custom formatter added below
                  LengthLimitingTextInputFormatter(15),
                ],
                decoration: InputDecoration(
                  labelText: "CNIC Number",
                  hintText: "35202-1234567-1", // Light example
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  // Professional helper
                  helperText: "Format: xxxxx-xxxxxxx-x (Auto-formatted)",
                ),
                validator: _validateCNIC,
              ),
              
              const SizedBox(height: 20),
              
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "Phone Number",
                  hintText: "0300 1234567",
                  prefixIcon: const Icon(Icons.phone_android),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) => val!.isEmpty ? "Phone required" : null,
              ),
              
              const SizedBox(height: 30),
              
              // -- STRICT POLICY BOX --
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50, 
                  borderRadius: BorderRadius.circular(15), 
                  border: Border.all(color: Colors.red.shade200, width: 1.5)
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.gavel, color: Colors.red),
                        const SizedBox(width: 10),
                        Text("LEGAL NOTICE", style: GoogleFonts.poppins(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 16))
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "By submitting this form, you legally certify that the CNIC and Phone Number belong to you. Misrepresentation is a criminal offense and will result in an immediate and permanent ban from the platform.",
                      style: GoogleFonts.poppins(color: Colors.red.shade900, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("I have read and agree to the policy.", style: TextStyle(fontSize: 14)),
                value: _agreedToPolicy,
                onChanged: (val) => setState(() => _agreedToPolicy = val!),
                activeColor: const Color(0xFF6C35DE),
              ),
              
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, 
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitVerification, 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C35DE),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  child: const Text("Verify & Continue", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                )
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- CNIC AUTO FORMATTER CLASS ---
class CnicInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;

    if (newValue.selection.baseOffset == 0) {
      return newValue;
    }

    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex <= 5) {
        if (nonZeroIndex == 5 && text.length != nonZeroIndex) {
          buffer.write('-'); // Add dash after 5th digit
        }
      } else if (nonZeroIndex <= 12) {
        if (nonZeroIndex == 12 && text.length != nonZeroIndex) {
          buffer.write('-'); // Add dash after 12th digit
        }
      }
    }

    var string = buffer.toString();
    return newValue.copyWith(
        text: string,
        selection: TextSelection.collapsed(offset: string.length)
    );
  }
}