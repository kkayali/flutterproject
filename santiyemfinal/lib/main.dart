import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'package:intl/date_symbol_data_local.dart';

// Şantiye Şefi paneli (mevcut)
import 'santiye_sefi/foreman_panel.dart';

// MÜTEAHHİT tarafı – import HATASI düzeltilmiş
import 'muteahhit/contractor_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initSupabase();
  await initializeDateFormatting('tr_TR', null);
  runApp(const SantiyemApp());
}

class SantiyemApp extends StatelessWidget {
  const SantiyemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Şantiyem Cepte',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const Root(),
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth.User?>(
      stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AuthPage();
        }
        return const RoleRedirect();
      },
    );
  }
}

class RoleRedirect extends StatelessWidget {
  const RoleRedirect({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const AuthPage();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(body: Center(child: Text('Kullanıcı kaydı bulunamadı.')));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final role = (data['role'] ?? '').toString();

        if (role == 'Müteahhit') {
          // Müteahhit ana sayfası
          return const ContractorHomePage();
        } else if (role == 'Şantiye Şefi') {
          // Şantiye şefi paneli
          return const ForemanPanel();
        } else {
          return const Scaffold(body: Center(child: Text('Desteklenmeyen kullanıcı tipi')));
        }
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final passwordRepeatController = TextEditingController();
  final nameController = TextEditingController();
  final companyController = TextEditingController();
  String selectedRole = 'Müteahhit';
  bool isRegister = false;
  bool isLoading = false;
  bool rememberMe = false;

  final auth = fb_auth.FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;

  Future<void> handleLogin() async {
    setState(() => isLoading = true);
    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final userDoc = await firestore.collection('users').doc(credential.user!.uid).get();
      final savedRole = userDoc.data()?['role'];

      if (savedRole != selectedRole) {
        await auth.signOut();
        showError('Rol yanlış! Lütfen doğru kullanıcı türünü seçin.');
        setState(() => isLoading = false);
        return;
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        showError('E-posta bulunamadı.');
      } else if (e.code == 'wrong-password') {
        showError('Şifre yanlış.');
      } else {
        showError(e.message ?? 'Giriş hatası');
      }
    }
    setState(() => isLoading = false);
  }

  Future<void> handleRegister() async {
    if (passwordController.text != passwordRepeatController.text) {
      showError('Şifreler eşleşmiyor!');
      return;
    }

    setState(() => isLoading = true);
    try {
      final userCredential = await auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final userDoc = <String, dynamic>{
        'email': emailController.text.trim(),
        'name': nameController.text.trim(),
        'role': selectedRole,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (selectedRole == 'Müteahhit') {
        userDoc['company'] = companyController.text.trim();
      }

      await firestore.collection('users').doc(userCredential.user!.uid).set(userDoc);

      await auth.signOut();

      emailController.clear();
      passwordController.clear();
      passwordRepeatController.clear();
      nameController.clear();
      companyController.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kayıt başarılı! Lütfen giriş yapın.')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const Root()),
            (route) => false,
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      showError(e.message ?? 'Kayıt hatası');
    }

    setState(() => isLoading = false);
  }

  Future<void> handleResetPassword() async {
    try {
      await auth.sendPasswordResetEmail(email: emailController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifre sıfırlama e-postası gönderildi')),
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      showError(e.message ?? 'Şifre sıfırlama hatası');
    }
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isRegister ? 'Kayıt Ol' : 'Giriş Yap',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (isRegister)
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'İsim Soyisim',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  if (isRegister)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextField(
                        controller: passwordRepeatController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Şifre Tekrarı',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    items: const ['Müteahhit', 'Şantiye Şefi']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedRole = val!),
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı Türü',
                      prefixIcon: Icon(Icons.work_outline),
                    ),
                  ),
                  if (isRegister && selectedRole == 'Müteahhit')
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextField(
                        controller: companyController,
                        decoration: const InputDecoration(
                          labelText: 'Firma Adı',
                          prefixIcon: Icon(Icons.business),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (!isRegister)
                    CheckboxListTile(
                      value: rememberMe,
                      onChanged: (val) => setState(() => rememberMe = val ?? false),
                      title: const Text("Beni Hatırla"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: isLoading
                        ? null
                        : isRegister
                        ? handleRegister
                        : handleLogin,
                    icon: isLoading
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : Icon(isRegister ? Icons.person_add : Icons.login),
                    label: Text(isRegister ? 'Kayıt Ol' : 'Giriş Yap'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isLoading ? null : handleResetPassword,
                    child: const Text('Şifremi Unuttum'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => isRegister = !isRegister),
                    child: Text(isRegister
                        ? 'Zaten hesabım var, giriş yap'
                        : 'Hesabım yok, kayıt ol'),
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
