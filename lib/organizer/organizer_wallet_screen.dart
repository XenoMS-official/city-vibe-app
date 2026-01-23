import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:math'; // For random transaction ID
// STRIPE IMPORTS
import 'package:flutter_stripe/flutter_stripe.dart' hide Card; 
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 

class OrganizerWalletScreen extends StatefulWidget {
  const OrganizerWalletScreen({super.key});

  @override
  State<OrganizerWalletScreen> createState() => _OrganizerWalletScreenState();
}

class _OrganizerWalletScreenState extends State<OrganizerWalletScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isProcessing = false;
  
  // Stripe Controller
  final CardEditController _cardEditController = CardEditController();

  // Pakistani Banks List
  final List<String> _pakistaniBanks = [
    'Meezan Bank',
    'HBL (Habib Bank Ltd)',
    'UBL (United Bank Ltd)',
    'MCB Bank',
    'Bank Alfalah',
    'Allied Bank',
    'Askari Bank',
    'Standard Chartered',
    'Easypaisa (Telenor)',
    'JazzCash (Mobilink)',
  ];

  // ==================================================
  // 1. TOP UP LOGIC (Fixed Integration Error)
  // ==================================================
  
  void _showTopUpDialog() {
    TextEditingController amountCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing while editing
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // Rounded Dialog
        title: const Text("Top Up Wallet"),
        content: SizedBox(
          width: 400, // Fixed width for Web stability
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: "PKR ", 
                  hintText: "Amount",
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
              ),
              if(kIsWeb) ...[
                const SizedBox(height: 20),
                const Align(alignment: Alignment.centerLeft, child: Text("Card Details", style: TextStyle(fontWeight: FontWeight.bold))),
                const SizedBox(height: 10),
                // Container is crucial for Web Element rendering
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CardField(
                    controller: _cardEditController,
                    enablePostalCode: false,
                    autofocus: true, 
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                  ),
                ),
                const SizedBox(height: 5),
                const Text("Use Test Card: 4242 4242 4242 4242", style: TextStyle(color: Colors.grey, fontSize: 10)),
              ]
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.only(bottom: 20, right: 20),
        actions: [
          TextButton(
            onPressed: _isProcessing ? null : () => Navigator.pop(ctx), 
            child: const Text("Cancel", style: TextStyle(color: Colors.grey))
          ),
          
          // --- PAY NOW BUTTON EDITED HERE ---
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C35DE),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30), // Pill shape
              ),
            ),
            onPressed: _isProcessing ? null : () {
              double? val = double.tryParse(amountCtrl.text);
              if (val != null && val > 0) {
                // On Web, we don't pop immediately to let the Promise resolve
                if(!kIsWeb) Navigator.pop(ctx); 
                _handleStripeTopUp(val, ctx);
              }
            },
            child: _isProcessing 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text("Pay Now", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Future<void> _handleStripeTopUp(double amount, BuildContext dialogContext) async {
    setState(() => _isProcessing = true);
    try {
      // 1. Get Client Secret
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('createPaymentIntent');
      final result = await callable.call(<String, dynamic>{'amount': (amount * 100).toInt(), 'currency': 'pkr'});
      final clientSecret = result.data['clientSecret'];

      // 2. Confirm Payment
      if (kIsWeb) {
        if (!_cardEditController.complete) throw "Please enter valid card details (4242...)";
        
        await Stripe.instance.confirmPayment(
          paymentIntentClientSecret: clientSecret, 
          data: const PaymentMethodParams.card(paymentMethodData: PaymentMethodData())
        );
        // If successful, close dialog manually on web
        if(mounted && Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);
      } else {
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret, 
            merchantDisplayName: 'City Vibes', 
            style: ThemeMode.system
          )
        );
        await Stripe.instance.presentPaymentSheet();
      }

      // 3. Update Wallet (Credit)
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
        transaction.update(userRef, {'walletBalance': FieldValue.increment(amount)});
        DocumentReference historyRef = userRef.collection('wallet_history').doc();
        transaction.set(historyRef, {
          'type': 'credit',
          'amount': amount,
          'description': 'Wallet Top Up',
          'date': Timestamp.now(),
        });
      });

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Top Up Successful!"), backgroundColor: Colors.green));

    } on StripeException catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Stripe Error: ${e.error.localizedMessage}"), backgroundColor: Colors.red));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isProcessing = false);
    }
  }

  // ==================================================
  // 2. WITHDRAWAL LOGIC (Professional Slip)
  // ==================================================
  
  void _showWithdrawDialog(double currentBalance) {
    final amountCtrl = TextEditingController();
    final accountTitleCtrl = TextEditingController();
    final accountNoCtrl = TextEditingController();
    String? selectedBank;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Withdraw Funds"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Bank Transfer Details", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6C35DE))),
                  const SizedBox(height: 15),
                  
                  // BANK DROPDOWN
                  DropdownButtonFormField<String>(
                    value: selectedBank,
                    items: _pakistaniBanks.map((bank) => DropdownMenuItem(value: bank, child: Text(bank, style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (val) => setStateSB(() => selectedBank = val),
                    decoration: InputDecoration(
                      labelText: "Select Bank",
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5)
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // ACCOUNT TITLE
                  TextField(
                    controller: accountTitleCtrl, 
                    decoration: InputDecoration(
                      labelText: "Account Title (Name)",
                      filled: true,
                      fillColor: Colors.grey[100], 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5)
                    )
                  ),
                  const SizedBox(height: 10),
                  
                  // ACCOUNT NUMBER
                  TextField(
                    controller: accountNoCtrl, 
                    decoration: InputDecoration(
                      labelText: "Account Number / IBAN", 
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5)
                    )
                  ),
                  const SizedBox(height: 15),
                  const Divider(),
                  const SizedBox(height: 10),
                  
                  // AMOUNT
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      prefixText: "PKR ", 
                      labelText: "Withdraw Amount",
                      filled: true,
                      fillColor: Colors.grey[100], 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5)
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text("Available Balance: PKR ${currentBalance.toStringAsFixed(0)}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.only(bottom: 20, right: 20),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), 
                child: const Text("Cancel", style: TextStyle(color: Colors.grey))
              ),
              
              // --- WITHDRAW BUTTON EDITED HERE ---
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C35DE), 
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30), // Pill Shape
                  ),
                ),
                onPressed: () async {
                  // VALIDATION
                  double? amount = double.tryParse(amountCtrl.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Amount"))); return;
                  }
                  if (amount > currentBalance) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Insufficient Funds"))); return;
                  }
                  if (selectedBank == null || accountTitleCtrl.text.isEmpty || accountNoCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all bank details"))); return;
                  }

                  Navigator.pop(ctx);
                  await _processWithdrawal(amount, selectedBank!, accountTitleCtrl.text, accountNoCtrl.text);
                },
                child: const Text("Withdraw", style: TextStyle(fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      ),
    );
  }

  Future<void> _processWithdrawal(double amount, String bank, String title, String accNo) async {
    setState(() => _isProcessing = true);
    
    // Simulate Banking Delay
    await Future.delayed(const Duration(seconds: 3));

    try {
      String txnId = "TXN-${Random().nextInt(999999)}-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
        DocumentSnapshot snap = await transaction.get(userRef);
        double balance = (snap.data() as Map)['walletBalance']?.toDouble() ?? 0.0;
        
        if (balance < amount) throw Exception("Insufficient Funds");

        // Debit Wallet
        transaction.update(userRef, {'walletBalance': balance - amount});
        
        // Add History
        DocumentReference histRef = userRef.collection('wallet_history').doc();
        transaction.set(histRef, {
          'type': 'debit',
          'amount': amount,
          'description': 'Withdrawal to $bank',
          'details': '$title ($accNo)',
          'txnId': txnId,
          'date': Timestamp.now(),
        });
      });

      if (mounted) _showProfessionalSlip(amount, bank, title, accNo, txnId);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if(mounted) setState(() => _isProcessing = false);
    }
  }

  // --- PROFESSIONAL RECEIPT SLIP ---
  void _showProfessionalSlip(double amount, String bank, String title, String accNo, String txnId) {
    DateTime now = DateTime.now();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        backgroundColor: Colors.white,
        child: Stack(
          children: [
            // WATERMARK
            Positioned.fill(
              child: Center(
                child: Transform.rotate(
                  angle: -0.5,
                  child: Opacity(
                    opacity: 0.1,
                    child: Text("SUCCESSFUL", style: GoogleFonts.poppins(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.green)),
                  ),
                ),
              ),
            ),
            
            // CONTENT
            Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 60),
                  const SizedBox(height: 10),
                  Text("Withdrawal Receipt", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 5),
                  Text("City Vibe Wallet", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  
                  const SizedBox(height: 20),
                  const Divider(thickness: 1), 
                  const SizedBox(height: 10),
                  
                  _slipRow("Amount Withdrawn", "PKR ${amount.toStringAsFixed(2)}", isBold: true, color: Colors.red),
                  _slipRow("Transaction Date", DateFormat('MMM dd, yyyy - hh:mm a').format(now)),
                  _slipRow("Transaction ID", txnId),
                  
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        _slipRow("Bank", bank, isSmall: true),
                        _slipRow("Account Title", title, isSmall: true),
                        _slipRow("Account No", accNo, isSmall: true),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  const Text("Funds will be transferred within 24 hours.", style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 20),
                  
                  SizedBox(
                    width: double.infinity, 
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C35DE), foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx), 
                      child: const Text("Download Slip")
                    )
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slipRow(String label, String value, {bool isBold = false, Color? color, bool isSmall = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isSmall ? 2 : 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700], fontSize: isSmall ? 12 : 14)),
          Flexible(
            child: Text(value, style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? Colors.black,
              fontSize: isSmall ? 12 : 14
            ), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isProcessing) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text("Organizer Wallet")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
          builder: (context, snapshot) {
            double balance = 0.0;
            if(snapshot.hasData && snapshot.data!.exists) {
                balance = (snapshot.data!.data() as Map<String, dynamic>)['walletBalance']?.toDouble() ?? 0.0;
            }
            return Column(
              children: [
                // --- PURPLE WALLET CARD ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C35DE), // PURPLE COLOR
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]
                  ),
                  child: Column(
                    children: [
                      const Text("Available Balance", style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 10),
                      Text("PKR ${balance.toStringAsFixed(0)}", style: GoogleFonts.poppins(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      
                      // BUTTONS
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF6C35DE)),
                              onPressed: () => _showWithdrawDialog(balance),
                              icon: const Icon(Icons.download),
                              label: const Text("Withdraw"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.black26, foregroundColor: Colors.white),
                              onPressed: _showTopUpDialog,
                              icon: const Icon(Icons.add),
                              label: const Text("Top Up"),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                const Align(alignment: Alignment.centerLeft, child: Text("Transaction History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                const SizedBox(height: 10),
                
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).collection('wallet_history').orderBy('date', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if(!snapshot.hasData) return const SizedBox();
                    if(snapshot.data!.docs.isEmpty) return const Text("No transactions found.");
                    
                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (ctx, index) {
                        var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                        bool isCredit = data['type'] == 'credit';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isCredit ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                              child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: isCredit ? Colors.green : Colors.red),
                            ),
                            title: Text(data['description'] ?? "Transaction"),
                            subtitle: Text(DateFormat('MMM dd, hh:mm a').format((data['date'] as Timestamp).toDate())),
                            trailing: Text(
                              "${isCredit?'+':'-'} ${data['amount'].toStringAsFixed(0)}",
                              style: TextStyle(color: isCredit?Colors.green:Colors.red, fontWeight: FontWeight.bold)
                            ),
                          ),
                        );
                      }
                    );
                  }
                )
              ],
            );
          }
        ),
      ),
    );
  }
}