import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scanner Aggregator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return const ScannerHomePage();
        }
        return const SignInPage();
      },
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 16),
              Text('Sign In', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _signIn,
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: const Text('Sign In'),
                    ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const SignUpPage()));
                },
                child: const Text('Don\'t have an account? Sign Up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<void> _signUp() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) Navigator.pop(context); // Go back to sign in
    } on FirebaseAuthException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_add, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 16),
              Text('Sign Up', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _signUp,
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: const Text('Sign Up'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

enum ScannerType { document, qr, barcode }

class _ScannerHomePageState extends State<ScannerHomePage> {
  ScannerType? _selectedType;
  String? _scanResult;
  File? _capturedImage;
  bool _isLoading = false;

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.storage.request();
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isLoading = true);
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      final imageFile = File(pickedFile.path);
      setState(() {
        _capturedImage = imageFile;
        _scanResult = null;
      });
      if (_selectedType == ScannerType.document) {
        await _scanDocument(imageFile);
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _scanDocument(File image) async {
    final inputImage = InputImage.fromFile(image);
    final textRecognizer = TextRecognizer();
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
    setState(() {
      _scanResult = recognizedText.text.isNotEmpty ? recognizedText.text : 'No text found.';
    });
    textRecognizer.close();
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Scan QR Code')),
          body: MobileScanner(
            onDetect: (capture) {
              final barcode = capture.barcodes.first;
              Navigator.of(context).pop(barcode.rawValue ?? 'No QR code found.');
            },
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (result != null && result is String && result.isNotEmpty && result != 'No QR code found.') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('QR Code Result'),
          content: Text(result),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    setState(() {
      _scanResult = (result is String && result.isNotEmpty) ? result : 'No QR code found.';
      _capturedImage = null;
    });
  }

  Future<void> _scanBarcode() async {
    var result = await BarcodeScanner.scan();
    setState(() {
      _scanResult = result.rawContent.isNotEmpty ? result.rawContent : 'No barcode found.';
      _capturedImage = null;
    });
  }

  Widget _buildScanResult() {
    if (_scanResult == null) return const SizedBox.shrink();
    final urlRegExp = RegExp(r'https?://[^\s]+');
    final matches = urlRegExp.allMatches(_scanResult!);
    if (matches.isNotEmpty) {
      final urls = matches.map((m) => m.group(0)).whereType<String>().toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Scan Result:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ...urls.map((url) => InkWell(
                onTap: () => launchUrl(Uri.parse(url)),
                child: Text(url, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
              )),
          if (_scanResult!.replaceAll(urls.join(), '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(_scanResult!.replaceAll(urls.join(), '')),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Scan Result:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text(_scanResult!),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner Aggregator App'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToggleButtons(
                isSelected: [
                  _selectedType == ScannerType.document,
                  _selectedType == ScannerType.qr,
                  _selectedType == ScannerType.barcode,
                ],
                onPressed: (index) {
                  setState(() {
                    _selectedType = ScannerType.values[index];
                    _scanResult = null;
                    _capturedImage = null;
                  });
                },
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Document')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('QR Code')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Barcode')),
                ],
              ),
              const SizedBox(height: 16),
              if (_selectedType == ScannerType.document) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Capture Document'),
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Pick from Gallery'),
                  onPressed: () => _pickImage(ImageSource.gallery),
                ),
              ] else if (_selectedType == ScannerType.qr) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR Code'),
                  onPressed: _scanQRCode,
                ),
              ] else if (_selectedType == ScannerType.barcode) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Scan Barcode'),
                  onPressed: _scanBarcode,
                ),
              ],
              const SizedBox(height: 16),
              if (_isLoading) const Center(child: CircularProgressIndicator()),
              if (_capturedImage != null) ...[
                const Text('Captured Image:', style: TextStyle(fontWeight: FontWeight.bold)),
                if (kIsWeb)
                  FutureBuilder<Uint8List>(
                    future: _capturedImage!.readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                        return Image.memory(snapshot.data!, height: 200, fit: BoxFit.contain);
                      } else {
                        return const CircularProgressIndicator();
                      }
                    },
                  )
                else
                  Image.file(_capturedImage!, height: 200, fit: BoxFit.contain),
                const SizedBox(height: 8),
              ],
              if (_scanResult != null) _buildScanResult(),
            ],
          ),
        ),
      ),
    );
  }
}
