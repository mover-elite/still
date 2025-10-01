import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/video_call_page.dart';
import 'package:flutter_app/resources/pages/voice_call_page.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:flutter_app/app/models/media_response.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

class ProfileDetailsPage extends NyStatefulWidget {
  static RouteView path = ("/profile-details", (_) => ProfileDetailsPage());

  ProfileDetailsPage({super.key})
      : super(child: () => _ProfileDetailsPageState());
}

class _ProfileDetailsPageState extends NyPage<ProfileDetailsPage> {
  int _selectedTab = 0; // 0: Media, 1: Files, 2: Links
  final ScrollController _scrollController = ScrollController();
  bool _showCollapsedHeader = false;
  String _userName = '';
  String? _userImage;
  String defaultImage = 'image2.png';
  int? _chatId;

  // Remote media state
  bool _isLoadingMedia = false;
  bool _mediaError = false;
  List<MediaResponse> _mediaItems = [];
  bool _mediaFetchAttempted = false; // prevents repeated fetch loops
  // Video preview controllers (for grid thumbnails)
  final Map<String, VideoPlayerController> _videoThumbControllers = {};
  final Set<String> _videoThumbInitializing = {};
  final Set<String> _videoThumbErrors = {};


  @override
  get init => () {
        _scrollController.addListener(_onScroll);
        _loadUserData();
      };

  void _onScroll() {
    final showCollapsed = _scrollController.offset > 200;
    if (showCollapsed != _showCollapsedHeader) {
      setState(() {
        _showCollapsedHeader = showCollapsed;
      });
    }
  }

  void _loadUserData() {
    final navigationData = data();
    print(navigationData['partner'].toJson());
    print(navigationData);
    setState(() {
      _userName = navigationData?['userName'] ?? 'User Name';
      _userImage = navigationData?['userImage'];
      _chatId = navigationData?['chatId'];
    });

    if (_chatId != null) {
      _fetchChatMedia();
    }
  }

