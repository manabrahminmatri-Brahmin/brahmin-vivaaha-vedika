import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../services/success_story_service.dart';

class SuccessStoriesScreen extends StatefulWidget {
  const SuccessStoriesScreen({super.key});

  @override
  State<SuccessStoriesScreen> createState() => _SuccessStoriesScreenState();
}

class _SuccessStoriesScreenState extends State<SuccessStoriesScreen> {
  late Future<List<SuccessStory>> _storiesFuture;

  @override
  void initState() {
    super.initState();
    _storiesFuture = _loadSuccessStories();
  }

  Future<List<SuccessStory>> _loadSuccessStories() async {
    final docs = await SuccessStoryService.fetchPublishedStories();
    return docs.map((d) => SuccessStory.fromFirestore(d)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Success Stories',
        showLogo: false,
      ),
      body: FutureBuilder<List<SuccessStory>>(
        future: _storiesFuture,
        builder: (context, snapshot) {
          // Loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE85D04)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading success stories...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          // Error state
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading stories',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _storiesFuture = _loadSuccessStories();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE85D04),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          // Get data
          final stories = snapshot.data ?? [];

          // Empty state
          if (stories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_outline,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No success stories yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check back soon for inspiring success stories',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Show stories
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _storiesFuture = _loadSuccessStories();
              });
              await _storiesFuture;
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: stories.length,
              itemBuilder: (context, index) {
                final story = stories[index];
                return _buildStoryCard(context, story);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildStoryCard(BuildContext context, SuccessStory story) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: AC.card(context),
      elevation: Theme.of(context).brightness == Brightness.dark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: Theme.of(context).brightness == Brightness.dark
            ? BorderSide(color: AC.border(context), width: 0.5)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Story image (placeholder)
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: AC.surface2(context),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: story.imageUrl != null && story.imageUrl!.isNotEmpty
                ? Image.network(
                    story.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Icon(
                          Icons.image_not_supported,
                          size: 48,
                          color: AC.textMuted(context),
                        ),
                      );
                    },
                  )
                : Center(
                    child: Icon(
                      Icons.photo_camera_back,
                      size: 48,
                      color: AC.textMuted(context),
                    ),
                  ),
          ),
          // Story content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.title ?? 'Success Story',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (story.coupleNames != null && story.coupleNames!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      story.coupleNames!,
                      style: TextStyle(
                        fontSize: 14,
                        color: AC.textSub(context),
                      ),
                    ),
                  ),
                if (story.description != null && story.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      story.description!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (story.formattedDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Married: ${story.formattedDate}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AC.textMuted(context),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _showFullStory(context, story),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE85D04),
                  ),
                  child: const Text('Read More'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFullStory(BuildContext context, SuccessStory story) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AC.card(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.title ?? 'Success Story',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (story.coupleNames != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      story.coupleNames!,
                      style: TextStyle(
                        fontSize: 16,
                        color: AC.textSub(context),
                      ),
                    ),
                  ),
                if (story.description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      story.description!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE85D04),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SuccessStory {
  final String? id;
  final String? title;
  final String? description;
  final String? coupleNames;
  final String? imageUrl;
  final String? date;
  // Firestore fields from recordSuccessStory()
  final String? groomProfileId;
  final String? brideProfileId;
  final String? marriedAt;

  SuccessStory({
    this.id,
    this.title,
    this.description,
    this.coupleNames,
    this.imageUrl,
    this.date,
    this.groomProfileId,
    this.brideProfileId,
    this.marriedAt,
  });

  /// Parse from Firestore document (snake_case fields written by recordSuccessStory)
  factory SuccessStory.fromFirestore(Map<String, dynamic> json) => SuccessStory(
    id: json['id'] as String?,
    groomProfileId: json['groom_profile_id'] as String?,
    brideProfileId: json['bride_profile_id'] as String?,
    marriedAt: json['married_at'] as String?,
    title: json['title'] as String?,
    description: json['description'] as String?,
    coupleNames: json['couple_names'] as String? ??
        _buildCoupleNames(json['groom_profile_id'] as String?, json['bride_profile_id'] as String?),
    imageUrl: json['image_url'] as String? ?? json['imageUrl'] as String?,
    date: json['married_at'] as String? ?? json['date'] as String?,
  );

  String? get formattedDate {
    final raw = marriedAt ?? date;
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateFormat('d MMM yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw.length > 10 ? raw.substring(0, 10) : raw;
    }
  }

  static String? _buildCoupleNames(String? groomId, String? brideId) {
    if (groomId == null && brideId == null) return null;
    return [groomId, brideId].where((s) => s != null && s.isNotEmpty).join(' & ');
  }

  /// Legacy JSON parse (camelCase fields)
  factory SuccessStory.fromJson(Map<String, dynamic> json) => SuccessStory(
    id: json['id'] as String?,
    title: json['title'] as String?,
    description: json['description'] as String?,
    coupleNames: json['coupleNames'] as String?,
    imageUrl: json['imageUrl'] as String?,
    date: json['date'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'coupleNames': coupleNames,
    'imageUrl': imageUrl,
    'date': date,
  };
}
