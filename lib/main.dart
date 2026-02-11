import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SecureEncryptorApp());
}

class SecureEncryptorApp extends StatelessWidget {
  const SecureEncryptorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Secure Encryptor",
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.green,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController plainController = TextEditingController();
  final TextEditingController secretController = TextEditingController();
  final TextEditingController encryptedController = TextEditingController();

  String status = "";

  encrypt.Key generateKey(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  encrypt.IV generateIV() {
    final random = Random.secure();
    final ivBytes = List<int>.generate(16, (_) => random.nextInt(256));
    return encrypt.IV(Uint8List.fromList(ivBytes));
  }

  void encryptText() {
    final plainText = plainController.text.trim();
    final secretKey = secretController.text.trim();

    if (plainText.isEmpty || secretKey.isEmpty) {
      setState(() {
        status = "❌ Enter message and secret key";
      });
      return;
    }

    try {
      final key = generateKey(secretKey);
      final iv = generateIV();

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final encryptedText = encrypter.encrypt(plainText, iv: iv);

      // Output Format => base64IV:base64EncryptedMessage
      final output = "${base64Encode(iv.bytes)}:${encryptedText.base64}";

      setState(() {
        encryptedController.text = output;
        status = "✅ Encrypted Successfully";
      });
    } catch (e) {
      setState(() {
        status = "❌ Encryption Failed";
      });
    }
  }

  void decryptText() {
    final encryptedText = encryptedController.text.trim();
    final secretKey = secretController.text.trim();

    if (encryptedText.isEmpty || secretKey.isEmpty) {
      setState(() {
        status = "❌ Enter encrypted text and secret key";
      });
      return;
    }

    try {
      final parts = encryptedText.split(":");

      if (parts.length != 2) {
        setState(() {
          status = "❌ Invalid encrypted format";
        });
        return;
      }

      final iv = encrypt.IV(base64Decode(parts[0]));
      final encryptedMessage = parts[1];

      final key = generateKey(secretKey);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final decryptedText = encrypter.decrypt64(encryptedMessage, iv: iv);

      setState(() {
        plainController.text = decryptedText;
        status = "✅ Decrypted Successfully";
      });
    } catch (e) {
      setState(() {
        status = "❌ Wrong secret key or invalid message";
      });
    }
  }

  Future<void> copyEncrypted() async {
    final text = encryptedController.text.trim();
    if (text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));

    setState(() {
      status = "📋 Copied encrypted text";
    });
  }

  Future<void> pasteEncrypted() async {
    final data = await Clipboard.getData("text/plain");
    if (data == null || data.text == null) return;

    setState(() {
      encryptedController.text = data.text!;
      status = "📥 Pasted encrypted text";
    });
  }

  void clearAll() {
    setState(() {
      plainController.clear();
      secretController.clear();
      encryptedController.clear();
      status = "🧹 Cleared";
    });
  }

  @override
  void dispose() {
    plainController.dispose();
    secretController.dispose();
    encryptedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🛡️ Secure Encryptor"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Plain Text Message", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: plainController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: "Type message here...",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            const Text("Secret Key", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: secretController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: "Enter secret key...",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: encryptText,
              child: const Text("🔒 Encrypt"),
            ),

            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: decryptText,
              child: const Text("🔓 Decrypt"),
            ),

            const SizedBox(height: 18),

            const Text(
              "Encrypted Output (Copy this to WhatsApp)",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: encryptedController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: "Encrypted text will appear here...",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: copyEncrypted,
                    icon: const Icon(Icons.copy),
                    label: const Text("Copy"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: pasteEncrypted,
                    icon: const Icon(Icons.paste),
                    label: const Text("Paste"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            ElevatedButton.icon(
              onPressed: clearAll,
              icon: const Icon(Icons.delete),
              label: const Text("Clear"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),

            const SizedBox(height: 20),

            Text(
              status,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: status.contains("❌")
                    ? Colors.redAccent
                    : Colors.greenAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