  Future<void> _fetchChatMedia() async {
    if (_chatId == null) return;
    if (_mediaFetchAttempted) return; // already fetched or in progress
    _mediaFetchAttempted = true;
    setState(() {
      _isLoadingMedia = true;
      _mediaError = false;
    });
    try {
      final list = await ChatApiService().getChatMedia(_chatId!);
      print("Fetched media items count: ${list?.length ?? 0}");
      _mediaItems = list ?? [];
    } catch (e) {
      debugPrint('Error fetching chat media: $e');
      _mediaError = true;
      _mediaFetchAttempted = false; // allow retry if it failed
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMedia = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Dispose video thumbnail controllers
    for (final c in _videoThumbControllers.values) {
      c.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget view(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F131B),
      body: SafeArea(
        child: Column(
          children: [
            // Dynamic Header
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _showCollapsedHeader ? 60 : 0,
              child:
                  _showCollapsedHeader ? _buildCollapsedHeader() : Container(),
            ),

            // Main Content with ScrollView
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    // Profile Info Section
                    _buildProfileInfo(),

                    // Action Buttons
                    _buildActionButtons(),

                    // About Section (always visible)
                    _buildAboutSection(),

                    // Media Tabs
                    _buildMediaTabs(),

                    // Content based on selected tab
                    _buildTabContent(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0F131B),
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF1C212C),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_ios,
              color: Color(0xFFE8E7EA),
              size: 16,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            _userName,
            style: const TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 18,
              fontFamily: 'PlusJakartaSans',
              fontWeight: FontWeight.w400,
              height: 21 / 18,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          Text(
            _getTabCount(),
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
              fontFamily: 'PlusJakartaSans',
              fontWeight: FontWeight.w400,
              height: 21 / 14,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  String _getTabCount() {
    switch (_selectedTab) {
      case 0:
        return '20 media';
      case 1:
        return '8 files';
      case 2:
        return '10 links';
      default:
        return '';
    }
  }

  Widget _buildProfileInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Profile Image
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: (_userImage != null && _userImage != defaultImage)
                  ? Image.network(
                      '$_userImage',
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    )
                  : Image.asset(
                    defaultImage,
                    fit: BoxFit.cover,
                    width: 80,
                    height: 80,
                  ).localAsset(),
              ),
          ),

          const SizedBox(height: 16),

          // Name
          Text(
            _userName,
            style: const TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 20,
              fontFamily: 'PlusJakartaSans',
              fontWeight: FontWeight.w400,
              height: 21 / 20,
              letterSpacing: 0,
            ),
          ),

          const SizedBox(height: 4),

          // Last Seen
          Text(
            'Last seen 3 hours ago',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
              fontFamily: 'PlusJakartaSans',
              fontWeight: FontWeight.w400,
              height: 21 / 14,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Call Button
          _buildActionButton(
            icon: Icons.call,
            onTap: () {
              final navigationData = data();
              // Make voice call
              Navigator.pushNamed(context, VoiceCallPage.path.name, arguments: {
                'partner': navigationData?['partner'].toJson(),
                "isGroup": navigationData?['isGroup'] ?? false,
                "chatId": navigationData?['chatId'],
                "initiateCall": true,
              });
            },
          ),

          // Video Call Button
          _buildActionButton(
            icon: Icons.videocam,
            onTap: () {
              final navigationData = data();
              
            Navigator.pushNamed(context, VideoCallPage.path.name, arguments: {
              'partner': navigationData?['partner'].toJson(),
              "isGroup": navigationData?['isGroup'] ?? false,
              "chatId": navigationData?['chatId'],
              "initiateCall": true,
            });
          },
          ),

          // Search Button
          _buildActionButton(
            icon: Icons.search,
            onTap: () {
              // Search in chat
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        child: Icon(
          icon,
          color: const Color(0xFFE8E7EA),
          size: 24,
        ),
      ),
    );
  }

  Widget _buildAboutSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About $_userName',
            style: const TextStyle(
              color: Color(0xFFE8E7EA),
              fontSize: 16,
              fontWeight: FontWeight.w400,
              fontFamily: 'PlusJakartaSans',
              height: 21 / 16,
              letterSpacing: 0,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            "I'm a software engineer passionate about building secure and private communication tools.",
            style: TextStyle(
              color: Colors.grey.shade300,
              fontSize: 14,
              fontFamily: 'PlusJakartaSans',
              fontWeight: FontWeight.w400,
              height: 21 / 14,
              letterSpacing: 0,
            ),
          ),

          const SizedBox(height: 16),

          // Username
          _buildInfoItem('Username', _userName),

          const SizedBox(height: 12),

          // Phone Number
          _buildInfoItem('Phone Number', '+971 57 7563 263'),

          const SizedBox(height: 12),

          // Email
          _buildInfoItem('Email', 'laylabmoney@stillur.com'),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 12,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w400,
            height: 21 / 12,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFE8E7EA),
            fontSize: 14,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w400,
            height: 21 / 14,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }

