import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/video_call_page.dart';
import 'package:flutter_app/resources/pages/voice_call_page.dart';
import 'package:flutter_app/resources/pages/profile_details_page.dart';
import 'package:nylo_framework/nylo_framework.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  createState() => _CallsTabState();
}

class _CallsTabState extends NyState<CallsTab> {
  bool _showHistory = false;
  String _currentActiveLetter = "A";

  Set<String> _selectedContacts = {};

  // Sample data
  final List<Contact> _contacts = [
    Contact(name: "Eleanor", image: "image1.png", isOnline: true),
    Contact(name: "Layla B", image: "image2.png", isOnline: false),
    Contact(name: "Gadia", image: "image3.png", isOnline: true),
    Contact(name: "Sandra", image: "image4.png", isOnline: false),
    Contact(name: "Sheilla", image: "image5.png", isOnline: true),
    Contact(name: "Ahmed", image: "image6.png", isOnline: false),
    Contact(name: "Rodriga", image: "image7.png", isOnline: true),
    Contact(name: "Fenta", image: "image8.png", isOnline: false),
  ];

  final List<CallHistory> _callHistory = [
    CallHistory(
      contact: Contact(name: "Eleanor", image: "image1.png"),
      time: "08:24PM",
      type: CallType.incoming,
      duration: "10 minutes 3 minutes",
    ),
    CallHistory(
      contact: Contact(name: "Layla B", image: "image2.png"),
      time: "11:23AM",
      type: CallType.outgoing,
      duration: "20 outgoing minutes",
      count: 2,
    ),
    CallHistory(
      contact: Contact(name: "Sheilla", image: "image5.png"),
      time: "09:23AM",
      type: CallType.incoming,
      duration: "10 incoming 6 minutes",
    ),
    CallHistory(
      contact: Contact(name: "Fast Cars and tracks", image: "image9.png"),
      time: "Yesterday",
      type: CallType.missed,
      duration: "Missed",
    ),
    CallHistory(
      contact: Contact(name: "Gadia", image: "image3.png"),
      time: "Yesterday",
      type: CallType.missed,
      duration: "Missed",
    ),
    CallHistory(
      contact: Contact(name: "Sandra", image: "image4.png"),
      time: "Yesterday",
      type: CallType.outgoing,
      duration: "3 outgoing minutes",
      count: 4,
    ),
  ];

  @override
  get init => () {};

