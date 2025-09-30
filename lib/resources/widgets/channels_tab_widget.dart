import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nylo_framework/nylo_framework.dart';

class ChannelsTab extends StatefulWidget {
  const ChannelsTab({super.key});

  @override
  createState() => _ChannelsTabState();
}

class _ChannelsTabState extends NyState<ChannelsTab> {
  bool _showMyChannels = true;
  List<Channel> _myChannels = [];
  List<Channel> _joinedChannels = [
    Channel(
      name: "Fast Cars Reviewers Club",
      description:
          "McLaren Artura Spider, A combination of Twin-Turbocharged V6 Petrol Engine and powerful, ultra-efficient...",
      image: "image9.png",
      hasNotification: true,
    ),
    Channel(
      name: "Fast Cars Reviewers Club",
      description:
          "McLaren Artura Spider, A combination of Twin-Turbocharged V6 Petrol Engine and powerful, ultra-efficient...",
      image: "image9.png",
      hasNotification: true,
    ),
    Channel(
      name: "Fast Cars Reviewers Club",
      description:
          "McLaren Artura Spider, A combination of Twin-Turbocharged V6 Petrol Engine and powerful, ultra-efficient...",
      image: "image9.png",
      hasNotification: true,
    ),
  ];

  final List<Contact> _contacts = [
    Contact(name: "Layla B", image: "image2.png"),
    Contact(name: "Eleanor", image: "image1.png"),
    Contact(name: "Sheilla", image: "image5.png"),
    Contact(name: "Sandra", image: "image4.png"),
    Contact(name: "Fenta", image: "image8.png"),
    Contact(name: "Arthur", image: "image6.png"),
    Contact(name: "Amanda", image: "image7.png"),
    Contact(name: "Al-Amin", image: "image3.png"),
    Contact(name: "Ahmad", image: "image10.png"),
  ];

  // Add missing variable for alphabet scroll
  String _currentActiveLetter = '';

  @override
  get init => () {};

