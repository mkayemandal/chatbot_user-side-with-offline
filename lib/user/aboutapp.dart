import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ask_psu/user/profile.dart';

const primarycolor = Color(0xFFd5891b);
const primarycolordark = Color(0xFF753a0e);
const lightBackground = Color(0xFFF9F6F1);
const textdark = Color(0xFF333333);
const textlight = Color(0xFF767268);

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});

  final List<Map<String, String>> developers = const [
    {
      'image': 'assets/images/mariel.png',
      'name': 'Mariel Kaye Mandal',
      'role': 'Backend Developer'
    },
    {
      'image': 'assets/images/kisses.png',
      'name': 'Jance Kisses Lopez',
      'role': 'Frontend Developer'
    },
    {
      'image': 'assets/images/aira.png',
      'name': 'Jane Aira Villalon',
      'role': 'UI/UX Designer'
    },
    {
      'image': 'assets/images/noemi.png',
      'name': 'Noemi Cabugwas',
      'role': 'Firebase Admin'
    },
    {
      'image': 'assets/images/jereme.png',
      'name': 'Jereme Andrew Closa',
      'role': 'QA Engineer'
    },
    {
      'image': 'assets/images/lloyd.png',
      'name': 'John Lloyd Yusi',
      'role': 'Project Manager'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;
    final scale = (screenWidth / 375).clamp(0.85, 1.3);

    return Scaffold(
      backgroundColor: lightBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: primarycolordark),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const Profilepage(),
                    transitionsBuilder: (_, animation, __, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                  ),
                );
              },
            ),
            title: Text(
              'About App',
              style: GoogleFonts.poppins(
                color: primarycolordark,
                fontWeight: FontWeight.bold,
                fontSize: 20 * scale,
              ),
            ),
            centerTitle: true,
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.06,
          vertical: screenHeight * 0.02,
        ),
        child: ListView(
          children: [
            Center(
              child: Icon(
                Icons.info_outline,
                size: 70 * scale,
                color: primarycolordark,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Chatbot App',
                style: GoogleFonts.poppins(
                  fontSize: 22 * scale,
                  fontWeight: FontWeight.bold,
                  color: textdark,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Version 1.0.0',
                style: GoogleFonts.poppins(
                  fontSize: 14 * scale,
                  color: textlight,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'About This App',
              style: GoogleFonts.poppins(
                fontSize: 17 * scale,
                fontWeight: FontWeight.w600,
                color: textdark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'This mobile application is designed to provide users with a seamless chatbot experience. Users can communicate, manage their profiles, and access helpful features with ease. The app also includes admin tools, user feedback, and settings management for enhanced control.',
              style: GoogleFonts.poppins(
                fontSize: 14 * scale,
                color: textlight,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Our Developers',
              style: GoogleFonts.poppins(
                fontSize: 17 * scale,
                fontWeight: FontWeight.w600,
                color: textdark,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: isTablet ? 3 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 8,
              childAspectRatio: isTablet ? 1.8 : 1.4,
              children: developers.map((dev) {
                return _buildDeveloper(
                  imagePath: dev['image']!,
                  name: dev['name']!,
                  role: dev['role']!,
                  scale: scale,
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              'Developed By',
              style: GoogleFonts.poppins(
                fontSize: 17 * scale,
                fontWeight: FontWeight.w600,
                color: textdark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your Team or Developer Name\n© 2025 All rights reserved.',
              style: GoogleFonts.poppins(
                fontSize: 14 * scale,
                color: textlight,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeveloper({
    required String imagePath,
    required String name,
    required String role,
    required double scale,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 28 * scale,
          backgroundImage: AssetImage(imagePath),
        ),
        SizedBox(height: 4 * scale),
        Text(
          name,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12.5 * scale,
            fontWeight: FontWeight.w500,
            color: textdark,
          ),
        ),
        SizedBox(height: 2 * scale),
        Text(
          role,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 11.5 * scale,
            fontWeight: FontWeight.w400,
            color: textlight,
          ),
        ),
      ],
    );
  }
}
