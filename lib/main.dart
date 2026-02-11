import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pin_lock.dart';

void main() {
  runApp(const SecureEncryptorApp());
}

class SecureEncryptorApp extends StatelessWidget {
  const SecureEncryptorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Secure Encryptor",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.green,
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
      ),
      home: const SplashAuthGate(),
    );
  }
}

class SplashAuthGate extends StatefulWidget {
  const SplashAuthGate({super.key});

  @override
  State<SplashAuthGate> createState() => _SplashAuthGateState();
}

class _SplashAuthGateState extends State<SplashAuthGate> {
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _initAuth();
  }

  Future<void> _initAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool("biometric_enabled") ?? false;
    final pinEnabled = prefs.getBool("pin_enabled") ?? false;

    if (!biometricEnabled && !pinEnabled) {
      _goHome();
      return;
    }

    // Try biometric first if enabled
    if (biometricEnabled) {
      final auth = LocalAuthentication();

      try {
        final canCheck = await auth.canCheckBiometrics;
        final isDeviceSupported = await auth.isDeviceSupported();

        if (canCheck && isDeviceSupported) {
          final success = await auth.authenticate(
            localizedReason: "Authenticate to open Secure Encryptor",
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true,
            ),
          );

          if (success) {
            _goHome();
            return;
          }
        }
      } catch (e) {
        // Biometric failed, try PIN if enabled
      }
    }

    // Fallback to PIN if enabled
    if (pinEnabled) {
      _goPinLock();
    } else {
      SystemNavigator.pop();
    }
  }

  void _goHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _goPinLock() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PinLockScreen(
          onSuccess: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: loading
            ? const CircularProgressIndicator()
            : const Text("Loading..."),
      ),
    );
  }
}

class HistoryItem {
  final String type; // encrypt / decrypt
  final String plainText;
  final String encryptedText;
  final DateTime createdAt;

  HistoryItem({
    required this.type,
    required this.plainText,
    required this.encryptedText,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      "type": type,
      "plainText": plainText,
      "encryptedText": encryptedText,
      "createdAt": createdAt.toIso8601String(),
    };
  }

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      type: json["type"],
      plainText: json["plainText"],
      encryptedText: json["encryptedText"],
      createdAt: DateTime.parse(json["createdAt"]),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentIndex = 0;

  final TextEditingController plainController = TextEditingController();
  final TextEditingController secretController = TextEditingController();
  final TextEditingController encryptedController = TextEditingController();

  String qrData = "";

  List<HistoryItem> history = [];

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  encrypt.Key _generateKey(String password) {
    final digest = sha256.convert(utf8.encode(password));
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  encrypt.IV _generateIV() {
    final random = Random.secure();
    final ivBytes = List<int>.generate(16, (_) => random.nextInt(256));
    return encrypt.IV(Uint8List.fromList(ivBytes));
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.redAccent : Colors.green,
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList("history", encoded);
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList("history") ?? [];

    setState(() {
      history = data
          .map((e) => HistoryItem.fromJson(jsonDecode(e)))
          .toList()
          .reversed
          .toList();
    });
  }

  Future<void> addHistoryItem(HistoryItem item) async {
    setState(() {
      history.insert(0, item);
      if (history.length > 50) {
        history = history.sublist(0, 50);
      }
    });

    await saveHistory();
  }

  void encryptText() {
    final plainText = plainController.text.trim();
    final secretKey = secretController.text.trim();

    if (plainText.isEmpty) {
      _showSnack("Enter plain text message", error: true);
      return;
    }

    if (secretKey.length < 4) {
      _showSnack("Secret key must be minimum 4 characters", error: true);
      return;
    }

    try {
      final key = _generateKey(secretKey);
      final iv = _generateIV();

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final encryptedText = encrypter.encrypt(plainText, iv: iv);

      final output = "${base64Encode(iv.bytes)}:${encryptedText.base64}";

      setState(() {
        encryptedController.text = output;
        qrData = output;
      });

      addHistoryItem(
        HistoryItem(
          type: "encrypt",
          plainText: plainText,
          encryptedText: output,
          createdAt: DateTime.now(),
        ),
      );

      _showSnack("Encrypted Successfully ✅");
    } catch (e) {
      _showSnack("Encryption Failed ❌", error: true);
    }
  }

  String normalizeEncryptedText(String input) {
    String cleaned = input.trim();

    // Remove extra spaces/new lines copied from WhatsApp
    cleaned = cleaned.replaceAll("\n", "");
    cleaned = cleaned.replaceAll(" ", "");

    // Sometimes WhatsApp adds weird invisible chars
    cleaned = cleaned.replaceAll("\u200B", "");
    cleaned = cleaned.replaceAll("\u200C", "");
    cleaned = cleaned.replaceAll("\u200D", "");

    return cleaned;
  }

  void decryptText() {
    final encryptedText = normalizeEncryptedText(encryptedController.text);
    final secretKey = secretController.text.trim();

    if (encryptedText.isEmpty) {
      _showSnack("Paste encrypted message first", error: true);
      return;
    }

    if (secretKey.isEmpty) {
      _showSnack("Enter secret key", error: true);
      return;
    }

    try {
      final parts = encryptedText.split(":");
      if (parts.length != 2) {
        _showSnack("Invalid encrypted format", error: true);
        return;
      }

      final iv = encrypt.IV(base64Decode(parts[0]));
      final encryptedData = parts[1];

      final key = _generateKey(secretKey);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      final decryptedText = encrypter.decrypt64(encryptedData, iv: iv);

      setState(() {
        plainController.text = decryptedText;
      });

      addHistoryItem(
        HistoryItem(
          type: "decrypt",
          plainText: decryptedText,
          encryptedText: encryptedText,
          createdAt: DateTime.now(),
        ),
      );

      _showSnack("Decrypted Successfully 🔓");
    } catch (e) {
      _showSnack("Wrong key or invalid message ❌", error: true);
    }
  }

  Future<void> copyEncrypted() async {
    final text = encryptedController.text.trim();
    if (text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));
    _showSnack("Encrypted message copied 📋");
  }