  void _showNewCallBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildNewCallBottomSheet(),
    );
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F131B),
      appBar: PreferredSize(
        preferredSize:
            const Size.fromHeight(80), // Increased height for two rows
        child: AppBar(
          backgroundColor: Color(0xFF1C212C),
          elevation: 0,
          automaticallyImplyLeading: false,
          flexibleSpace: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 10,
                ),
                // Top row - Logo aligned left
                // Container(
                //   height: 13,
                //   padding: const EdgeInsets.symmetric(horizontal: 16),
                //   alignment: Alignment.centerLeft,
                //   child: Container(
                //     width: 49,
                //     height: 13,
                //     child: Image.asset(
                //       'stillurlogo.png',
                //       width: 24,
                //       height: 24,
                //     ).localAsset(),
                //   ),
                // ),

                // Bottom row - Calls title centered
                Container(
                  height: 50,
                  alignment: Alignment.center,
                  child: Text(
                    'Calls',
                    style: TextStyle(
                      color: Color(0xFFFFFFFFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _showHistory ? _buildCallHistory() : _buildMainCallsView(),
    );
  }

  Widget _buildMainCallsView() {
    return Column(
      children: [
        // Make private calls section
        Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox(
                height: 40,
              ),
              Image.asset(
                'make_call.png', // Your phone image asset
                width: 80,
                height: 64,
                color: Color(0xFF6C7B7F),
              ).localAsset(),
              const SizedBox(height: 60),
              const Text(
                'Make private calls',
                style: TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your recent voice and video calls will\nappear here',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF8E9297),
                    fontSize: 14,
                    fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _showNewCallBottomSheet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E333E),
                    foregroundColor: Color(0xFF2E333E),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add,
                        size: 14,
                        color: Color(0xFFAACFFF),
                      ),
                      SizedBox(width: 8),
                      Text('Start Call',
                          style: TextStyle(
                              fontSize: 14, color: Color(0xFFAACFFF))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Make your first call now section
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Make your first call now',
                      style: TextStyle(
                          color: Color(0xFFE8E7EA),
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    // TextButton(
                    //   onPressed: () {
                    //     setState(() {
                    //       _showHistory = true;
                    //     });
                    //   },
                    //   child: const Text(
                    //     'History',
                    //     style: TextStyle(color: Color(0xFF3498DB)),
                    //   ),
                    // ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    return _buildContactItem(contact);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactItem(Contact contact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: () {
                  // Navigate to profile details page
                  routeTo(ProfileDetailsPage.path, data: {
                    'userName': contact.name,
                    'userImage': contact.image,
                    'isOnline': contact.isOnline,
                    'description': '',
                  });
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.shade700,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      contact.image,
                      fit: BoxFit.cover,
                    ).localAsset(),
                  ),
                ),
              ),
              if (contact.isOnline)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2ECC71),
                      shape: BoxShape.circle,
                      border: Border.all(color: Color(0xFF0F131B), width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              contact.name,
              style: const TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              routeTo(VoiceCallPage.path);
            },
            icon: const Icon(
              Icons.call,
              color: Color(0xFFE8E7EA),
              size: 22,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              routeTo(VideoCallPage.path);
            },
            icon: const Icon(
              Icons.videocam,
              color: Color(0xFFE8E7EA),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(
            'Call History',
            style: TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _callHistory.length,
            itemBuilder: (context, index) {
              final call = _callHistory[index];
              return _buildCallHistoryItem(call);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCallHistoryItem(CallHistory call) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              // Navigate to profile details page
              routeTo(ProfileDetailsPage.path, data: {
                'userName': call.contact.name,
                'userImage': call.contact.image,
                'description': '',
              });
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade700,
              ),
              child: ClipOval(
                child: Image.asset(
                  call.contact.image,
                  fit: BoxFit.cover,
                ).localAsset(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      call.contact.name,
                      style: const TextStyle(
                        color: Color(0xFFE8E7EA),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (call.count != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${call.count})',
                        style: const TextStyle(
                          color: Color(0xFFE8E7EA),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      _getCallIcon(call.type),
                      size: 14,
                      color: _getCallColor(call.type),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      call.duration,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                call.time,
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              const Icon(
                Icons.info_outline,
                color: Colors.grey,
                size: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewCallBottomSheet() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1B1C1D),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 84,
            height: 4,
            decoration: BoxDecoration(
              color: Color(0xFFC4C6C8),
              borderRadius: BorderRadius.circular(2),
            ),
          ).onTap(() => Navigator.pop(context)),

          // Header
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 14,
                        fontWeight: FontWeight.w400),
                  ),
                ),
                const Text(
                  'New Call',
                  style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 18,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 60),
              ],
            ),
          ),

          // Search bar
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade600,
                  width: 1.0,
                ),
              ),
            ),
            child: TextField(
              style: const TextStyle(color: Color(0xFFE8E7EA)),
              decoration: InputDecoration(
                hintText: 'Search contact or username',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 18),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.grey.shade500,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Recent contacts row
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                final isSelected = _selectedContacts.contains(contact.name);
                return Container(
                  margin: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_selectedContacts.contains(contact.name)) {
                          _selectedContacts.remove(contact.name);
                        } else {
                          _selectedContacts.add(contact.name);
                        }
                      });
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 47,
                          height: 47,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade700,
                            border: isSelected
                                ? Border.all(color: Color(0xFF57A1FF), width: 2)
                                : null,
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              contact.image,
                              fit: BoxFit.cover,
                            ).localAsset(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          contact.name,
                          style: TextStyle(
                            color: isSelected
                                ? Color(0xFF57A1FF)
                                : Color(0xFFC4C6C8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: Color(0xFF2B2A30),
          ),

          const SizedBox(height: 20),

          // Create New Call Link
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.link,
                    color: Color(0xFF57A1FF),
                    size: 14,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Create New Call Link',
                  style: TextStyle(
                      color: Color(0xFF3498DB),
                      fontSize: 16,
                      fontWeight: FontWeight.w300),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Frequently Contacted section
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Frequently Contacted',
                style: TextStyle(
                  color: Color(0xFF82808F),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Contacts list with alphabet scroll
          Expanded(
            child: Stack(
              children: [
                // Contacts list
                ListView.builder(
                  padding: const EdgeInsets.only(
                      left: 16,
                      right: 40,
                      bottom: 20), // Add right padding for alphabet
                  itemCount: _getSortedContactsWithHeaders().length,
                  itemBuilder: (context, index) {
                    final item = _getSortedContactsWithHeaders()[index];

                    if (item['isHeader'] == true) {
                      // Section header
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          item['letter'],
                          style: const TextStyle(
                            color: Color(0xFFE8E7EA),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    } else {
                      // Contact item
                      final contact = item['contact'] as Contact;
                      final isSelected =
                          _selectedContacts.contains(contact.name);

                      return Container(
                        margin:
                            const EdgeInsets.only(bottom: 8), // Reduced margin
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedContacts.remove(contact.name);
                              } else {
                                _selectedContacts.add(contact.name);
                              }
                            });
                          },
                          child: Row(
                            children: [
                              Container(
                                width: 36, // Reduced size
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey.shade700,
                                  border: isSelected
                                      ? Border.all(
                                          color: Color(0xFF57A1FF), width: 2)
                                      : null,
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    contact.image,
                                    fit: BoxFit.cover,
                                  ).localAsset(),
                                ),
                              ),
                              const SizedBox(width: 12), // Reduced spacing
                              Expanded(
                                child: Text(
                                  contact.name,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Color(0xFF57A1FF)
                                        : Color(0xFFE8E7EA),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedContacts.remove(contact.name);
                                      print(_selectedContacts);
                                    } else {
                                      _selectedContacts.add(contact.name);
                                      print(_selectedContacts);
                                    }
                                  });
                                },
                                child: Container(
                                    width: 20, // Smaller selection circle
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? Color(0xFF57A1FF)
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? Color(0xFF57A1FF)
                                            : Colors.grey.shade600,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Container()),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),

                // Alphabet index on the right
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: -1,
                  child: Container(
                    width: 20,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _getAlphabetLetters().map((letter) {
                        // Check if this letter is the active one
                        final isActive = _currentActiveLetter == letter;
                        print(_currentActiveLetter == letter);
                        return GestureDetector(
                          onTap: () => _scrollToLetter(letter),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: isActive
                                ? BoxDecoration(
                                    color: Color(0xFF57A1FF),
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Text(
                              letter,
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : Colors.grey.shade500,
                                fontSize: 12, // Smaller font
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom buttons
          Container(
            color: const Color(0xFF161518),
            padding:
                const EdgeInsets.fromLTRB(16, 8, 16, 16), // Reduced top padding
            child: Column(
              children: [
                // Video Call button
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12), // Reduced padding
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F131B),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam,
                            color: Color(0xFFE8E7EA), size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Video Call',
                          style:
                              TextStyle(color: Color(0xFFE8E7EA), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8), // Reduced spacing
                // Call button with count
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12), // Reduced padding
                    decoration: BoxDecoration(
                      color: Color(0xFFC8DEFC),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.call,
                            color: Color(0xFFC8DEFC), size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Call',
                          style: TextStyle(
                              color: Color(0xFF121417),
                              fontSize: 18,
                              fontWeight: FontWeight.w700),
                        ),
                        if (_selectedContacts.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                '${_selectedContacts.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods to add to your class
  List<Map<String, dynamic>> _getSortedContactsWithHeaders() {
    // Sort contacts by name
    final sortedContacts = List<Contact>.from(_contacts)
      ..sort((a, b) => a.name.compareTo(b.name));

    List<Map<String, dynamic>> result = [];
    String currentLetter = '';

    for (final contact in sortedContacts) {
      final firstLetter = contact.name[0].toUpperCase();
      if (firstLetter != currentLetter) {
        // Add section header
        result.add({
          'isHeader': true,
          'letter': firstLetter,
        });
        currentLetter = firstLetter;
      }
      // Add contact
      result.add({
        'isHeader': false,
        'contact': contact,
      });
    }

    return result;
  }

  List<String> _getAlphabetLetters() {
    final letters = <String>{};
    for (final contact in _contacts) {
      letters.add(contact.name[0].toUpperCase());
    }
    return letters.toList()..sort();
  }

  void _scrollToLetter(String letter) {
    // Implement scroll to letter functionality if needed
    // This would require a ScrollController and calculating positions
  }
}

IconData _getCallIcon(CallType type) {
  switch (type) {
    case CallType.incoming:
      return Icons.call_received;
    case CallType.outgoing:
      return Icons.call_made;
    case CallType.missed:
      return Icons.call_received;
  }
}

Color _getCallColor(CallType type) {
  switch (type) {
    case CallType.incoming:
      return const Color(0xFF2ECC71);
    case CallType.outgoing:
      return Colors.grey;
    case CallType.missed:
      return const Color(0xFFE74C3C);
  }
}

class Contact {
  final String name;
  final String image;
  final bool isOnline;

  Contact({
    required this.name,
    required this.image,
    this.isOnline = false,
  });
}

class CallHistory {
  final Contact contact;
  final String time;
  final CallType type;
  final String duration;
  final int? count;

  CallHistory({
    required this.contact,
    required this.time,
    required this.type,
    required this.duration,
    this.count,
  });
}

enum CallType { incoming, outgoing, missed }