  void _showCreateChannelFlow() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CreateChannelStep1(),
    );
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F131B),
      body: Column(
        children: [
          // Top section with proper layout
          Container(
            color: Color(0xff1C212C),
            padding: const EdgeInsets.only(top: 50, left: 16, right: 16),
            child: Column(
              children: [
                // Stillur logo aligned to left
                // Container(
                //   padding: const EdgeInsets.only(bottom: 4),
                //   child: Align(
                //     alignment: Alignment.centerLeft,
                //     child: Container(
                //       width: 50,
                //       height: 13,
                //       child: Image.asset('stillurlogo.png').localAsset(),
                //     ),
                //   ),
                // ),

                // Tabs row with search on extreme right
                Row(
                  children: [
                    // Channel tabs
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showMyChannels = true;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          border: _showMyChannels
                              ? const Border(
                                  bottom: BorderSide(
                                      color: Color(0xFF3B69C6), width: 2))
                              : null,
                        ),
                        child: Text(
                          'My Channels',
                          style: TextStyle(
                            color: _showMyChannels
                                ? Color(0xFFFFFFFF)
                                : Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showMyChannels = false;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          border: !_showMyChannels
                              ? const Border(
                                  bottom: BorderSide(
                                      color: Color(0xFF3B69C6), width: 2))
                              : null,
                        ),
                        child: Text(
                          'Joined Channels',
                          style: TextStyle(
                            color: !_showMyChannels
                                ? Color(0xFFE8E7EA)
                                : Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    // Spacer to push search to extreme right
                    const Spacer(),

                    // Search icon on extreme right
                    IconButton(
                      icon: const Icon(Icons.search, color: Color(0xFFE8E7EA)),
                      onPressed: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),

          // Content area
          Expanded(
            child: _showMyChannels
                ? _buildMyChannelsView()
                : _buildJoinedChannelsView(),
          ),
        ],
      ),
    );
  }

  Widget _buildMyChannelsView() {
    if (_myChannels.isEmpty) {
      return Column(
        children: [
          // Empty state content first
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Folder image placeholder
                Container(
                  width: 120,
                  height: 120,
                  child: Image.asset(
                    'channel.png', // Replace with your actual image
                    fit: BoxFit.contain,
                  ).localAsset(),
                ),

                const SizedBox(height: 32),

                const Text(
                  'Be a part of a Private Channels',
                  style: TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Your created or joined channels will\nshow up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8E9297),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 40),

                // Create My Channel button moved below the text
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _showCreateChannelFlow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C212C),
                      foregroundColor: Color(0xFFE8E7EA),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 14, color: Color(0xffAACFFF)),
                        SizedBox(
                          width: 8,
                        ),
                        Text('Create My Channel',
                            style: TextStyle(
                                fontSize: 16, color: Color(0xffAACFFF))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      return _buildChannelsList(_myChannels);
    }
  }

  Widget _buildJoinedChannelsView() {
    return Column(
      children: [
        // Create My Channel button
        Container(
          margin: const EdgeInsets.all(16),
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _showCreateChannelFlow,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1C212C),
              foregroundColor: Color(0xFFE8E7EA),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 14),
                SizedBox(width: 8),
                Text('Create My Channel', style: TextStyle(fontSize: 18)),
              ],
            ),
          ),
        ),
        Expanded(child: _buildChannelsList(_joinedChannels)),
      ],
    );
  }

  Widget _buildChannelsList(List<Channel> channels) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C212C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade700,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    channel.image,
                    fit: BoxFit.cover,
                  ).localAsset(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: const TextStyle(
                        color: Color(0xFFE8E7EA),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      channel.description,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (channel.hasNotification)
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3498DB),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _CreateChannelStep1() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xff1B1C1D),
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
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 14),
                  ),
                ),
                const Text(
                  'Create Channel',
                  style: TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 60),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Camera icon and Channel Name on same row
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF3498DB), width: 2),
                        ),
                        child: Image.asset("channel_camera.png").localAsset(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF1F1F1F),
                                Color(0xB2919191), // #919191B2 (70% opacity)
                                // #1F1F1F
                              ],
                              stops: [0.3, 1.0],
                            ),
                          ),
                          padding: EdgeInsets.all(1.5), // Border thickness
                          child: TextField(
                            controller: nameController,
                            style: const TextStyle(color: Color(0xFFE8E7EA)),
                            decoration: InputDecoration(
                              hintText: 'Channel Name',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                              ),
                              filled: true,
                              fillColor: Color(0xff1B1C1D), // Match background
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.5),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.5),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.5),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Description field
                  Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF1F1F1F),
                            Color(0xB2919191), // #919191B2 (70% opacity)
                            // #1F1F1F
                          ],
                          stops: [0.3, 1.0],
                        ),
                      ),
                      padding: EdgeInsets.all(1.5), // Border thickness
                      child: TextField(
                        controller: descriptionController,
                        style: const TextStyle(color: Color(0xFFE8E7EA)),
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Description',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: Color(0xff1B1C1D),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade700,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade700,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade600,
                              width: 1,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      )),

                  const SizedBox(height: 8),

                  Text(
                    'You can provide an optional description for your channel',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 32), // Fixed spacing instead of Spacer

                  // Next button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showChannelTypeSettings(
                            nameController.text, descriptionController.text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xffC8DEFC),
                        foregroundColor: Color(0xFFE8E7EA),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      child: const Text(
                        'Next',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xff121417),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  void _showChannelTypeSettings(String channelName, String description) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ChannelTypeScreen(channelName, description),
      ),
    );
  }

  Widget _ChannelTypeScreen(String channelName, String description) {
    bool isPrivate = true;
    bool restrictContent = false;

    return StatefulBuilder(
      builder: (context, setModalState) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F131B), // Main page background
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F131B),
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios,
                  color: Color(0xFFE8E7EA), size: 20),
            ),
            title: const Text(
              'Channel Type',
              style: TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showContactSelection();
                },
                child: const Text(
                  'Next',
                  style: TextStyle(color: Color(0xFF3498DB), fontSize: 16),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Channel Type Selection Section
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C212C), // Section background
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Public option
                        GestureDetector(
                          onTap: () {
                            setModalState(() {
                              isPrivate = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: !isPrivate
                                          ? const Color(0xFF3498DB)
                                          : Colors.grey.shade600,
                                      width: 2,
                                    ),
                                  ),
                                  child: !isPrivate
                                      ? Container(
                                          margin: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF3498DB),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                const Text(
                                  'Public',
                                  style: TextStyle(
                                    color: Color(0xFFE8E7EA),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Divider
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          height: 1,
                          color: Colors.grey.shade800,
                        ),

                        // Private option
                        GestureDetector(
                          onTap: () {
                            setModalState(() {
                              isPrivate = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isPrivate
                                          ? const Color(0xFF3498DB)
                                          : Colors.grey.shade600,
                                      width: 2,
                                    ),
                                  ),
                                  child: isPrivate
                                      ? Container(
                                          margin: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF3498DB),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                const Text(
                                  'Private',
                                  style: TextStyle(
                                    color: Color(0xFFE8E7EA),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (isPrivate) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Private channel can only be joined via link',
                        style: TextStyle(
                          color: Color(0xff82808F),
                          fontSize: 13,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Invite Link section
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C212C), // Section background
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header inside the container
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Text(
                              'INVITE LINK',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),

                          // Link row - compact width
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Color(0xff0F131B),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    's.me/+CGHSDhdkgjudkj',
                                    style: const TextStyle(
                                      color: Color(0xFFE8E7EA),
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Color(0xFFC8DEFC),
                                        shape: BoxShape.circle,
                                      ),
                                      padding: EdgeInsets.all(
                                          8.0), // Add padding for better visual appearance
                                      child: const Icon(
                                        Icons.more_horiz,
                                        color: Color(0xff0F131B),
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Share Link button inside the container
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 22, 20),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(
                                      0xFFC8DEFC), // Button background
                                  foregroundColor: const Color(
                                      0xFF0F131B), // Button text color (dark)
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Share Link',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'People can join channel by following this link.\nYou can revoke the link at any time.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.left,
                    ),

                    const SizedBox(height: 40),

                    // Saving and Copying Content section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'SAVING AND COPYING CONTENT',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C212C), // Section background
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Restrict Saving Content',
                            style: TextStyle(
                              color: Color(0xFFE8E7EA),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Switch(
                            value: restrictContent,
                            onChanged: (value) {
                              setModalState(() {
                                restrictContent = value;
                              });
                            },
                            activeThumbColor: const Color(0xFF3498DB),
                            inactiveThumbColor: Colors.grey.shade400,
                            inactiveTrackColor: Colors.grey.shade700,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 6,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Subscribe will be able to copy, save and forward content from this channel',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Add missing methods
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
    setState(() {
      _currentActiveLetter = letter;
    });
  }

  void _showContactSelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ContactSelection(),
    );
  }

  Widget _ContactSelection() {
    List<Contact> selectedContacts = [];

    return StatefulBuilder(
      builder: (context, setModalState) {
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
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 84,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Color(0xFFC4C6C8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

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
                      'Contact',
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
                    hintStyle:
                        TextStyle(color: Colors.grey.shade500, fontSize: 18),
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
                    final isSelected = selectedContacts.contains(contact);
                    return Container(
                      margin: const EdgeInsets.only(right: 16),
                      child: GestureDetector(
                        onTap: () {
                          setModalState(() {
                            if (selectedContacts.contains(contact)) {
                              selectedContacts.remove(contact);
                            } else {
                              selectedContacts.add(contact);
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

              // Invite link section
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
                        Icons.content_copy,
                        color: Color(0xFF57A1FF),
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      's.me/+CGHSDhdkgjudkj',
                      style: TextStyle(
                          color: Color(0xFF3498DB),
                          fontSize: 16,
                          fontWeight: FontWeight.w300),
                    ),
                  ],
                ),
              ),

              Container(
                height: 0.5,
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                color: Color(0xFF2B2A30),
              ),

              // Frequently Contacted section
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
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
                          final isSelected = selectedContacts.contains(contact);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  if (isSelected) {
                                    selectedContacts.remove(contact);
                                  } else {
                                    selectedContacts.add(contact);
                                  }
                                });
                              },
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.grey.shade700,
                                      border: isSelected
                                          ? Border.all(
                                              color: Color(0xFF57A1FF),
                                              width: 2)
                                          : null,
                                    ),
                                    child: ClipOval(
                                      child: Image.asset(
                                        contact.image,
                                        fit: BoxFit.cover,
                                      ).localAsset(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
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
                                      setModalState(() {
                                        if (isSelected) {
                                          selectedContacts.remove(contact);
                                        } else {
                                          selectedContacts.add(contact);
                                        }
                                      });
                                    },
                                    child: Container(
                                      width: 20,
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
                                      child: Container(),
                                    ),
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
                      bottom: 0,
                      child: Container(
                        width: 20,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _getAlphabetLetters().map((letter) {
                            // Check if this letter is the active one
                            final isActive = _currentActiveLetter == letter;
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
                                    fontSize: 10,
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

              // Send button
              Container(
                color: const Color(0xFF161518),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Color(0xFFC8DEFC),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Send',
                          style: TextStyle(
                              color: Color(0xFF121417),
                              fontSize: 18,
                              fontWeight: FontWeight.w700),
                        ),
                        if (selectedContacts.isNotEmpty) ...[
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
                                '${selectedContacts.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        const Icon(Icons.send,
                            color: Color(0xFF121417), size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Helper functions and IconData methods
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

// Model classes
class Channel {
  final String name;
  final String description;
  final String image;
  final bool hasNotification;

  Channel({
    required this.name,
    required this.description,
    required this.image,
    this.hasNotification = false,
  });
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
