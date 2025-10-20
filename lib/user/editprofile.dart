import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ask_psu/user/myaccount.dart';


const primarycolor = Color(0xFFd5891b);
const primarycolordark = Color(0xFF753a0e);
const secondarycolor = Color(0xFF542409);
const dark = Color(0xFF17110d);
const textdark = Color(0xFF333333);
const textlight = Color(0xFF767268);
const lightBackground = Color(0xFFF9F6F1);


String capitalizeEachWord(String text) {
  return text
      .toLowerCase()
      .split(' ')
      .map((word) =>
          word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
      .join(' ');
}


class EditProfile extends StatefulWidget {
  const EditProfile({super.key});


  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}


class _EditProfileScreenState extends State<EditProfile>
    with SingleTickerProviderStateMixin {
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController contactController = TextEditingController();


  String? phoneNumber;
  bool _isPhoneInvalid = false;
  bool _isSaving = false;
  bool _saveHovered = false;
  bool _savePressed = false;


  late AnimationController _controller;
  late Animation<double> _fadeAnimation;


  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _loadUserData();
    _controller.forward();
  }


  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;


    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();


    if (data != null) {
      fullNameController.text = capitalizeEachWord(data['name'] ?? '');
      contactController.text = data['phone']?.replaceAll('+63', '') ?? '';
      emailController.text = data['email'] ?? '';
      usernameController.text = data['username'] ?? '';
      phoneNumber = data['phone'] ?? '';
      setState(() {});
    }
  }


  Future<void> _saveUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;


    final validPattern = RegExp(r'^(?:\+639|09)\d{9}$');
    if (phoneNumber == null || !validPattern.hasMatch(phoneNumber!)) {
      setState(() => _isPhoneInvalid = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Enter a valid Philippine phone number (e.g. 09123456789 or +639123456789).",
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }


    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'name': fullNameController.text.trim(),
        'username': usernameController.text.trim(),
        'email': emailController.text.trim(),
        'phone': phoneNumber,
      });


      _showSuccessDialog('Profile Updated!',
          'Your profile has been successfully updated.');
    } catch (e) {
      _showSuccessDialog(
          'Update Failed', 'Something went wrong while updating your profile.');
    } finally {
      setState(() => _isSaving = false);
    }
  }


  void _showSuccessDialog(String title, String subtitle) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Success",
      barrierColor: Colors.black.withOpacity(0.3),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: anim1.value,
          child: Opacity(
            opacity: anim1.value,
            child: Center(
              child: Dialog(
                backgroundColor: const Color(0xFFFDFCFB),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle,
                          color: primarycolor, size: 60),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: textdark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: textlight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );


    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(builder: (_) => const MyAccountPage()),
      );
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: textdark),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Edit Profile',
          style: GoogleFonts.poppins(
            color: primarycolordark,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 10),


              // ✅ Profile Picture Only
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  const CircleAvatar(
                    radius: 45,
                    backgroundImage: AssetImage('assets/images/defaultDP.jpg'),
                  ),
                  Material(
                    shape: const CircleBorder(),
                    color: Colors.white,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Profile photo update coming soon!",
                              style: GoogleFonts.poppins(),
                            ),
                            backgroundColor: primarycolordark,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.camera_alt,
                          size: 18,
                          color: primarycolordark,
                        ),
                      ),
                    ),
                  ),
                ],
              ),


              // ✅ Removed name and email here
              const SizedBox(height: 20),
              Divider(color: Colors.grey.shade300, height: 1),
              const SizedBox(height: 20),


              _buildInputField('Full Name', fullNameController, Icons.person),
              const SizedBox(height: 12),
              _buildInputField('Username', usernameController, Icons.alternate_email),
              const SizedBox(height: 12),


              _buildInputField(
                'Email',
                emailController,
                Icons.email,
                readOnly: true,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Email cannot be edited.",
                        style: GoogleFonts.poppins(),
                      ),
                      backgroundColor: primarycolordark,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),


              const SizedBox(height: 12),


              IntlPhoneField(
                controller: contactController,
                initialCountryCode: 'PH',
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: dark,
                  fontWeight: FontWeight.w500,
                ),
                dropdownTextStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  color: dark,
                ),
                decoration: InputDecoration(
                  labelText: 'Contact Number',
                  hintText: '9123456789',
                  filled: true,
                  fillColor: Colors.white,
                  labelStyle: const TextStyle(
                    color: dark,
                    fontWeight: FontWeight.w500,
                  ),
                  floatingLabelStyle: const TextStyle(
                    color: primarycolordark,
                    fontWeight: FontWeight.bold,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: secondarycolor, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: primarycolordark, width: 1.6),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.redAccent, width: 1.5),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.redAccent, width: 1.6),
                  ),
                  errorText: _isPhoneInvalid
                      ? 'Invalid Philippine mobile number'
                      : null,
                  errorStyle: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'Poppins',
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onChanged: (phone) {
                  setState(() {
                    phoneNumber = phone.completeNumber;
                    _isPhoneInvalid = false;
                  });
                },
              ),


              const SizedBox(height: 28),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildInputField(String label, TextEditingController controller, IconData icon,
      {bool readOnly = false, VoidCallback? onTap}) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      style: GoogleFonts.poppins(color: textdark, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: primarycolor),
        labelStyle:
            GoogleFonts.poppins(color: textlight, fontWeight: FontWeight.w500),
        floatingLabelStyle: GoogleFonts.poppins(
            color: primarycolordark, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: readOnly ? Colors.grey.shade100 : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primarycolor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: primarycolordark, width: 1.6),
        ),
      ),
    );
  }


  Widget _buildSaveButton() {
    return Listener(
      onPointerDown: (_) => setState(() => _savePressed = true),
      onPointerUp: (_) => setState(() => _savePressed = false),
      child: MouseRegion(
        onEnter: (_) => setState(() => _saveHovered = true),
        onExit: (_) => setState(() {
          _saveHovered = false;
          _savePressed = false;
        }),
        child: AnimatedScale(
          scale: _savePressed
              ? 0.98
              : _saveHovered
                  ? 1.04
                  : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeIn,
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              color: _saveHovered
                  ? primarycolordark.withOpacity(0.94)
                  : primarycolor,
              borderRadius: BorderRadius.circular(13),
              boxShadow: _saveHovered
                  ? [
                      BoxShadow(
                        color: primarycolor.withOpacity(0.20),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [],
            ),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveUserData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                elevation: 0,
                padding: EdgeInsets.zero,
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(
                      color: textdark, strokeWidth: 2.2)
                  : Text(
                      'Save',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}