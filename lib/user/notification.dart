import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ask_psu/user/firestore_client_wrapper.dart';

const primarycolor = Color(0xFFE6B24A);
const primarycolordark = Color(0xFF7A4F22);
const secondarycolor = Color(0xFFF7D9B9);
const textdark = Color(0xFF312B20);
const textlight = Color(0xFF948D7C);
const lightBackground = Color(0xFFFFFAF3);

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  List<DocumentSnapshot> notifications = [];
  List<DocumentSnapshot> unreadNotifications = [];
  List<DocumentSnapshot> readNotifications = [];
  bool isLoading = true;
  bool selectionMode = false;
  Set<String> selectedIds = {};

  @override
  void initState() {
    super.initState();
    _patchUserMissingTimestamps().then((_) => _loadNotifications());
  }

  Future<void> _patchUserMissingTimestamps() async {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    if (email == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Notifications')
          .where('email', isEqualTo: email)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (!(data.containsKey('timestamp')) || data['timestamp'] == null) {
          await doc.reference.update({'timestamp': Timestamp.now()});
        }
      }
    } catch (e, stack) {
      print("Error patching missing timestamps: $e\n$stack");
    }
  }

  Future<void> _loadNotifications() async {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    if (email == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      final unreadSnap = await FirestoreClientWrapper.safeGet(
        FirestoreClientWrapper.safeCollection('Notifications')
            .where('email', isEqualTo: email)
            .where('status', isEqualTo: 'unread')
            .where('timestamp',
                isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(0))
            .orderBy('timestamp', descending: true),
        timeout: const Duration(seconds: 15),
      );

      final readSnap = await FirestoreClientWrapper.safeGet(
        FirestoreClientWrapper.safeCollection('Notifications')
            .where('email', isEqualTo: email)
            .where('status', isEqualTo: 'read')
            .where('timestamp',
                isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(0))
            .orderBy('timestamp', descending: true),
        timeout: const Duration(seconds: 15),
      );

      setState(() {
        unreadNotifications = unreadSnap.docs;
        readNotifications = readSnap.docs;
        notifications = [...unreadNotifications, ...readNotifications];
        isLoading = false;
      });
    } catch (e, stack) {
      print("Firestore query error: $e\n$stack");
      setState(() {
        unreadNotifications = [];
        readNotifications = [];
        notifications = [];
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading notifications: $e')),
      );
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
  }

  void _deleteSelected() async {
    final List<Map<String, dynamic>> backupList = [];
    final List<String> idsToDelete = selectedIds.toList();

    for (var id in idsToDelete) {
      final docRef =
          FirestoreClientWrapper.safeCollection('Notifications').doc(id);
      final doc = await docRef.get();
      if (doc.exists) {
        backupList.add({'id': id, 'data': doc.data()});
        await docRef.delete();
      }
    }

    setState(() {
      selectionMode = false;
      selectedIds.clear();
    });

    // ✅ Refresh notifications after deletion
    await _loadNotifications();

    final count = idsToDelete.length;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$count notification${count > 1 ? 's' : ''} deleted',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () async {
            for (var item in backupList) {
              await FirebaseFirestore.instance
                  .collection('Notifications')
                  .doc(item['id'])
                  .set(item['data'] as Map<String, dynamic>);
            }
            // ✅ Refresh again after undo
            await _loadNotifications();
          },
        ),
      ),
    );
  }

  void _selectAll() {
    setState(() {
      selectedIds = notifications.map((e) => e.id).toSet();
    });
  }

  void _cancelSelection() {
    setState(() {
      selectionMode = false;
      selectedIds.clear();
    });
  }

  void _deleteSingleNotification(DocumentSnapshot doc, int index) async {
    final deletedDoc = doc;
    final backupData = doc.data() as Map<String, dynamic>;

    // Delete from Firestore
    await FirebaseFirestore.instance
        .collection('Notifications')
        .doc(doc.id)
        .delete();

    // Reload updated notifications list
    await _loadNotifications();

    // Show snackbar with Undo option
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Notification deleted',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () async {
            // Restore the deleted notification
            await FirebaseFirestore.instance
                .collection('Notifications')
                .doc(deletedDoc.id)
                .set(backupData);

            // 🔁 Reload notifications after Undo
            await _loadNotifications();
          },
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${time.month}/${time.day}/${time.year}';
  }

  Widget _buildNotificationItem(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Notification';
    final message = data['message'] ?? '';
    final timestamp = data['timestamp'] as Timestamp?;
    final isSelected = selectedIds.contains(doc.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPress: () {
          setState(() {
            selectionMode = true;
            _toggleSelection(doc.id);
          });
        },
        onTap: () {
          if (selectionMode) {
            _toggleSelection(doc.id);
          }
        },
        child: Dismissible(
          key: Key(doc.id),
          direction: selectionMode
              ? DismissDirection.none
              : DismissDirection.endToStart,
          onDismissed: (_) => _deleteSingleNotification(doc, 0),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  isSelected ? secondarycolor.withOpacity(0.6) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                if (selectionMode)
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(doc.id),
                    activeColor: primarycolordark,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: primarycolordark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: GoogleFonts.poppins(
                          color: textlight,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (timestamp != null)
                        Text(
                          _formatTimestamp(timestamp.toDate()),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: lightBackground,
        surfaceTintColor: lightBackground,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        centerTitle: true,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: primarycolordark),
          onPressed:
              selectionMode ? _cancelSelection : () => Navigator.pop(context),
        ),
        title: selectionMode
            ? Row(
                children: [
                  if (selectedIds.isNotEmpty)
                    Text(
                      '${selectedIds.length}',
                      style: const TextStyle(
                          color: primarycolordark, fontSize: 18),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: primarycolordark),
                    onPressed: _deleteSelected,
                  ),
                  Checkbox(
                    value: selectedIds.length == notifications.length &&
                        notifications.isNotEmpty,
                    onChanged: (value) {
                      value == true
                          ? _selectAll()
                          : setState(() => selectedIds.clear());
                    },
                    activeColor: primarycolordark,
                    checkColor: Colors.white,
                    side: const BorderSide(color: primarycolordark, width: 2),
                  ),
                  const Text(
                    "Select all",
                    style: TextStyle(
                        color: primarycolordark,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              )
            : Text(
                'Notifications',
                style: GoogleFonts.poppins(
                    color: primarycolordark, fontWeight: FontWeight.bold),
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: notifications.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/notification_empty.png',
                            width: constraints.maxWidth < 400
                                ? 150
                                : 220, // responsive size
                            height: constraints.maxWidth < 400 ? 150 : 220,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'No notifications to show',
                            style: GoogleFonts.poppins(
                              color: textlight,
                              fontSize: constraints.maxWidth < 400
                                  ? 14
                                  : 16, // responsive text
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              if (unreadNotifications.isNotEmpty) ...[
                                _buildSectionHeader(
                                    "Unread (${unreadNotifications.length})",
                                    primarycolor,
                                    primarycolordark),
                                const SizedBox(height: 10),
                                ...unreadNotifications
                                    .map(_buildNotificationItem),
                                const SizedBox(height: 20),
                              ],
                              if (readNotifications.isNotEmpty) ...[
                                _buildSectionHeader(
                                    "Read (${readNotifications.length})",
                                    Colors.grey.withOpacity(0.15),
                                    textlight),
                                const SizedBox(height: 10),
                                ...readNotifications
                                    .map(_buildNotificationItem),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color bgColor, Color textColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withOpacity(0.4)),
      ),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
