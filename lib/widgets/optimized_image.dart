import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Optimized image widget with caching and performance tracking
class OptimizedImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Duration fadeInDuration;
  final bool enableMemoryCache;
  final bool enableDiskCache;
  final int? memCacheWidth;
  final int? memCacheHeight;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 200),
    this.enableMemoryCache = true,
    this.enableDiskCache = true,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  State<OptimizedImage> createState() => _OptimizedImageState();
}

class _OptimizedImageState extends State<OptimizedImage> 
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: widget.fadeInDuration,
      
      // Optimized placeholder
      placeholder: (context, url) => widget.placeholder ?? _buildPlaceholder(),
      
      // Optimized error widget
      errorWidget: (context, url, error) => widget.errorWidget ?? _buildErrorWidget(),
      
      // Memory optimization
      memCacheWidth: widget.memCacheWidth ?? widget.width?.toInt(),
      memCacheHeight: widget.memCacheHeight ?? widget.height?.toInt(),
      
      // Disk cache settings
      maxWidthDiskCache: 1200,
      maxHeightDiskCache: 1200,
      
      // Cache control
      cacheKey: widget.imageUrl,
      
      // Progressive loading
      progressIndicatorBuilder: (context, url, downloadProgress) => 
        _buildProgressIndicator(downloadProgress),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: (widget.width ?? 100) * 0.3,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: (widget.width ?? 100) * 0.3,
              color: Colors.grey[400],
            ),
            if (widget.height != null && widget.height! > 50)
              const SizedBox(height: 8),
            if (widget.height != null && widget.height! > 50)
              Text(
                'Failed to load',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(DownloadProgress? progress) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: progress != null
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress.totalSize != null
                      ? progress.downloaded / (progress.totalSize ?? 1)
                      : null,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                ),
              )
            : SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Optimized profile image with circular shape and fallback
class OptimizedProfileImage extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String? name;
  final Widget? fallbackChild;
  final BuildContext? context; // Add context parameter

  const OptimizedProfileImage({
    super.key,
    this.imageUrl,
    this.size = 50,
    this.name,
    this.fallbackChild,
    this.context, // Add to constructor
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipOval(
        child: OptimizedImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: size.toInt(),
          memCacheHeight: size.toInt(),
          placeholder: _buildProfilePlaceholder(),
          errorWidget: _buildProfileError(),
        ),
      );
    }
    
    return _buildProfileFallback(context);
  }

  Widget _buildProfilePlaceholder() {
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        child: Center(
          child: Icon(
            Icons.person,
            size: size * 0.5,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileError() {
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        child: Center(
          child: Icon(
            Icons.person,
            size: size * 0.5,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileFallback(BuildContext context) {
    if (fallbackChild != null) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: fallbackChild,
        ),
      );
    }

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        child: Center(
          child: Text(
            name?.isNotEmpty == true 
                ? name!.substring(0, 1).toUpperCase()
                : '?',
            style: TextStyle(
              fontSize: size * 0.4,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
      ),
    );
  }
}
