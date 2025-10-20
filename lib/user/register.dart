import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';
import 'package:ask_psu/user/login.dart';

const Color primarycolor = Color(0xFFd5891b);
const Color primarycolordark = Color(0xFF753a0e);
const Color textdark = Color(0xFF333333);
const Color textlight = Color(0xFF767268);
const Color lightBackground = Color(0xFFF9F6F1);

String capitalizeEachWord(String input) {
  return input
      .split(' ')
      .map(
        (word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '',
      )
      .join(' ');
}

class RegisterPage extends StatefulWidget {
  final String? prefilledEmail;
  final bool isGoogleSignIn;
  const RegisterPage(
      {super.key, this.prefilledEmail, this.isGoogleSignIn = false});

  @override
  State<RegisterPage> createState() => _RegisterPageScreen();
}

String _studentType = 'Prospective';

class _RegisterPageScreen extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;

  late AnimationController _fadeInController;
  late Animation<double> _fadeIn;

  final fullNameController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  late final emailController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _registrationCompleted = false;
  bool _emailSent = false;
  bool _isVerified = false;

  User? currentUser;

  @override
  void initState() {
    super.initState();
    emailController.text = widget.prefilledEmail ?? '';
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _fadeInController, curve: Curves.easeIn);
    _fadeInController.forward();
  }

  @override
  void dispose() {
    _fadeInController.dispose();
    fullNameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    if (!_registrationCompleted) {
      _signOutAndDeleteUser();
    }
    super.dispose();
  }

  Future<void> _signOutAndDeleteUser() async {
    final user = _auth.currentUser;
    final googleSignIn = GoogleSignIn();
    try {
      // Only delete user if they haven't completed registration
      if (user != null && !_registrationCompleted) {
        await user.delete();
      }
      await _auth.signOut();
      await googleSignIn.signOut();
    } catch (e) {
      // If deletion fails, just sign out
      try {
        await _auth.signOut();
        await googleSignIn.signOut();
      } catch (_) {}
    }
  }

  Future<void> _checkForIncompleteRecords(String email) async {
    try {
      // Check if there are any incomplete user records in Firestore
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      print('🔍 DEBUG: Found ${query.docs.length} records for email: $email');

      for (var doc in query.docs) {
        final data = doc.data();
        print('📄 DEBUG: Record ID: ${doc.id}, Data: $data');

        // Check if this is an incomplete registration (no verified email)
        if (data['emailVerified'] != true) {
          print('⚠️ DEBUG: Found incomplete record, attempting to clean up...');
          await doc.reference.delete();
          print('✅ DEBUG: Incomplete record deleted');
        }
      }
    } catch (e) {
      print('❌ DEBUG: Error checking incomplete records: $e');
    }
  }

  void _showSnack(String msg, {Color color = primarycolordark}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showEmailAlreadyUsedDialog(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: lightBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Email Already Registered',
          style: TextStyle(
            color: primarycolor,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        content: Text(
          'The email "$email" is already registered. Would you like to try logging in instead?',
          style: const TextStyle(
            color: textdark,
            fontFamily: 'Poppins',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _isLoading = false);
            },
            child: const Text(
              'Try Different Email',
              style: TextStyle(color: textlight, fontFamily: 'Poppins'),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const UserLogin()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primarycolor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Go to Login',
              style: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _register() async {
    final name = capitalizeEachWord(fullNameController.text.trim());
    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (name.isEmpty || username.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnack("Please fill in all fields.");
      return;
    }

    if (password != confirmPassword) {
      _showSnack("Passwords do not match.", color: Colors.red);
      return;
    }

    // Check if username is already taken
    final usernameQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .get();

    if (usernameQuery.docs.isNotEmpty) {
      _showSnack("Username already taken. Please choose a different username.",
          color: Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.isGoogleSignIn) {
        // For Google sign-in users, link the password to their existing Google account
        currentUser = _auth.currentUser;
        if (currentUser == null) {
          _showSnack("Google sign-in user not found. Please try again.",
              color: Colors.red);
          setState(() => _isLoading = false);
          return;
        }

        // Link email/password credential to the existing Google account
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );

        await currentUser!.linkWithCredential(credential);
        print('✅ DEBUG: Password linked to Google account for: $email');

        // For Google sign-in users, since Google accounts are already verified,
        // we can directly save the user data and mark as verified
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .set({
          'uid': currentUser!.uid,
          'name': capitalizeEachWord(fullNameController.text.trim()),
          'username': usernameController.text.trim(),
          'email': currentUser!.email,
          'studentType': _studentType,
          'createdAt': FieldValue.serverTimestamp(),
          'emailVerified': true, // Google accounts are already verified
          'isGoogleUser': true,
        });

        setState(() {
          _registrationCompleted = true;
          _isVerified = true;
          _isLoading = false;
        });

        _showSnack("Registration completed successfully!", color: Colors.green);

        Future.delayed(const Duration(seconds: 2), () {
          Navigator.pop(
              context, true); // Return true to indicate successful registration
        });
      } else {
        // Regular email/password registration
        print('🔍 DEBUG: Attempting to register email: $email');

        final credential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        print('✅ DEBUG: Account created successfully for: $email');
        currentUser = credential.user;
        await currentUser!.sendEmailVerification();

        setState(() {
          _emailSent = true;
        });

        _showSnack("Verification email sent. Please check your inbox.");

        _checkVerificationStatus();
      }
    } on FirebaseAuthException catch (e) {
      // Debug: Log the exact error details
      print(
          '❌ DEBUG: Firebase Auth Error - Code: ${e.code}, Message: ${e.message}');

      String message = 'Registration failed. Please try again.';

      switch (e.code) {
        case 'email-already-in-use':
          message =
              'This email is already registered. Would you like to try logging in instead?';
          print(
              '🔍 DEBUG: Email already in use - checking for incomplete records...');
          await _checkForIncompleteRecords(email);
          _showEmailAlreadyUsedDialog(email);
          return; // Don't show the snack bar, show dialog instead
        case 'weak-password':
          message = 'Password is too weak. Please choose a stronger password.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'operation-not-allowed':
          message =
              'Email registration is not enabled. Please contact support.';
          break;
        case 'credential-already-in-use':
          message = 'This email is already linked to another account.';
          break;
        default:
          message = e.message ?? 'Registration failed. Please try again.';
      }

      _showSnack(message, color: Colors.red);
      setState(() => _isLoading = false);
    } catch (e) {
      _showSnack("Unexpected error: ${e.toString()}", color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkVerificationStatus() async {
    int elapsed = 0;
    while (elapsed < 180 && !_isVerified) {
      await Future.delayed(const Duration(seconds: 3));
      await currentUser?.reload();
      final refreshedUser = _auth.currentUser;

      if (refreshedUser != null && refreshedUser.emailVerified) {
        setState(() {
          _isVerified = true;
          _isLoading = false;
        });
        await _saveUserData();
        break;
      }
      elapsed += 3;
    }

    if (!_isVerified) {
      _showSnack("Verification timeout. Try again.", color: Colors.red);
      await _signOutAndDeleteUser();
      setState(() {
        _isLoading = false;
        _emailSent = false;
      });
    }
  }

  Future<void> _saveUserData() async {
    if (currentUser == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid)
        .set({
      'uid': currentUser!.uid,
      'name': capitalizeEachWord(fullNameController.text.trim()),
      'username': usernameController.text.trim(),
      'email': currentUser!.email,
      'studentType': _studentType,
      'createdAt': FieldValue.serverTimestamp(),
      'emailVerified': currentUser!.emailVerified,
    });

    _registrationCompleted = true;
    _showSnack("Email verified! Registration complete.", color: Colors.green);

    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(
          context, true); // Return true to indicate successful registration
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      body: FadeTransition(
        opacity: _fadeIn,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                children: [
                  const SizedBox(height: 50),
                  Text(
                    'Create Account',
                    style: TextStyle(
                      color: primarycolor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildField(fullNameController, 'Full Name'),
                  const SizedBox(height: 12),
                  _buildField(usernameController, 'Username'),
                  const SizedBox(height: 12),
                  _buildField(emailController, 'Email'),
                  const SizedBox(height: 12),
                  _buildPassword(passwordController, 'Password', true),
                  const SizedBox(height: 12),
                  _buildPassword(
                    confirmPasswordController,
                    'Confirm Password',
                    false,
                  ),
                  const SizedBox(height: 16),
                  _buildStudentTypeSelector(),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : _emailSent
                              ? _isVerified
                                  ? null
                                  : () => _checkVerificationStatus()
                              : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isVerified ? Colors.green : primarycolor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              widget.isGoogleSignIn
                                  ? (_isVerified
                                      ? "Registration Complete!"
                                      : "Complete Registration")
                                  : _isVerified
                                      ? "Verified! Continue"
                                      : _emailSent
                                          ? "Waiting for Verification..."
                                          : "Register",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: () async {
                      if (!_registrationCompleted) {
                        await _signOutAndDeleteUser();
                      }
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const UserLogin()),
                      );
                    },
                    child: const Text(
                      'Already have an account? Login here',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: lightBackground,
        labelStyle: const TextStyle(fontFamily: 'Poppins'),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primarycolor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildPassword(
    TextEditingController controller,
    String label,
    bool isMain,
  ) {
    final isObscure = isMain ? _obscurePassword : _obscureConfirmPassword;

    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(
            isObscure ? Icons.visibility_off : Icons.visibility,
            color: textlight,
          ),
          onPressed: () {
            setState(() {
              if (isMain) {
                _obscurePassword = !_obscurePassword;
              } else {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              }
            });
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primarycolor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildStudentTypeSelector() {
    return Column(
      children: [
        const Text(
          'Student Type',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textdark,
            fontFamily: 'Poppins',
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Radio<String>(
              value: 'Prospective',
              groupValue: _studentType,
              onChanged: (value) => setState(() => _studentType = value!),
              activeColor: primarycolordark,
            ),
            const Text('Prospective'),
            Radio<String>(
              value: 'Enrolled',
              groupValue: _studentType,
              onChanged: (value) => setState(() => _studentType = value!),
              activeColor: primarycolordark,
            ),
            const Text('Enrolled'),
          ],
        ),
      ],
    );
  }
}