  Future<void> pasteEncrypted() async {
    final data = await Clipboard.getData("text/plain");
    if (data?.text == null) return;

    setState(() {
      encryptedController.text = data!.text!;
      qrData = data.text!;
    });

    _showSnack("Pasted from clipboard 📥");
  }

  Future<void> shareEncrypted() async {
    final text = encryptedController.text.trim();
    if (text.isEmpty) {
      _showSnack("Nothing to share", error: true);
      return;
    }

    await Share.share(text);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("history");

    setState(() {
      history.clear();
    });

    _showSnack("History cleared 🧹");
  }

  Future<void> exportHistoryFile() async {
    if (history.isEmpty) {
      _showSnack("No history to export", error: true);
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/secure_history.txt");

    final buffer = StringBuffer();
    buffer.writeln("Secure Encryptor History Export");
    buffer.writeln("==================================\n");

    for (final item in history) {
      buffer.writeln("TYPE: ${item.type.toUpperCase()}");
      buffer.writeln("TIME: ${item.createdAt}");
      buffer.writeln("PLAIN: ${item.plainText}");
      buffer.writeln("ENCRYPTED: ${item.encryptedText}");
      buffer.writeln("----------------------------------\n");
    }

    await file.writeAsString(buffer.toString());

    await Share.shareXFiles([
      XFile(file.path),
    ], text: "My Secure Encryptor History");

    _showSnack("History exported successfully 📤");
  }

  Future<void> deleteHistoryItem(int index) async {
    setState(() {
      history.removeAt(index);
    });

    await saveHistory();
    _showSnack("Deleted");
  }

  void clearAll() {
    setState(() {
      plainController.clear();
      secretController.clear();
      encryptedController.clear();
      qrData = "";
    });

    _showSnack("Cleared 🧹");
  }

  void openQRScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          onScanned: (value) {
            setState(() {
              encryptedController.text = value;
              qrData = value;
            });
            _showSnack("QR scanned successfully ✅");
          },
        ),
      ),
    );
  }

  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryScreen(
          history: history,
          onCopy: (value) async {
            await Clipboard.setData(ClipboardData(text: value));
            _showSnack("Copied to clipboard 📋");
          },
          onDelete: deleteHistoryItem,
          onClearAll: clearHistory,
        ),
      ),
    );
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
      appBar: _buildAppBar(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.lock), label: "Encrypt"),
          NavigationDestination(icon: Icon(Icons.lock_open), label: "Decrypt"),
        ],
      ),
      body: currentIndex == 0 ? _encryptUI() : _decryptUI(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text("Secure Encryptor 🛡️"),
      centerTitle: true,
      actions: [
        IconButton(onPressed: openHistory, icon: const Icon(Icons.history)),
        IconButton(
          onPressed: exportHistoryFile,
          icon: const Icon(Icons.download),
        ),
        IconButton(onPressed: openSettings, icon: const Icon(Icons.settings)),
        IconButton(onPressed: clearAll, icon: const Icon(Icons.delete_forever)),
      ],
    );
  }

  Widget _encryptUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _headerCard(
            title: "Encrypt Message",
            subtitle: "Type message + secret key and generate ciphertext.",
            icon: Icons.lock,
          ),
          const SizedBox(height: 14),
          _inputCard(
            label: "Plain Text",
            controller: plainController,
            hint: "Enter your message...",
            maxLines: 4,
          ),
          const SizedBox(height: 14),
          _inputCard(
            label: "Secret Key",
            controller: secretController,
            hint: "Example: sunny@123",
            maxLines: 1,
            obscure: true,
          ),
          const SizedBox(height: 14),
          _primaryButton(
            icon: Icons.lock,
            title: "Encrypt Now",
            onTap: encryptText,
          ),
          const SizedBox(height: 14),
          _encryptedOutputCard(),
          const SizedBox(height: 16),
          if (qrData.isNotEmpty) _qrCard(),
        ],
      ),
    );
  }

  Widget _decryptUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _headerCard(
            title: "Decrypt Message",
            subtitle: "Paste ciphertext + key and reveal message.",
            icon: Icons.lock_open,
          ),
          const SizedBox(height: 14),
          _inputCard(
            label: "Encrypted Text",
            controller: encryptedController,
            hint: "Paste encrypted message here...",
            maxLines: 5,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _secondaryButton(
                  icon: Icons.paste,
                  title: "Paste",
                  onTap: pasteEncrypted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _secondaryButton(
                  icon: Icons.qr_code_scanner,
                  title: "Scan QR",
                  onTap: openQRScanner,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _inputCard(
            label: "Secret Key",
            controller: secretController,
            hint: "Enter same secret key...",
            maxLines: 1,
            obscure: true,
          ),
          const SizedBox(height: 14),
          _primaryButton(
            icon: Icons.lock_open,
            title: "Decrypt Now",
            onTap: decryptText,
          ),
          const SizedBox(height: 14),
          _decryptedOutputCard(),
        ],
      ),
    );
  }

  Widget _headerCard({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF1F2A37), Color(0xFF0B0F14)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.green.withValues(alpha: 0.15),
            child: Icon(icon, color: Colors.greenAccent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputCard({
    required String label,
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    bool obscure = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: maxLines,
            obscureText: obscure,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: const Color(0xFF0B1220),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(title),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(title),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _encryptedOutputCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Encrypted Output",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: encryptedController,
            maxLines: 5,
            readOnly: true,
            decoration: InputDecoration(
              hintText: "Encrypted text will appear here...",
              filled: true,
              fillColor: const Color(0xFF0B1220),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _secondaryButton(
                  icon: Icons.copy,
                  title: "Copy",
                  onTap: copyEncrypted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _secondaryButton(
                  icon: Icons.share,
                  title: "Share",
                  onTap: shareEncrypted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _decryptedOutputCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Decrypted Output",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              plainController.text.isEmpty
                  ? "Decrypted message will appear here..."
                  : plainController.text,
              style: TextStyle(
                color: plainController.text.isEmpty
                    ? Colors.white54
                    : Colors.white,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qrCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "QR Code (Fast Share)",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(data: qrData, size: 200),
            ),
          ),
        ],
      ),
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  final Function(String value) onScanned;

  const QRScannerScreen({super.key, required this.onScanned});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan QR Code"), centerTitle: true),
      body: MobileScanner(
        onDetect: (capture) {
          if (scanned) return;

          final barcode = capture.barcodes.first;
          final value = barcode.rawValue;

          if (value != null && value.isNotEmpty) {
            scanned = true;
            widget.onScanned(value);
            Navigator.pop(context);
          }
        },
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  final List<HistoryItem> history;
  final Function(String value) onCopy;
  final Function(int index) onDelete;
  final VoidCallback onClearAll;

  const HistoryScreen({
    super.key,
    required this.history,
    required this.onCopy,
    required this.onDelete,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("History"),
        actions: [
          IconButton(
            onPressed: onClearAll,
            icon: const Icon(Icons.delete_forever),
          ),
        ],
      ),
      body: history.isEmpty
          ? const Center(child: Text("No history yet"))
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                final item = history[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: ListTile(
                    title: Text(
                      item.type == "encrypt" ? "🔒 Encrypted" : "🔓 Decrypted",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      item.encryptedText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () => onCopy(item.encryptedText),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => onDelete(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool biometricEnabled = false;
  bool pinEnabled = false;
  final TextEditingController pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      biometricEnabled = prefs.getBool("biometric_enabled") ?? false;
      pinEnabled = prefs.getBool("pin_enabled") ?? false;
      pinController.text = prefs.getString("pin_code") ?? "";
    });
  }

  Future<void> toggleBiometric(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("biometric_enabled", value);

    setState(() {
      biometricEnabled = value;
    });
  }

  Future<void> togglePin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("pin_enabled", value);

    setState(() {
      pinEnabled = value;
    });
  }

  Future<void> savePin() async {
    final pin = pinController.text.trim();

    if (pin.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter a PIN")));
      return;
    }

    if (pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PIN must be at least 4 digits")),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("pin_code", pin);

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("PIN saved successfully ✅")));
  }

  @override
  void dispose() {
    pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text("Enable Biometric Lock"),
              subtitle: const Text(
                "Require fingerprint/face unlock at startup",
              ),
              value: biometricEnabled,
              onChanged: toggleBiometric,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: SwitchListTile(
              title: const Text("Enable PIN Lock"),
              subtitle: const Text(
                "Require PIN at startup (fallback if biometric fails)",
              ),
              value: pinEnabled,
              onChanged: togglePin,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Set PIN Code",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
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
                    child: ElevatedButton.icon(
                      onPressed: savePin,
                      icon: const Icon(Icons.save),
                      label: const Text("Save PIN"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
