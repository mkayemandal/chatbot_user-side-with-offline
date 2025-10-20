import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ask_psu/user/forgotpass.dart';
import 'package:ask_psu/user/register.dart';
import 'package:ask_psu/user/homepage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

const Color primarycolor = Color(0xFFd5891b);
const Color primarycolordark = Color(0xFF753a0e);
const Color secondarycolor = Color(0xFF542409);
const Color dark = Color(0xFF17110d);
const Color textdark = Color(0xFF333333);
const Color textlight = Color(0xFF767268);
const Color lightBackground = Color(0xFFF9F6F1);

class UserLogin extends StatelessWidget {
  final bool isOffline;

  const UserLogin({super.key, this.isOffline = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Poppins',
        scaffoldBackgroundColor: lightBackground,
        colorScheme: ColorScheme.light(
          primary: primarycolor,
          secondary: secondarycolor,
          background: lightBackground,
        ),
      ),
      home: LoginScreen(isOffline: isOffline),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final bool isOffline;

  const LoginScreen({super.key, this.isOffline = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FocusNode emailFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;

  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _slideIn = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  // ✅ LOGIN WITH EMAIL AND PASSWORD
  Future<void> _login() async {
    if (widget.isOffline) {
      _showPopup(
        'Offline Mode',
        'Login is not available in offline mode. Please connect to the internet to sign in.',
      );
      return;
    }

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showPopup('Missing Fields', 'Please enter both email and password.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final user = userCredential.user;

      if (user == null) throw FirebaseAuthException(code: 'user-null');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        _showPopup('Account Error', 'User record not found.');
        await FirebaseAuth.instance.signOut();
        return;
      }

      final isBlocked = userDoc.data()?['blocked'] == true;

      if (isBlocked) {
        await FirebaseAuth.instance.signOut();
        _showPopup(
          'Account Blocked',
          'Your account has been blocked. Please contact support.',
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const Homepage()),
      );
    } on FirebaseAuthException catch (e) {
      String message = e.message ?? 'Login failed. Please try again.';
      if (e.code == 'user-not-found') {
        emailController.clear();
        message = 'No user found with this email.';
      } else if (e.code == 'wrong-password') {
        passwordController.clear();
        message = 'Incorrect password.';
      }
      _showPopup('Login Failed', message);
    } catch (e) {
      _showPopup('Error', 'Something went wrong. Try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ✅ GOOGLE SIGN-IN WITH BLOCK CHECK
  Future<void> _signInWithGoogle() async {
    if (widget.isOffline) {
      _showPopup(
        'Offline Mode',
        'Google Sign-In is not available in offline mode. Please connect to the internet.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;

      UserCredential result;
      User? user;

      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        result = await auth.signInWithPopup(googleProvider);
        user = result.user;
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() => _isLoading = false);
          return;
        }

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        result = await auth.signInWithCredential(credential);
        user = result.user;
      }

      if (user == null || user.email == null) {
        setState(() => _isLoading = false);
        return;
      }

      final userDoc = await firestore.collection('users').doc(user.uid).get();

      // 🚫 Check if blocked even if Google login
      if (userDoc.exists && userDoc.data()?['blocked'] == true) {
        await _signOutUser(user);
        _showPopup(
          'Account Blocked',
          'Your Google account is blocked. Please contact support.',
        );
        setState(() => _isLoading = false);
        return;
      }

      // 🟢 Register new user if not found
      if (!userDoc.exists) {
        final registered = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RegisterPage(
              prefilledEmail: user?.email ?? '',
              isGoogleSignIn: true,
            ),
          ),
        );

        if (registered != true) {
          await _signOutUser(user);
          _showPopup(
            'Registration Incomplete',
            'Please complete the registration to proceed.',
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Homepage()),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Google Sign-In failed. Please try again.';

      switch (e.code) {
        case 'account-exists-with-different-credential':
          message =
              'An account already exists with this email using a different sign-in method.';
          break;
        case 'invalid-credential':
          message = 'The credential received is malformed or has expired.';
          break;
        case 'operation-not-allowed':
          message = 'Google Sign-In is not enabled. Please contact support.';
          break;
        case 'user-disabled':
          message = 'This user account has been disabled.';
          break;
        case 'user-not-found':
          message = 'No user found with this email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        case 'invalid-verification-code':
          message = 'The verification code is invalid.';
          break;
        case 'invalid-verification-id':
          message = 'The verification ID is invalid.';
          break;
        default:
          message = e.message ?? 'Google Sign-In failed. Please try again.';
      }

      _showPopup('Google Sign-In Error', message);
    } catch (e) {
      String errorMessage = 'Google Sign-In failed. Please try again.';

      if (e.toString().contains('ApiException: 10')) {
        errorMessage =
            'Google Sign-In configuration error. Please contact support or try again later.';
      } else if (e.toString().contains('network_error')) {
        errorMessage =
            'Network error. Please check your internet connection and try again.';
      } else if (e.toString().contains('sign_in_failed')) {
        errorMessage =
            'Sign-in failed. Please make sure Google Play Services is up to date.';
      }

      _showPopup('Google Sign-In Error', errorMessage);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOutUser(User? user) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (user != null) {
        await GoogleSignIn().signOut();
      }
    } catch (e) {
      _showPopup('Sign-out failed', 'There was an issue signing you out.');
    }
  }

  void _showPopup(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: lightBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            color: primarycolor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(message, style: const TextStyle(color: primarycolordark)),
        actions: [
          TextButton(
            child: const Text('OK', style: TextStyle(color: primarycolor)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = (screenWidth / 375).clamp(0.85, 1.25);

    return Scaffold(
      backgroundColor: lightBackground,
      body: FadeTransition(
        opacity: _fadeIn,
        child: SlideTransition(
          position: _slideIn,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: screenHeight * 0.9),
                  child: IntrinsicHeight(child: _buildLoginForm(scale)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: lightBackground,
      labelStyle: const TextStyle(fontFamily: 'Poppins'),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primarycolor, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primarycolor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primarycolordark, width: 2),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    FocusNode focusNode,
    String label,
  ) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      decoration: _inputDecoration(label),
      enabled: !widget.isOffline, // Disable fields in offline mode
    );
  }

  Widget _buildLoginForm(double scale) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Offline mode indicator
        if (widget.isOffline)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, size: 20, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'Offline Mode - Login Unavailable',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
          ),

        Text(
          widget.isOffline ? 'Offline Mode' : 'Login here',
          style: TextStyle(
            fontSize: 30 * scale,
            fontWeight: FontWeight.bold,
            color: primarycolor,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          widget.isOffline
              ? "You're currently offline.\nLogin features are unavailable."
              : "Welcome back, you've\nbeen missed!",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17 * scale,
            fontWeight: FontWeight.w600,
            color: secondarycolor,
          ),
        ),
        const SizedBox(height: 50),
        _buildTextField(emailController, emailFocus, 'Email'),
        const SizedBox(height: 20),
        TextFormField(
          controller: passwordController,
          focusNode: passwordFocus,
          obscureText: _obscurePassword,
          enabled: !widget.isOffline, // Disable field in offline mode
          decoration: _inputDecoration('Password').copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: passwordFocus.hasFocus ? primarycolordark : textlight,
              ),
              onPressed: widget.isOffline
                  ? null
                  : () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!widget.isOffline)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              ),
              child: Text(
                'Forgot your password?',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: primarycolor,
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton(
            onPressed: widget.isOffline ? null : (_isLoading ? null : _login),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.isOffline ? Colors.grey : primarycolor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.isOffline ? 'Login Unavailable' : 'Sign in',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'Poppins',
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        if (!widget.isOffline)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Don't have an account? ",
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: textdark,
                  fontFamily: 'Poppins',
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterPage()),
                ),
                child: Text(
                  'Register here',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primarycolordark,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 40),
        if (!widget.isOffline)
          Row(
            children: [
              const Expanded(child: Divider(color: textlight)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  'Or continue with',
                  style: TextStyle(
                    color: textlight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: textlight)),
            ],
          ),
        const SizedBox(height: 16),
        if (!widget.isOffline)
          SizedBox(
            width: 50,
            height: 50,
            child: GestureDetector(
              onTap: _isLoading ? null : _signInWithGoogle,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/google.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        if (widget.isOffline)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(top: 20),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.info_outline, size: 24, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text(
                  "To access your account and personalized features, please connect to the internet and restart the app.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
