import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:image_picker/image_picker.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  createState() => _SettingsTabState();
}

String get baseUrl => getEnv('API_BASE_URL');

class _SettingsTabState extends NyState<SettingsTab> {
  bool _hiddenProfile = false;
  String _username = "Alim Salim";
  String? _phoneNumber = "+971577563263";
  String? _userAvatar;
  int _imageKey = 0;

  // Track image upload status
  bool _isUploadingImage = false;
  String? _tempPickedImagePath;

  String? _email = "Alim Salim"; // Placeholder for user's full name
  String defaultAvatar = "image6.png";

  /// Shows a full-screen image preview when the profile image is tapped
  // Handle the logout process safely
  void _performLogout(BuildContext context) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent back button dismissal
          child: const Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF57A1FF)),
              ),
            ),
          ),
        );
      },
    );

    try {
      // Clear local auth data first - this is most important
      await Auth.logout();

      // Use routeTo to navigate to sign-in
      // This is safer than directly using Navigator
      routeTo('/sign-in', navigationType: NavigationType.pushAndForgetAll);
    } catch (e) {
      print('Error during logout: $e');

      // Make sure auth is cleared even if there's an error
      await Auth.logout();

      // Try the most direct way to get back to sign-in
      routeTo('/sign-in', navigationType: NavigationType.pushAndForgetAll);
    }
  }

  void _showFullScreenImage(BuildContext context,
      {required String imageUrl, required bool isAsset}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: Colors.black.withOpacity(0.9),
            body: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image with interactive viewer for zooming
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Hero(
                          tag: 'profile-image',
                          child: isAsset
                              ? Image.asset(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                ).localAsset()
                              : Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                            : null,
                                        color: Colors.white,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                  // Close button
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  get init => () async {
        final userData = await Auth.data();
        print("User data: $userData");
        if (userData != null) {
          setState(() {
            _username = userData['username'];
            _phoneNumber = userData['phone'];
            _userAvatar = userData['avatar']; // Default avatar
            _email = userData['email']; // Default full
            // _hiddenProfile = userData['hiddenProfile'] ?? false;
          });
        }
      };

  void _pickMedia() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      // Set the temporary image path and show loading state
      setState(() {
        _tempPickedImagePath = pickedFile.path;
        _isUploadingImage = true;
      });

      try {
        // Upload the image
        final resp = await ChatApiService().uploadAvatarImage(pickedFile.path);

        if (resp != null && resp.url != null) {
          // Update with the server image
          _imageKey++;
          setState(() {
            _imageKey++;
            _isUploadingImage = false;
            _tempPickedImagePath = null;
          });
        } else {
          // Handle upload failure
          setState(() {
            _isUploadingImage = false;
            _tempPickedImagePath = null;
          });

          // Show an error message
          showToast(
              title: "Error",
              description: "Failed to upload image. Please try again.");
        }
      } catch (e) {
        // Handle exceptions
        setState(() {
          _isUploadingImage = false;
          _tempPickedImagePath = null;
        });

        // Show an error message
        showToast(
            title: "Error",
            description: "Failed to upload image: ${e.toString()}");
      }
    }
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F131B),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // User Profile Section
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Profile Image with hover and pick media

                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact(); // Add haptic feedback

                        if (_tempPickedImagePath != null) {
                          // Show the temporary image in full screen
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              opaque: false,
                              pageBuilder:
                                  (context, animation, secondaryAnimation) {
                                return Scaffold(
                                  backgroundColor:
                                      Colors.black.withOpacity(0.9),
                                  body: SafeArea(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Center(
                                          child: GestureDetector(
                                            onTap: () =>
                                                Navigator.of(context).pop(),
                                            child: InteractiveViewer(
                                              minScale: 0.5,
                                              maxScale: 4.0,
                                              child: Hero(
                                                tag: 'profile-image',
                                                child: Image.file(
                                                  File(_tempPickedImagePath!),
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 16,
                                          right: 16,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.black.withOpacity(0.5),
                                              shape: BoxShape.circle,
                                            ),
                                            child: IconButton(
                                              icon: const Icon(Icons.close,
                                                  color: Colors.white),
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                            ),
                                          ),
                                        ),
                                        if (_isUploadingImage)
                                          Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CircularProgressIndicator(
                                                    color: Colors.white),
                                                SizedBox(height: 16),
                                                Text(
                                                  'Uploading...',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              transitionsBuilder: (context, animation,
                                  secondaryAnimation, child) {
                                return FadeTransition(
                                    opacity: animation, child: child);
                              },
                            ),
                          );
                        } else if (_userAvatar != null &&
                            _userAvatar != defaultAvatar) {
                          _showFullScreenImage(
                            context,
                            imageUrl:
                                '${baseUrl}$_userAvatar?refresh=$_imageKey',
                            isAsset: false,
                          );
                        } else {
                          _showFullScreenImage(
                            context,
                            imageUrl: defaultAvatar,
                            isAsset: true,
                          );
                        }
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                            ),
                            child: ClipOval(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Show either temporary image, network image, or default image
                                  if (_tempPickedImagePath != null)
                                    Hero(
                                      tag: 'profile-image',
                                      child: Image.file(
                                        File(_tempPickedImagePath!),
                                        fit: BoxFit.cover,
                                        width: 80,
                                        height: 80,
                                      ),
                                    )
                                  else if (_userAvatar != null &&
                                      _userAvatar != defaultAvatar)
                                    Hero(
                                      tag: 'profile-image',
                                      child: Image.network(
                                        '${baseUrl}$_userAvatar?refresh=$_imageKey',
                                        key: ValueKey(_imageKey),
                                        fit: BoxFit.cover,
                                        width: 80,
                                        height: 80,
                                      ),
                                    )
                                  else
                                    Hero(
                                      tag: 'profile-image',
                                      child: Image.asset(
                                        defaultAvatar,
                                        fit: BoxFit.cover,
                                        width: 80,
                                        height: 80,
                                      ).localAsset(),
                                    ),

                                  // Show loading indicator when uploading
                                  if (_isUploadingImage)
                                    Container(
                                      width: 80,
                                      height: 80,
                                      color: Colors.black.withOpacity(0.5),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 3,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickMedia,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Color(0xFF57A1FF),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // User Name
                    Text(
                      "@" + _username,
                      style: TextStyle(
                        color: Color(0xFFE8E7EA),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Phone Number and Username
                    Text(
                      '${_phoneNumber ?? _email} | $_username',
                      style: TextStyle(
                        color: Color(0xFF8E9297),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // Settings Options
              _buildSettingsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // First Group - Main Settings
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C212C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Profile Details
                _buildSettingsItem(
                  // icon: Icons.person_outline,
                  imagePath: "profile_icon.png",
                  title: 'Profile Details',
                  onTap: () {
                    // routeTo(ProfileDetailsPage.path);
                  },
                  showDivider: true,
                ),

                // Security
                _buildSettingsItem(
                  // icon: Icons.security_outlined,
                  imagePath: "security_icon.png",
                  title: 'Security',
                  onTap: () {
                    // Navigate to security settings
                  },
                  showDivider: true,
                ),

                // Chats
                _buildSettingsItem(
                  // icon: Icons.chat_bubble_outline,
                  imagePath: "chat_icon.png",
                  title: 'Chats',
                  onTap: () {
                    // Navigate to chat settings
                  },
                  showDivider: true,
                ),

                // Notifications
                _buildSettingsItem(
                  // icon: Icons.notifications_outlined,
                  imagePath: "notification_icon.png",
                  title: 'Notifications',
                  onTap: () {
                    // Navigate to notification settings
                  },
                  showDivider: false,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Hidden Profile Toggle - Separate Section
          _buildHiddenProfileToggle(),

          const SizedBox(height: 16),

          // Second Group - Additional Settings
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C212C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Subscription
                _buildSettingsItem(
                  // icon: Icons.star_outline,
                  imagePath: "subscription_icon.png",
                  title: 'Subscription',
                  onTap: () {
                    // Navigate to subscription
                  },
                  showDivider: true,
                ),

                // Help and Feedback
                _buildSettingsItem(
                  // icon: Icons.help_outline,
                  imagePath: "feedback_icon.png",
                  title: 'Help and feedback',
                  onTap: () {
                    // Navigate to help
                  },
                  showDivider: true,
                ),

                // Share Stillur
                _buildSettingsItem(
                  // icon: Icons.share_outlined,
                  imagePath: "share_icon.png",
                  title: 'Share Stillur',
                  onTap: () {
                    // Share app
                  },
                  showDivider: false,
                ),
                _buildSettingsItem(
                  imagePath: "share_icon.png",
                  title: 'Log Out',
                  textColor: Colors.red,
                  onTap: () {
                    // Show confirmation dialog
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          backgroundColor: const Color(0xFF1C212C),
                          title: const Text(
                            'Log Out',
                            style: TextStyle(
                              color: Color(0xFFE8E7EA),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          content: const Text(
                            'Are you sure you want to log out?',
                            style: TextStyle(
                              color: Color(0xFFE8E7EA),
                            ),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop(); // Close dialog
                              },
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Color(0xFF8E9297),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                // Close the dialog first
                                Navigator.of(context).pop();

                                // Use a simpler logout approach
                                _performLogout(context);
                              },
                              child: const Text(
                                'Log Out',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  showDivider: false,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
    IconData? icon,
    String? imagePath,
    required String title,
    required VoidCallback onTap,
    bool showDivider = false,
    Color? textColor,
  }) {
    assert(icon != null || imagePath != null,
        'Either icon or imagePath must be provided');
    assert(!(icon != null && imagePath != null),
        'Cannot provide both icon and imagePath');

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  // Display either icon or image
                  if (icon != null)
                    Icon(
                      icon,
                      color: Color(0xFF57A1FF),
                      size: 20,
                    )
                  else if (imagePath != null)
                    Container(
                      width: 20,
                      height: 20,
                      child: Image.asset(
                        imagePath,
                        fit: BoxFit.contain,
                      ).localAsset(),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: textColor ?? Color(0xFFE8E7EA),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF8E9297),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Container(
            margin: const EdgeInsets.only(left: 52),
            height: 1,
            color: Color(0xFF2B2A30),
          ),
      ],
    );
  }

  Widget _buildHiddenProfileToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C212C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // const Icon(
              //   Icons.lock_outline,
              //   color: Color(0xFF57A1FF),
              //   size: 20,
              // ),
              Image.asset(
                "lock_icon.png",
                width: 20,
                height: 20,
              ).localAsset(),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Hidden Profile',
                  style: TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Switch(
                value: _hiddenProfile,
                onChanged: (value) {
                  setState(() {
                    _hiddenProfile = value;
                  });
                },
                activeTrackColor: const Color(0xFF3498DB),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.shade700,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(
              'Hide your profile details so others cannot see them.',
              style: TextStyle(
                color: Color(0xFF8E9297),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
