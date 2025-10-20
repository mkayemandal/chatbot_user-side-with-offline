import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'forgotpass.dart';
import 'package:ask_psu/user/login.dart';

const Color primarycolor = Color(0xFFd5891b);
const Color primarycolordark = Color(0xFF753a0e);
const Color textdark = Color(0xFF333333);
const Color textlight = Color(0xFF767268);
const Color lightBackground = Color(0xFFF9F6F1);

class CheckMailPage extends StatelessWidget {
  const CheckMailPage({super.key});

  Future<void> openEmailApp() async {
    // Try Gmail (Android)
    const gmailUrl = 'googlegmail://';
    if (await canLaunchUrl(Uri.parse(gmailUrl))) {
      await launchUrl(Uri.parse(gmailUrl));
      return;
    }

    // Try Outlook
    const outlookUrl = 'ms-outlook://';
    if (await canLaunchUrl(Uri.parse(outlookUrl))) {
      await launchUrl(Uri.parse(outlookUrl));
      return;
    }

    // Try Yahoo Mail
    const yahooUrl = 'ymail://';
    if (await canLaunchUrl(Uri.parse(yahooUrl))) {
      await launchUrl(Uri.parse(yahooUrl));
      return;
    }

    // iOS Mail
    const appleMailUrl = 'message://';
    if (await canLaunchUrl(Uri.parse(appleMailUrl))) {
      await launchUrl(Uri.parse(appleMailUrl));
      return;
    }

    // Fallback: open mailto (compose window)
    final mailtoUri = Uri(scheme: 'mailto', path: '');
    if (await canLaunchUrl(mailtoUri)) {
      await launchUrl(mailtoUri);
    } else {
      debugPrint("No email apps available");
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    final double titleFontSize = isTablet ? 28 : 24;
    final double subtitleFontSize = isTablet ? 16 : 14;
    final double buttonFontSize = isTablet ? 18 : 16;

    return Scaffold(
      backgroundColor: lightBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 140,
                        width: 140,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDEFD4),
                          borderRadius: BorderRadius.circular(70),
                        ),
                        child: const Icon(
                          Icons.mail_outline,
                          size: 72,
                          color: primarycolor,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Check your mail',
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: textdark,
                          fontFamily: 'Poppins',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'We’ve sent password recovery instructions to your email address.',
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          color: textlight,
                          fontFamily: 'Poppins',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 36),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primarycolor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: openEmailApp,
                        child: Text(
                          'Open email app',
                          style: TextStyle(
                            fontSize: buttonFontSize,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        },
                        child: Text(
                          "Skip, I'll confirm later",
                          style: TextStyle(
                            fontSize: subtitleFontSize,
                            fontWeight: FontWeight.w500,
                            color: textdark,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                bottom: 20.0,
                left: 28,
                right: 28,
                top: 10,
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    "Didn't receive the email? Check your spam filter, or ",
                    style: TextStyle(
                      fontSize: subtitleFontSize,
                      color: textlight,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ForgotPasswordScreen(),
                        ),
                      );
                    },
                    child: Text(
                      "try another email address",
                      style: TextStyle(
                        fontSize: subtitleFontSize,
                        color: primarycolordark,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
