import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinLockScreen extends StatefulWidget {
  final VoidCallback onSuccess;

  const PinLockScreen({super.key, required this.onSuccess});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final TextEditingController pinController = TextEditingController();
  String savedPin = "";

  @override
  void initState() {
    super.initState();
    loadPin();
  }

  Future<void> loadPin() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      savedPin = prefs.getString("pin_code") ?? "";
    });
  }

  void verifyPin() {
    final entered = pinController.text.trim();

    if (savedPin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No PIN set. Enable PIN in settings.")),
      );
      return;
    }

    if (entered == savedPin) {
      widget.onSuccess();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Wrong PIN ❌")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 50),
                  const SizedBox(height: 10),
                  const Text(
                    "Enter PIN",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      hintText: "Enter 4-6 digit PIN",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: verifyPin,
                      child: const Text("Unlock"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