  Widget _buildMediaTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildTab('Media', 0),
          _buildTab('Files', 1),
          _buildTab('Links', 2),
        ],
      ),
    );
  }

  Widget _buildTab(String title, int index) {
    final bool isSelected = _selectedTab == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color:
                  isSelected ? const Color(0xFFE8E7EA) : Colors.grey.shade500,
              fontSize: 14,
              fontFamily: 'PlusJakartaSans',
              fontWeight: FontWeight.w400,
              height: 21 / 14,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          // Underline for active tab
          Container(
            height: 2,
            width: title.length * 8.0,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE8E7EA) : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildMediaGrid();
      case 1:
        return _buildFilesContent();
      case 2:
        return _buildLinksContent();
      default:
        return Container();
    }
  }

  Widget _buildMediaGrid() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: _isLoadingMedia
          ? _buildMediaLoadingSkeleton()
          : _mediaError
              ? _buildMediaError()
              : _mediaItems.isEmpty
                  ? _buildEmptyMediaState()
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                        childAspectRatio: 1,
                      ),
                      itemCount: _mediaItems.length,
                      itemBuilder: (context, index) {
                        final media = _mediaItems[index];
                        final base = getEnv("API_BASE_URL") ?? '';
                        final baseNormalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
                        final mediaUrl = '$baseNormalized/uploads/${media.fileId}';
                        final isVideo = media.type.toUpperCase() == 'VIDEO';
                        return GestureDetector(
                          onTap: () {
                            if (isVideo) {
                              _openVideoViewer(mediaUrl);
                            } else {
                              _openImageViewer(mediaUrl);
                            }
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (!isVideo)
                                  Image.network(
                                    mediaUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFF1C212C),
                                      child: const Icon(Icons.broken_image, color: Colors.grey),
                                    ),
                                  )
                                else
                                  _buildVideoThumbnail(media.fileId, mediaUrl),
                                if (isVideo)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black26,
                                      child: const Center(
                                        child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 40),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildVideoThumbnail(String fileId, String url) {
    // If error occurred
    if (_videoThumbErrors.contains(fileId)) {
      return Container(
        color: const Color(0xFF1C212C),
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }

    // Existing initialized controller
    final existing = _videoThumbControllers[fileId];
    if (existing != null && existing.value.isInitialized) {
      final aspect = existing.value.aspectRatio == 0 ? 1.0 : existing.value.aspectRatio;
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: 100 * aspect,
            height: 100,
            child: VideoPlayer(existing),
        ),
      );
    }

    // Kick off initialization if not already
    if (!_videoThumbInitializing.contains(fileId)) {
      _videoThumbInitializing.add(fileId);
      _initVideoThumb(fileId, url);
    }

    // Loading placeholder
    return Container(
      color: const Color(0xFF1C212C),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      ),
    );
  }

  Future<void> _initVideoThumb(String fileId, String url) async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      // Pause to show only first frame
      controller.pause();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _videoThumbControllers[fileId] = controller;
      });
    } catch (e) {
      debugPrint('Video thumbnail init failed for $fileId: $e');
      if (mounted) {
        setState(() {
          _videoThumbErrors.add(fileId);
        });
      }
    } finally {
      _videoThumbInitializing.remove(fileId);
    }
  }

  Widget _buildMediaLoadingSkeleton() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1,
      ),
      itemCount: 9,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C212C),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  Widget _buildMediaError() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
        const SizedBox(height: 12),
        const Text(
          'Failed to load media',
          style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _fetchChatMedia,
          child: const Text('Retry'),
        )
      ],
    );
  }

  Widget _buildEmptyMediaState() {
    return Column(
      children: const [
        SizedBox(height: 40),
        Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
        SizedBox(height: 12),
        Text(
          'No media found yet',
          style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 14),
        ),
      ],
    );
  }

  /* Media Viewers */
  void _openImageViewer(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white70, size: 60),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openVideoViewer(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) => _VideoPlayerDialog(videoUrl: url),
    );
  }

  Widget _buildFilesContent() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          _buildFileItem(
              'Image.png', '2.6 MB', 'mar 3, 2025 at 12:46', Icons.image),
          _buildFileItem('Stillur.zip', '2.6 MB', 'mar 3, 2025 at 12:46',
              Icons.folder_zip),
          _buildFileItem('Stillur.xlsx', '2.6 MB', 'mar 3, 2025 at 12:46',
              Icons.table_chart),
          _buildFileItem('Stillur.pdf', '2.6 MB', 'mar 3, 2025 at 12:46',
              Icons.picture_as_pdf),
          _buildFileItem(
              'Stillur.zip', '2.6 MB', 'mar 3, 2025 at 12:46', Icons.folder_zip,
              showDownload: true),
          _buildFileItem('Stillur.xlsx', '2.6 MB', 'mar 3, 2025 at 12:46',
              Icons.table_chart,
              showDownload: true),
          _buildFileItem('Stillur.pdf', '2.6 MB', 'mar 3, 2025 at 12:46',
              Icons.picture_as_pdf,
              showDownload: true),
          _buildFileItem(
              'Stillur.zip', '2.6 MB', 'mar 3, 2025 at 12:46', Icons.folder_zip,
              showDownload: true),
        ],
      ),
    );
  }

  Widget _buildFileItem(
      String fileName, String fileSize, String date, IconData icon,
      {bool showDownload = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C212C),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade700,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              color: Colors.grey.shade300,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$fileSize • $date',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (showDownload)
            Icon(
              Icons.download,
              color: Colors.grey.shade400,
              size: 20,
            ),
        ],
      ),
    );
  }

  Widget _buildLinksContent() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          _buildLinkItem(
              'Google',
              'Real-time meetings by Google. Using your browser, share your video, desktop, and presentations with teammates and customers...',
              'https://meet.google.com/landing'),
          _buildLinkItem(
              'Google',
              'Real-time meetings by Google. Using your browser, share your video, desktop, and presentations with teammates and customers...',
              'https://meet.google.com/landing'),
          _buildLinkItem(
              'Google',
              'Real-time meetings by Google. Using your browser, share your video, desktop, and presentations with teammates and customers...',
              'https://meet.google.com/landing'),
          _buildLinkItem(
              'Google',
              'Real-time meetings by Google. Using your browser, share your video, desktop, and presentations with teammates and customers...',
              'https://meet.google.com/landing'),
          _buildMonthSeparator('July 2025'),
          _buildLinkItem(
              'Google',
              'Real-time meetings by Google. Using your browser, share your video, desktop, and presentations with teammates and customers...',
              'https://meet.google.com/landing'),
          _buildLinkItem(
              'Google',
              'Real-time meetings by Google. Using your browser, share your video, desktop, and presentations with teammates and customers...',
              'https://meet.google.com/landing'),
          _buildLinkItem(
              'Google',
              'Real-time meetings by Google. Using your browser, share your video, desktop, and presentations with teammates and customers...',
              'https://meet.google.com/landing'),
          _buildLinkItem(
              'Google',
              'Real-time meetings by Google. Using your browser, share your video, desktop, and presentations with teammates and customers...',
              'https://meet.google.com/landing'),
          _buildMonthSeparator('June 2025'),
          _buildLinkItem(
              'Google',
              'Real-time meetings by Google. Using your browser, share your video, desktop, and presentations with teammates and customers...',
              'https://meet.google.com/landing'),
        ],
      ),
    );
  }

  Widget _buildLinkItem(String title, String description, String url) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C212C),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue.shade600,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.videocam,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFE8E7EA),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  url,
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSeparator(String month) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: Colors.grey.shade700,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              month,
              style: const TextStyle(
                color: Color(0xFFE8E7EA),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  final String videoUrl;
  const _VideoPlayerDialog({required this.videoUrl});

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final vc = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await vc.initialize();
      final cc = ChewieController(
        videoPlayerController: vc,
        autoPlay: true,
        looping: false,
        allowFullScreen: false,
        allowMuting: true,
        showControlsOnInitialize: true,
      );
      if (!mounted) return;
      setState(() {
        _videoController = vc;
        _chewieController = cc;
      });
    } catch (e) {
      debugPrint('Video init error: $e');
      if (mounted) {
        setState(() => _initError = true);
      }
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Center(
              child: _initError
                  ? const Icon(Icons.error_outline, color: Colors.white70, size: 60)
                  : (_chewieController == null || !_videoController!.value.isInitialized)
                      ? const SizedBox(
                          width: 60,
                          height: 60,
                          child: CircularProgressIndicator(color: Colors.white70),
                        )
                      : AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: Chewie(controller: _chewieController!),
                        ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
