import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'auth_provider.dart';
import 'login_screen.dart';
import 'main.dart'; 

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>(); 
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  
  int _selectedRole = 0; 
  bool _isLoading = false;
  bool _isObscure = true; 

  void _handleSignUp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isLoading = true);
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    String role = _selectedRole == 1 ? 'organizer' : 'attendee';

    try {
      final user = await _authService.signUp(
        _emailController.text.trim(),
        _passController.text.trim(),
        _nameController.text.trim(),
        role,
      );

      if (user != null && mounted) {
        authProvider.setRole(role);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthChecker()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(e.toString().split(']').last.trim()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form( 
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    "Create Account",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    "Welcome to the city's best event platform",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 24),

                // Toggle Switch
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                          child: const Center(
                            child: Text("Login", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C35DE),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text("Sign Up", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Role Selection
                Row(
                  children: [
                    Expanded(child: _roleCard("Attendee", Icons.people_outline, 0)),
                    const SizedBox(width: 16),
                    Expanded(child: _roleCard("Organizer", Icons.edit_calendar_outlined, 1)),
                  ],
                ),
                const SizedBox(height: 24),

                // -- NAME FIELD --
                TextFormField(
                  controller: _nameController,
                  validator: (value) => value!.isEmpty ? "Name is required" : null,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person_outline),
                    labelText: "Full Name",
                    hintText: "e.g. John Doe", 
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // -- EMAIL FIELD --
                TextFormField(
                  controller: _emailController,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Email is required';
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
                    return null;
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.email_outlined),
                    labelText: "Email Address",
                    hintText: "e.g. name@example.com",
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // -- PASSWORD FIELD WITH RED POLICY TEXT --
                TextFormField(
                  controller: _passController,
                  obscureText: _isObscure,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Password is required';
                    if (value.length < 8) return 'Password must be at least 8 characters';
                    if (!value.contains(RegExp(r'[A-Z]'))) return 'Missing uppercase letter';
                    if (!value.contains(RegExp(r'[0-9]'))) return 'Missing number';
                    if (!value.contains(RegExp(r'[!@#\$&*~]'))) return 'Missing special character';
                    return null;
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_isObscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _isObscure = !_isObscure),
                    ),
                    labelText: "Password",
                    hintText: "Enter a strong password",
                    
                    // --- CHANGED TO RED ---
                    helperText: "Policy: 8+ chars, 1 Uppercase, 1 Number, 1 Special Char (@#\$)",
                    helperMaxLines: 2,
                    helperStyle: const TextStyle(color: Colors.red, fontSize: 11),
                    
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Sign Up Button
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C35DE),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Create Account", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Already have an account? "),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                      child: const Text("Login", style: TextStyle(color: Color(0xFF6C35DE), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleCard(String title, IconData icon, int index) {
    bool isSelected = _selectedRole == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEDE7F6) : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xFF6C35DE) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
             if(!isSelected) BoxShadow(color: Colors.grey.shade200, blurRadius: 4, offset: const Offset(0, 2))
          ]
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: isSelected ? const Color(0xFF6C35DE) : Colors.grey.shade700),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF6C35DE) : Colors.black87)),
          ],
        ),
      ),
    );
  }
}