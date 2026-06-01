import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../features/auth/auth_controller.dart';
import '../theme/app_theme.dart';
import '../core/backend/storage_service.dart';
import '../services/cloudinary_upload_service.dart';
import '../services/security/protected_image_cache_service.dart';
import '../utils/profile_photo_cache.dart';
import 'security/profile_photo_security_context.dart';
import 'security/protected_profile_photo.dart';

/// A beautiful profile photo picker widget with camera and gallery options
class ProfilePhotoPicker extends StatefulWidget {
  final String? currentImagePath;
  final ValueChanged<String?> onImageSelected;
  final double size;
  final bool isPrivate;
  final ValueChanged<bool>? onPrivacyChanged;

  const ProfilePhotoPicker({
    super.key,
    this.currentImagePath,
    required this.onImageSelected,
    this.size = 150,
    this.isPrivate = false,
    this.onPrivacyChanged,
  });

  @override
  State<ProfilePhotoPicker> createState() => _ProfilePhotoPickerState();
}

class _ProfilePhotoPickerState extends State<ProfilePhotoPicker> {
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;
  bool _isLoading = false;
  Timer? _pendingDeleteTimer;
  String? _pendingDeletedImagePath;

  @override
  void initState() {
    super.initState();
    _imagePath = widget.currentImagePath;
  }

  @override
  void didUpdateWidget(ProfilePhotoPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync imagePath when parent provides a new value (e.g. after upload completes)
    if (widget.currentImagePath != oldWidget.currentImagePath) {
      setState(() {
        _imagePath = widget.currentImagePath;
      });
    }
  }

  @override
  void dispose() {
    _pendingDeleteTimer?.cancel();
    _pendingDeleteTimer = null;
    _pendingDeletedImagePath = null;
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // 🔥 Windows/Desktop: Use file_picker for gallery, disable camera
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        if (source == ImageSource.camera) {
          if (mounted) {
            _showErrorDialog('Camera is not supported on desktop. Please use Gallery instead.');
          }
          return;
        }
        
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        
        if (result != null && result.files.single.path != null) {
          if (!mounted) return;
          setState(() => _isLoading = true);
          final filePath = result.files.single.path!;
          
          // Upload photo to server (same pattern as mobile)
          final authService = Provider.of<AuthController>(context, listen: false);
          final userId = authService.currentUser?.id;
          
          if (userId != null) {
            try {
              final photoUrl = await CloudinaryUploadService.uploadProfilePhoto(
                filePath,
                uid: userId,
              );
              final versionMs = DateTime.now().millisecondsSinceEpoch;
              final displayUrl =
                  bustProfilePhotoCache(photoUrl, versionMs: versionMs);
              await ProtectedImageCacheService.evictUrl(photoUrl);
              await ProtectedImageCacheService.evictUrl(displayUrl);
              await ProtectedImageCacheService.clearProtectedImageCache();
              if (!mounted) return;
              setState(() {
                _imagePath = displayUrl;
                _isLoading = false;
              });
              widget.onImageSelected(displayUrl);
            } catch (e) {
              debugPrint('📸 Desktop photo upload failed: $e');
              if (mounted) {
                setState(() => _isLoading = false);
                _showErrorDialog(
                  'Could not upload photo. Check your connection and try again.\n($e)',
                );
              }
            }
          } else {
            if (mounted) {
              setState(() => _isLoading = false);
              _showErrorDialog('Please sign in to upload a photo.');
            }
          }
        }
        return;
      }

      // Request appropriate permission first
      final hasPermission = await _requestPermission(source);
      if (!hasPermission) {
        if (mounted) {
          _showPermissionDeniedDialog(source);
        }
        return;
      }

