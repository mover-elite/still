import 'package:flutter/material.dart';
import 'package:flutter_app/resources/pages/video_call_page.dart';
import 'package:flutter_app/resources/pages/voice_call_page.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:flutter_app/app/networking/chat_api_service.dart';
import 'package:flutter_app/app/models/media_response.dart';
import 'package:flutter_app/app/models/chat_links_response.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/utils.dart';

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

  // Files (DOCUMENT, AUDIO, VOICE)
  bool _isLoadingFiles = false;
  bool _filesError = false;
  bool _filesFetchAttempted = false;
  List<MediaResponse> _fileItems = [];
  final Map<String, String> _cachedFileLocalPaths = {}; // fileId -> local path
  final Map<String, bool> _downloadingFile = {}; // fileId -> in progress

  // Links
  bool _isLoadingLinks = false;
  bool _linksError = false;
  bool _linksFetchAttempted = false;
  List<LinkResponse> _linkItems = [];
  final Map<String, List<String>> _extractedLinksCache = {}; // messageId -> extracted URLs


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
    
    setState(() {
      _userName = navigationData?['userName'] ?? 'User Name';
      _userImage = navigationData?['userImage'];
      _chatId = navigationData?['chatId'];
    });

    if (_chatId != null) {
      _fetchChatMedia();
      _fetchChatFiles();
    }
  }

  Future<void> _fetchChatLinks() async {
    if (_chatId == null) return;
    if (_linksFetchAttempted) return;
    _linksFetchAttempted = true;
    setState(() {
      _isLoadingLinks = true;
      _linksError = false;
    });
    try {
      final list = await ChatApiService().getChatLinks(_chatId!);
      print("Fetched link items count: ${list?.length ?? 0}");
      _linkItems = list ?? [];
      
      // Extract links from text and caption for each message
      _extractedLinksCache.clear();
      for (final linkItem in _linkItems) {
        List<String> allLinks = [];
        
        // Extract from text if it exists
        if (linkItem.text != null && linkItem.text!.isNotEmpty) {
          allLinks.addAll(TextUtils.extractLinks(linkItem.text!));
        }
        
        // Extract from caption if it exists
        if (linkItem.caption != null && linkItem.caption!.isNotEmpty) {
          allLinks.addAll(TextUtils.extractLinks(linkItem.caption!));
        }
        
        if (allLinks.isNotEmpty) {
          _extractedLinksCache[linkItem.id.toString()] = allLinks;
        }
      }
    } catch (e) {
      debugPrint('Error fetching chat links: $e');
      _linksError = true;
      _linksFetchAttempted = false;
    } finally {
      if (mounted) {
        setState(() { _isLoadingLinks = false; });
      }
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

  Future<void> _fetchChatFiles() async {
    if (_chatId == null) return;
    if (_filesFetchAttempted) return;
    _filesFetchAttempted = true;
    setState(() {
      _isLoadingFiles = true;
      _filesError = false;
    });
    try {
      final list = await ChatApiService().getChatFiles(_chatId!);
      _fileItems = (list ?? []).where((m) {
        final t = m.type.toUpperCase();
        return t == 'DOCUMENT' || t == 'AUDIO' || t == 'VOICE';
      }).toList();
    } catch (e) {
      debugPrint('Error fetching chat files: $e');
      _filesError = true;
      _filesFetchAttempted = false;
    } finally {
      if (mounted) {
        setState(() { _isLoadingFiles = false; });
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
        return '${_mediaItems.length} media';
      case 1:
        return '${_fileItems.length} files';
      case 2:
        final linkCount = _extractedLinksCache.values.fold(0, (sum, links) => sum + links.length);
        return '$linkCount links';
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
          if (index == 1) { // Files tab
            _fetchChatFiles();
          } else if (index == 2) { // Links tab
            _fetchChatLinks();
          }
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
    if (_isLoadingFiles) {
      return _buildFilesLoadingSkeleton();
    }
    if (_filesError) {
      return _buildFilesError();
    }
    if (_fileItems.isEmpty) {
      return _buildEmptyFilesState();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: _fileItems.map(_buildDynamicFileItem).toList(),
      ),
    );
  }

  // Legacy static _buildFileItem removed (replaced by dynamic items)

  Widget _buildDynamicFileItem(MediaResponse media) {
    final type = media.type.toUpperCase();
    final fileId = media.fileId;
    final base = getEnv("API_BASE_URL") ?? '';
    final baseNormalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final url = '$baseNormalized/uploads/$fileId';
    final isAudio = type == 'AUDIO' || type == 'VOICE';
    final isDocument = type == 'DOCUMENT';
    final cachedPath = _cachedFileLocalPaths[fileId];
    final downloading = _downloadingFile[fileId] == true;
    final icon = isAudio
        ? Icons.audiotrack
        : _pickDocumentIcon(fileId);

    return GestureDetector(
      onTap: () async {
        if (isDocument) {
          if (cachedPath != null) {
            await OpenFilex.open(cachedPath);
          } else if (!downloading) {
            _downloadFile(fileId, url, isAudio: false, openAfter: true);
          }
        } else if (isAudio) {
          if (cachedPath != null) {
            _playOrPauseAudio(fileId, cachedPath);
          } else if (!downloading) {
            _downloadFile(fileId, url, isAudio: true, openAfter: true);
          }
        }
      },
      child: Container(
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
                color: isAudio ? Colors.blue.shade700 : Colors.grey.shade700,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _deriveFileName(fileId, type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE8E7EA),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fileMetaPlaceholder(media),
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (downloading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
              )
            else if (cachedPath == null)
              IconButton(
                icon: const Icon(Icons.download_rounded, color: Colors.white70, size: 20),
                onPressed: () => _downloadFile(fileId, url, isAudio: isAudio, openAfter: isAudio),
              )
            else if (isAudio)
              IconButton(
                icon: Icon(_isAudioPlayingId == fileId ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white70, size: 26),
                onPressed: () => _playOrPauseAudio(fileId, cachedPath),
              )
            else
              IconButton(
                icon: const Icon(Icons.open_in_new, color: Colors.white70, size: 20),
                onPressed: () => OpenFilex.open(cachedPath),
              ),
          ],
        ),
      ),
    );
  }

  String _deriveFileName(String fileId, String type) {
    // If backend stores original name elsewhere, adapt; for now use fileId
    return fileId;
  }

  String _fileMetaPlaceholder(MediaResponse media) {
    // Placeholder for size/date (needs backend support); show type for now
    return media.type.toLowerCase();
  }

  IconData _pickDocumentIcon(String fileId) {
    final lower = fileId.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.zip') || lower.endsWith('.rar')) return Icons.folder_zip;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart;
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return Icons.insert_drive_file; // generic (these should be media?)
    if (lower.endsWith('.mp3') || lower.endsWith('.m4a')) return Icons.audio_file;
    return Icons.insert_drive_file;
  }

  Widget _buildFilesLoadingSkeleton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: List.generate(6, (i) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF1C212C),
            borderRadius: BorderRadius.circular(8),
          ),
        )),
      ),
    );
  }

  Widget _buildFilesError() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
        const SizedBox(height: 12),
        const Text('Failed to load files', style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 14)),
        TextButton(onPressed: _fetchChatFiles, child: const Text('Retry'))
      ],
    );
  }

  Widget _buildEmptyFilesState() {
    return Column(
      children: const [
        SizedBox(height: 40),
        Icon(Icons.insert_drive_file, color: Colors.grey, size: 40),
        SizedBox(height: 12),
        Text('No files shared yet', style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 14)),
      ],
    );
  }

  Future<void> _downloadFile(String fileId, String url, {required bool isAudio, bool openAfter = false}) async {
    if (_downloadingFile[fileId] == true) return;
    setState(() { _downloadingFile[fileId] = true; });
    try {
      final tempDir = await getTemporaryDirectory();
      final localPath = '${tempDir.path}/$fileId';
      final dio = Dio();
      await dio.download(url, localPath);
      setState(() { _cachedFileLocalPaths[fileId] = localPath; });
      if (openAfter) {
        if (isAudio) {
          _playOrPauseAudio(fileId, localPath, forcePlay: true);
        } else {
          await OpenFilex.open(localPath);
        }
      }
    } catch (e) {
      debugPrint('Download failed for $fileId: $e');
    } finally {
      if (mounted) setState(() { _downloadingFile[fileId] = false; });
    }
  }

  // Simple audio play/pause using a shared AudioPlayer (reuse chat logic later if needed)
  AudioPlayer? _filesAudioPlayer;
  String? _isAudioPlayingId;

  Future<void> _playOrPauseAudio(String fileId, String path, {bool forcePlay = false}) async {
    _filesAudioPlayer ??= AudioPlayer();
    if (!forcePlay && _isAudioPlayingId == fileId) {
      await _filesAudioPlayer!.pause();
      setState(() { _isAudioPlayingId = null; });
      return;
    }
    try {
      await _filesAudioPlayer!.stop();
      await _filesAudioPlayer!.play(DeviceFileSource(path));
      setState(() { _isAudioPlayingId = fileId; });
      _filesAudioPlayer!.onPlayerComplete.listen((event) {
        if (mounted) setState(() { _isAudioPlayingId = null; });
      });
    } catch (e) {
      debugPrint('Audio play error for $fileId: $e');
    }
  }

  Widget _buildLinksContent() {
    if (_isLoadingLinks) {
      return _buildLinksLoadingSkeleton();
    }
    if (_linksError) {
      return _buildLinksError();
    }
    if (_linkItems.isEmpty) {
      return _buildEmptyLinksState();
    }

    // Group links by month for display
    Map<String, List<MapEntry<LinkResponse, List<String>>>> groupedLinks = {};
    
    // Sort links by creation date (newest first)
    final sortedLinkItems = List<LinkResponse>.from(_linkItems)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    for (final linkItem in sortedLinkItems) {
      final extractedLinks = _extractedLinksCache[linkItem.id.toString()] ?? [];
      if (extractedLinks.isNotEmpty) {
        final monthKey = _getMonthKey(linkItem.createdAt);
        groupedLinks.putIfAbsent(monthKey, () => []);
        groupedLinks[monthKey]!.add(MapEntry(linkItem, extractedLinks));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          for (final monthEntry in groupedLinks.entries.toList()..sort((a, b) => _compareMonths(b.key, a.key))) ...[
            _buildMonthSeparator(monthEntry.key),
            for (final linkEntry in monthEntry.value)
              for (final url in linkEntry.value)
                _buildDynamicLinkItem(linkEntry.key, url),
          ],
        ],
      ),
    );
  }

  int _compareMonths(String month1, String month2) {
    // Parse month strings like "October 2025" and compare dates
    try {
      final parts1 = month1.split(' ');
      final parts2 = month2.split(' ');
      
      if (parts1.length != 2 || parts2.length != 2) return 0;
      
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      
      final monthIndex1 = months.indexOf(parts1[0]);
      final monthIndex2 = months.indexOf(parts2[0]);
      final year1 = int.tryParse(parts1[1]) ?? 0;
      final year2 = int.tryParse(parts2[1]) ?? 0;
      
      if (year1 != year2) return year1.compareTo(year2);
      return monthIndex1.compareTo(monthIndex2);
    } catch (e) {
      return 0;
    }
  }

  String _getMonthKey(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Widget _buildDynamicLinkItem(LinkResponse linkMessage, String url) {
    // Try to get a title from the message text or use the domain
    String title = _extractTitle(linkMessage, url);
    String description = _extractDescription(linkMessage, url);
    
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
              Icons.link,
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
                if (description.isNotEmpty) ...[
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
                ],
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _launchUrl(url),
                  child: Text(
                    url,
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
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

  String _extractTitle(LinkResponse linkMessage, String url) {
    // If there's text, use the first part as title
    if (linkMessage.text != null && linkMessage.text!.isNotEmpty) {
      final words = linkMessage.text!.split(' ');
      if (words.length > 1) {
        return words.take(3).join(' ') + (words.length > 3 ? '...' : '');
      }
    }
    
    // Fallback to domain name
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      return uri.host.replaceFirst('www.', '');
    } catch (e) {
      return url;
    }
  }

  String _extractDescription(LinkResponse linkMessage, String url) {
    // Use caption if available
    if (linkMessage.caption != null && linkMessage.caption!.isNotEmpty) {
      return linkMessage.caption!;
    }
    
    // Or use text if it's longer than just the URL
    if (linkMessage.text != null && 
        linkMessage.text!.isNotEmpty && 
        linkMessage.text! != url &&
        linkMessage.text!.length > url.length + 10) {
      return linkMessage.text!;
    }
    
    return '';
  }

  Future<void> _launchUrl(String url) async {
    try {
      // Ensure URL has proper protocol
      String fullUrl = url;
      if (url.startsWith('www.')) {
        fullUrl = 'https://$url';
      } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
        fullUrl = 'https://$url';
      }
      
      final Uri uri = Uri.parse(fullUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  Widget _buildLinksLoadingSkeleton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: List.generate(5, (i) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF1C212C),
            borderRadius: BorderRadius.circular(8),
          ),
        )),
      ),
    );
  }

  Widget _buildLinksError() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
        const SizedBox(height: 12),
        const Text('Failed to load links', style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 14)),
        TextButton(onPressed: _fetchChatLinks, child: const Text('Retry'))
      ],
    );
  }

  Widget _buildEmptyLinksState() {
    return Column(
      children: const [
        SizedBox(height: 40),
        Icon(Icons.link_off, color: Colors.grey, size: 40),
        SizedBox(height: 12),
        Text('No links shared yet', style: TextStyle(color: Color(0xFFE8E7EA), fontSize: 14)),
      ],
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
