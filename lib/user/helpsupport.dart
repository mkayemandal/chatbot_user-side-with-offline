import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ask_psu/user/profile.dart';
import 'package:ask_psu/user/connection_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

const primarycolor = Color(0xFFd5891b);
const primarycolordark = Color(0xFF753a0e);
const secondarycolor = Color(0xFFf4e2c6);
const textdark = Color(0xFF333333);
const textlight = Color(0xFF767268);
const lightBackground = Color(0xFFF9F6F1);

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> faqTabs = ['All'];
  int selectedFaqTabIndex = 0;

  List<Map<String, String>> allFaqs = [];
  List<Map<String, String>> filteredFaqs = [];

  String searchQuery = '';
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';
  Map<String, dynamic>? cachedContactData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeData();
  }

  Future<void> _initializeData() async {
    // Try to load cached data first
    await _loadCachedData();

    // Then try to fetch fresh data
    await fetchFAQs();
    await _fetchContactData();
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load cached FAQs
      final cachedFaqs = prefs.getString('cached_faqs');
      if (cachedFaqs != null) {
        final List<dynamic> faqsData = json.decode(cachedFaqs);
        final Set<String> categories = {'All'};

        final loadedFaqs = faqsData.map<Map<String, String>>((faq) {
          categories.add(faq['category'] ?? 'General');
          return {
            'question': faq['question'] ?? '',
            'answer': faq['answer'] ?? '',
            'category': faq['category'] ?? 'General',
          };
        }).toList();

        setState(() {
          allFaqs = loadedFaqs;
          filteredFaqs = loadedFaqs;
          faqTabs = categories.toList();
          isLoading = false;
        });
      }

      // Load cached contact data
      final cachedContact = prefs.getString('cached_contact_data');
      if (cachedContact != null) {
        cachedContactData = json.decode(cachedContact);
      }
    } catch (e) {
      print('Error loading cached data: $e');
    }
  }

  Future<void> fetchFAQs() async {
    if (!ConnectionHandler.instance.isOnline) {
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'No internet connection. Showing cached data.';
      });
      return;
    }

    try {
      setState(() {
        isLoading = true;
        hasError = false;
      });

      final doc = await FirebaseFirestore.instance
          .collection('SystemSettings')
          .doc('global')
          .get()
          .timeout(const Duration(seconds: 10));

      if (doc.exists && doc.data()!.containsKey('faqs')) {
        final List<dynamic> faqsData = doc['faqs'];
        final Set<String> categories = {'All'};

        final loadedFaqs = faqsData.map<Map<String, String>>((faq) {
          categories.add(faq['category'] ?? 'General');
          return {
            'question': faq['question'] ?? '',
            'answer': faq['answer'] ?? '',
            'category': faq['category'] ?? 'General',
          };
        }).toList();

        // Cache the data
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_faqs', json.encode(faqsData));

        setState(() {
          allFaqs = loadedFaqs;
          filteredFaqs = loadedFaqs;
          faqTabs = categories.toList();
          isLoading = false;
          hasError = false;
        });
      } else {
        setState(() {
          isLoading = false;
          hasError = true;
          errorMessage = 'No FAQ data available.';
        });
      }
    } catch (e) {
      print('Error fetching FAQs: $e');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage =
            'Failed to load FAQs. Please check your connection and try again.';
      });
    }
  }

  Future<void> _fetchContactData() async {
    if (!ConnectionHandler.instance.isOnline) {
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('SystemSettings')
          .doc('global')
          .get()
          .timeout(const Duration(seconds: 10));

      if (doc.exists) {
        final data = doc.data()!;
        cachedContactData = {
          'supportWebsite': data['supportWebsite'],
          'supportFacebook': data['supportFacebook'],
          'supportEmail': data['supportEmail'],
          'supportPhone': data['supportPhone'],
        };

        // Cache the contact data
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'cached_contact_data', json.encode(cachedContactData));
      }
    } catch (e) {
      print('Error fetching contact data: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _goBackToProfile() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Profilepage()),
    );
  }

  Future<void> _retryFetch() async {
    setState(() {
      hasError = false;
      errorMessage = '';
    });
    await fetchFAQs();
    await _fetchContactData();
  }

  void _filterFaqs() {
    final selectedCategory = faqTabs[selectedFaqTabIndex];

    setState(() {
      filteredFaqs = allFaqs.where((faq) {
        final matchesCategory =
            selectedCategory == 'All' || faq['category'] == selectedCategory;
        final matchesSearch =
            faq['question']!.toLowerCase().contains(searchQuery.toLowerCase());
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Help Center',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: primarycolordark,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          color: primarycolordark,
          onPressed: _goBackToProfile,
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: primarycolordark,
          unselectedLabelColor: textlight,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          indicatorColor: primarycolordark,
          tabs: const [
            Tab(text: 'FAQ'),
            Tab(text: 'Contact Us'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFAQTab(),
          _buildContactUsTab(),
        ],
      ),
    );
  }

  Widget _buildFAQTab() {
    if (isLoading && allFaqs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primarycolordark),
            SizedBox(height: 16),
            Text(
              'Loading FAQs...',
              style: TextStyle(color: textlight),
            ),
          ],
        ),
      );
    }

    if (hasError && allFaqs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[300],
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to Load FAQs',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textdark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: textlight,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _retryFetch,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primarycolordark,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (hasError && allFaqs.isNotEmpty)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange[600], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Showing cached data. Pull to refresh.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.orange[800],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _retryFetch,
                  child: Text(
                    'Retry',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: primarycolordark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          alignment: Alignment.centerLeft,
          margin: const EdgeInsets.only(top: 12, bottom: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(faqTabs.length, (index) {
                final selected = selectedFaqTabIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedFaqTabIndex = index;
                      });
                      _filterFaqs();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? primarycolordark : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: primarycolordark),
                      ),
                      child: Text(
                        faqTabs[index],
                        style: GoogleFonts.poppins(
                          color: selected ? Colors.white : primarycolordark,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (value) {
              setState(() => searchQuery = value);
              _filterFaqs();
            },
            style: const TextStyle(color: textdark),
            cursorColor: primarycolordark,
            decoration: const InputDecoration(
              hintText: 'Search for help',
              hintStyle: TextStyle(color: textlight),
              prefixIcon: Icon(Icons.search, color: textlight),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _retryFetch,
            color: primarycolordark,
            child: filteredFaqs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.help_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'No FAQs found for "$searchQuery"'
                              : 'No FAQs available',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: textlight,
                          ),
                        ),
                        if (searchQuery.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              setState(() => searchQuery = '');
                              _filterFaqs();
                            },
                            child: Text(
                              'Clear search',
                              style: GoogleFonts.poppins(
                                color: primarycolordark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredFaqs.length,
                    itemBuilder: (context, index) {
                      final item = filteredFaqs[index];
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16), // ✅ added
                            childrenPadding: const EdgeInsets.fromLTRB(
                                16, 0, 16, 16), // consistent padding
                            title: Text(
                              item['question'] ?? '',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: textdark,
                              ),
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  item['answer'] ?? '',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: textlight,
                                    height: 1.4,
                                  ),
                                  textAlign: TextAlign.left,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactUsTab() {
    // Use cached data if available, otherwise fetch from Firestore
    if (cachedContactData != null) {
      return _buildContactContent(cachedContactData!);
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('SystemSettings')
          .doc('global')
          .get()
          .timeout(const Duration(seconds: 10)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: primarycolordark),
                SizedBox(height: 16),
                Text(
                  'Loading contact information...',
                  style: TextStyle(color: textlight),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to Load Contact Info',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: textdark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your connection and try again.',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: textlight,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _retryFetch,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primarycolordark,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        return _buildContactContent(data);
      },
    );
  }

  Widget _buildContactContent(Map<String, dynamic> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Need assistance?',
              style: GoogleFonts.poppins(
                  fontSize: 18, color: textdark, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(
            'If you have any issues, questions, or feedback, feel free to reach out to us. We\'re here to help!',
            style: GoogleFonts.poppins(fontSize: 14, color: textlight),
          ),
          const SizedBox(height: 24),
          _supportTile(
            icon: Icons.language,
            title: 'Website',
            subtitle: data['supportWebsite'] ?? 'Unavailable',
            onTap: data['supportWebsite'] != null &&
                    data['supportWebsite'].isNotEmpty
                ? () => launchUrl(Uri.parse(data['supportWebsite']),
                    mode: LaunchMode.externalApplication)
                : null,
          ),
          _supportTile(
            icon: Icons.facebook,
            title: 'Facebook',
            subtitle: data['supportFacebook'] ?? 'Unavailable',
            onTap: data['supportFacebook'] != null &&
                    data['supportFacebook'].isNotEmpty
                ? () => launchUrl(Uri.parse(data['supportFacebook']),
                    mode: LaunchMode.externalApplication)
                : null,
          ),
          _supportTile(
            icon: Icons.email_outlined,
            title: 'Email Support',
            subtitle: data['supportEmail'] ?? 'Unavailable',
            onTap: data['supportEmail'] != null &&
                    data['supportEmail'].isNotEmpty
                ? () => launchUrl(Uri.parse('mailto:${data['supportEmail']}'))
                : null,
          ),
          _supportTile(
            icon: Icons.phone_outlined,
            title: 'Phone Support',
            subtitle: data['supportPhone'] ?? 'Unavailable',
            onTap:
                data['supportPhone'] != null && data['supportPhone'].isNotEmpty
                    ? () => launchUrl(Uri.parse('tel:${data['supportPhone']}'))
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _supportTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null || subtitle == 'Unavailable';

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDisabled ? Colors.grey[100] : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: isDisabled ? Colors.grey[400] : primarycolordark),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: isDisabled ? Colors.grey[600] : textdark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: isDisabled ? Colors.grey[500] : textlight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ],
              ),
            ),
            if (isDisabled)
              Icon(
                Icons.block,
                color: Colors.grey[400],
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}