      setState(() => _isLoading = true);

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );

      if (!mounted) return;

      if (pickedFile != null) {
        // Upload photo to server
        final authService = Provider.of<AuthController>(context, listen: false);
        final userId = authService.currentUser?.id;
        
        if (userId != null) {
          try {
            // Same pipeline as My Profile — Cloudinary unsigned preset (not Firebase Storage).
            final photoUrl = await CloudinaryUploadService.uploadProfilePhoto(
              pickedFile.path,
              uid: userId,
            );
            final versionMs = DateTime.now().millisecondsSinceEpoch;
            final displayUrl =
                bustProfilePhotoCache(photoUrl, versionMs: versionMs);
            await ProtectedImageCacheService.evictUrl(photoUrl);
            await ProtectedImageCacheService.evictUrl(displayUrl);
            await ProtectedImageCacheService.clearProtectedImageCache();

            setState(() {
              _imagePath = displayUrl;
              _isLoading = false;
            });

            widget.onImageSelected(displayUrl);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Photo uploaded successfully!'),
                    ],
                  ),
                  backgroundColor: AppTheme.sacredGreen,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            debugPrint('📸 ProfilePhotoPicker upload failed: $e');
            if (mounted) {
              setState(() => _isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Photo upload failed. ${e.toString().length > 120 ? "${e.toString().substring(0, 120)}…" : e}',
                  ),
                  backgroundColor: AppTheme.primaryOrange,
                ),
              );
            }
          }
        } else {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('User not logged in. Please login again.'),
                backgroundColor: AppTheme.primaryOrange,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image. Please try again.'),
            backgroundColor: AppTheme.primaryOrange,
          ),
        );
      }
    }
  }

  /// Request camera or gallery permission
  Future<bool> _requestPermission(ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      return status.isGranted;
    }

    // Gallery: Android 13+ uses READ_MEDIA_IMAGES (Permission.photos),
    // older Android uses READ_EXTERNAL_STORAGE (Permission.storage)
    if (Platform.isAndroid) {
      final photos = await Permission.photos.request();
      if (photos.isGranted || photos.isLimited) return true;
      // Fallback for older Android
      final storage = await Permission.storage.request();
      return storage.isGranted;
    } else {
      // iOS
      final photos = await Permission.photos.request();
      return photos.isGranted || photos.isLimited;
    }
  }

  /// Show dialog when permission is denied
  void _showPermissionDeniedDialog(ImageSource source) {
    final isCamera = source == ImageSource.camera;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isCamera ? Icons.camera_alt : Icons.photo_library,
              color: Color(0xFF757575),
            ),
            const SizedBox(width: 12),
            Text(isCamera ? 'Camera Access' : 'Photo Access'),
          ],
        ),
        content: Text(
          isCamera
              ? 'Camera permission is required to take photos. Please enable it in your device settings.'
              : 'Photo library permission is required to select photos. Please enable it in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Show generic error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[400]),
            const SizedBox(width: 12),
            const Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Delete photo from server storage
  Future<void> _deletePhoto(String photoUrl) async {
    try {
      final authService = Provider.of<AuthController>(context, listen: false);
      final docId = authService.currentUser?.id ?? '';
      if (docId.isEmpty) return;
      final lower = photoUrl.toLowerCase();
      if (lower.contains('cloudinary.com')) {
        await CloudinaryUploadService.deleteProfilePhoto(uid: docId);
        debugPrint('📸 Cloudinary profile slot cleared for: $docId');
        return;
      }
      await StorageService().deletePhoto(photoUrl, userId: docId);
      debugPrint('📸 Photo deleted from storage: $photoUrl');
    } catch (e) {
      debugPrint('📸 Failed to delete photo from server: $e');
    }
  }

  void _scheduleRemovePhotoWithUndo(String imagePathToDelete) {
    _pendingDeleteTimer?.cancel();
    _pendingDeleteTimer = null;
    _pendingDeletedImagePath = imagePathToDelete;
    unawaited(
      ProtectedImageCacheService.evictUrl(imagePathToDelete).then(
        (_) => ProtectedImageCacheService.clearProtectedImageCache(),
      ),
    );

    if (mounted) {
      setState(() => _imagePath = null);
    } else {
      _imagePath = null;
    }
    widget.onImageSelected(null);

    _pendingDeleteTimer = Timer(const Duration(seconds: 3), () async {
      final finalizedPath = _pendingDeletedImagePath;
      _pendingDeletedImagePath = null;
      _pendingDeleteTimer = null;
      if (finalizedPath != null && finalizedPath.startsWith('http')) {
        await _deletePhoto(finalizedPath);
      }
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Photo removed'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppTheme.primaryOrange,
            onPressed: () {
              _pendingDeleteTimer?.cancel();
              _pendingDeleteTimer = null;
              final restorePath = _pendingDeletedImagePath;
              _pendingDeletedImagePath = null;
              if (restorePath == null || !mounted) return;
              setState(() => _imagePath = restorePath);
              widget.onImageSelected(restorePath);
            },
          ),
        ),
      );
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AC.surface(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 24),
            
            Text(
              'Upload Profile Photo',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.primaryOrange,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how to add your photo',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            
            const SizedBox(height: 24),
            
            // Camera Option
            _buildOptionTile(
              icon: Icons.camera_alt_rounded,
              title: 'Take Photo',
              subtitle: 'Capture using camera',
              color: AC.textMuted(context),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ).animate().fadeIn().slideX(begin: -0.1),
            
            SizedBox(height: 12),
            
            // Gallery Option
            _buildOptionTile(
              icon: Icons.photo_library_rounded,
              title: 'Choose from Gallery',
              subtitle: 'Select from your photos',
              color: AC.textMuted(context),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),
            
            if (_imagePath != null) ...[
              SizedBox(height: 12),
              // Remove Photo Option
              _buildOptionTile(
                icon: Icons.delete_outline_rounded,
                title: 'Remove Photo',
                subtitle: 'Delete current photo',
                color: AC.textMuted(context),
                onTap: () {
                  // Store values before pop
                  final imagePathToDelete = _imagePath;
                  Navigator.pop(context);
                  
                  // Defer async operations to next frame to avoid deactivated widget issues
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (imagePathToDelete == null || !mounted) return;
                    _scheduleRemovePhotoWithUndo(imagePathToDelete);
                  });
                },
              ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),
            ],
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(30)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Color(0xFF757575)),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppTheme.textMedium,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AC.textMuted(context)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Photo Container
        GestureDetector(
          onTap: _showImageOptions,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              gradient: _imagePath == null ? AppTheme.goldGradient : null,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.primaryOrange,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: AC.border(context),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: _isLoading
                  ? _buildLoadingIndicator()
                  : _imagePath != null
                      ? _buildImage()
                      : _buildPlaceholder(),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Upload Button
        TextButton.icon(
          onPressed: _showImageOptions,
          icon: Icon(
            _imagePath != null ? Icons.edit : Icons.add_a_photo,
            size: 18,
          ),
          label: Text(
            _imagePath != null ? 'Change Photo' : 'Add Photo',
          ),
        ),
        
        // Privacy Toggle
        if (widget.onPrivacyChanged != null && _imagePath != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isPrivate 
                  ? AppTheme.primaryOrange.withAlpha(15)
                  : AppTheme.primaryOrange.withAlpha(15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isPrivate ? Icons.lock : Icons.public,
                  size: 16,
                  color: AC.textSub(context),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isPrivate ? 'Hidden (request to view)' : 'Public',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: widget.isPrivate ? AC.textSub(context) : AC.textSub(context),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => widget.onPrivacyChanged?.call(!widget.isPrivate),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AC.textMuted(context).withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 11,
                        color: AC.card(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      color: AC.surface(context),
      child: const Center(
        child: CircularProgressIndicator(
          color: AppTheme.primaryMaroon,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildImage() {
    // Debug photo visibility
    debugPrint('📸 ProfilePhotoPicker _buildImage: _imagePath=$_imagePath, isPrivate=${widget.isPrivate}');
    
    // Check if path is a URL (starts with http) or local file path
    final isUrl = _imagePath!.startsWith('http://') || _imagePath!.startsWith('https://');
    
    return Stack(
      clipBehavior: Clip.antiAlias,
      children: [
        Positioned.fill(
          child: isUrl
              ? CachedNetworkImage(
                  key: ValueKey(profilePhotoCacheKey(_imagePath!)),
                  imageUrl: _imagePath!,
                  cacheKey: profilePhotoCacheKey(_imagePath!),
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: AC.surface(context),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AC.textSub(context),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) {
                    debugPrint(
                      '❌ Network image error in ProfilePhotoPicker: $error',
                    );
                    return _buildPlaceholder();
                  },
                )
              : Image.file(
                  File(_imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint(
                      '❌ File image error in ProfilePhotoPicker: $error',
                    );
                    return _buildPlaceholder();
                  },
                ),
        ),
        if (widget.isPrivate)
          Positioned.fill(
            child: Container(
              color: AC.surface(context),
              alignment: Alignment.center,
              child: Icon(
                Icons.lock,
                color: AC.card(context),
                size: 32,
              ),
            ),
          ),
        // Edit overlay on hover/tap
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  AppTheme.primaryOrange.withAlpha(54),
                  Colors.transparent,
                ],
              ),
            ),
            child: Center(
              child: Icon(
                Icons.camera_alt,
                color: AC.textMuted(context),
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AC.surface(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_add_alt_1_rounded,
            size: widget.size * 0.35,
            color: AppTheme.primaryOrange.withAlpha(100),
          ),
          SizedBox(height: 8),
          Text(
            'Add Photo',
            style: TextStyle(
              fontSize: 12,
              color: AC.textMuted(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget to display profile photo with request option
class ProfilePhotoDisplay extends StatelessWidget {
  final String? imagePath;
  final bool isPrivate;
  final double size;
  final String? fallbackInitial;
  final VoidCallback? onRequestPhoto;
  final bool canRequestPhoto;
  final BuildContext context;

  const ProfilePhotoDisplay({
    super.key,
    required this.context,
    this.imagePath,
    this.isPrivate = false,
    this.size = 120,
    this.fallbackInitial,
    this.onRequestPhoto,
    this.canRequestPhoto = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: imagePath == null || isPrivate ? AppTheme.goldGradient : null,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.primaryOrange,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: AC.border(context),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext buildContext) {
    // Debug photo visibility
    if (imagePath != null) {
      debugPrint('📸 ProfilePhotoDisplay: imagePath=$imagePath, isPrivate=$isPrivate');
    }
    
    if (imagePath != null && imagePath!.isNotEmpty && !isPrivate) {
      // Show the actual image
      final policy = ProtectedProfilePhoto.resolvePolicy();
      return ProtectedProfilePhoto(
        imageUrl: imagePath!,
        viewerId: ProfilePhotoSecurityContext.viewerProfileId(buildContext),
        ownerId: '',
        sessionToken: ProfilePhotoSecurityContext.sessionToken(),
        fit: BoxFit.cover,
        size: size,
        restrictSensitiveViewing: policy.restrictSensitiveViewing,
        heavyBlurWhenRestricted: policy.heavyBlurWhenRestricted,
        placeholder: Container(
          color: AC.surface(context),
          child: Center(
            child: CircularProgressIndicator(
              color: AC.textSub(context),
            ),
          ),
        ),
        errorWidget: _buildFallback(),
      );
    } else if (isPrivate && canRequestPhoto) {
      // Photo is private - show request button
      return GestureDetector(
        onTap: onRequestPhoto,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AC.surface(context),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              Icons.lock,
              color: AC.card(context),
              size: 32,
            ),
          ),
        ),
      );
    } else {
      return _buildFallback();
    }
  }

  Widget _buildFallback() {
    return Container(
      color: AC.surface(context),
      child: Center(
        child: fallbackInitial != null
            ? Text(
                fallbackInitial!.toUpperCase(),
                style: TextStyle(
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryOrange,
                ),
              )
            : Icon(
                Icons.person,
                size: size * 0.4,
                color: AC.textMuted(context),
              ),
      ),
    );
  }
}
