import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../legacy/compatibility.dart';
import '../../services/marriage_success_service.dart';
import '../../services/success_story_service.dart';
import '../../services/profile_deletion_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/celebration_effects.dart';
import '../auth/auth_selection_screen.dart';

/// Deletion reason category
enum _DeletionType {
  marriageFixed,  // immediate delete
  other,          // 7-day grace period
}

class _Reason {
  final String label;
  final IconData icon;
  final _DeletionType type;
  final String? subtitle;

  const _Reason(this.label, this.icon, this.type, {this.subtitle});
}

const _reasons = [
  _Reason(
    'Marriage Fixed 💍',
    Icons.favorite,
    _DeletionType.marriageFixed,
    subtitle: 'Congratulations! Your profile will be removed immediately.',
  ),
  _Reason(
    'Found a match outside this app',
    Icons.people_alt,
    _DeletionType.other,
    subtitle: '7-day grace period — you can restore anytime.',
  ),
  _Reason(
    'Not satisfied with the matches',
    Icons.sentiment_dissatisfied,
    _DeletionType.other,
    subtitle: '7-day grace period — you can restore anytime.',
  ),
  _Reason(
    'Taking a break from Vivaaha Vedika',
    Icons.pause_circle_outline,
    _DeletionType.other,
    subtitle: '7-day grace period — you can restore anytime.',
  ),
  _Reason(
    'Privacy concerns',
    Icons.lock_outline,
    _DeletionType.other,
    subtitle: '7-day grace period — you can restore anytime.',
  ),
  _Reason(
    'Too many unwanted contacts',
    Icons.block,
    _DeletionType.other,
    subtitle: '7-day grace period — you can restore anytime.',
  ),
  _Reason(
    'Technical issues with the app',
    Icons.settings_outlined,
    _DeletionType.other,
    subtitle: '7-day grace period — you can restore anytime.',
  ),
  _Reason(
    'Other reason',
    Icons.more_horiz,
    _DeletionType.other,
    subtitle: '7-day grace period — you can restore anytime.',
  ),
];

/// Full delete-profile flow:
///  • Shows all deletion reasons
///  • "Marriage fixed" → immediate delete + marriage survey
///  • All other reasons → 7-day grace period; user can restore within that window
class DeleteProfileScreen extends StatefulWidget {
  const DeleteProfileScreen({super.key});

  @override
  State<DeleteProfileScreen> createState() => _DeleteProfileScreenState();
}

class _DeleteProfileScreenState extends State<DeleteProfileScreen> {
  int? _selectedIndex;
  bool _loading = false;
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  _Reason? get _selected =>
      _selectedIndex != null ? _reasons[_selectedIndex!] : null;

  bool get _isMarriageFixed =>
      _selected?.type == _DeletionType.marriageFixed;

  Future<void> _proceed() async {
    if (_selected == null) return;

    if (_isMarriageFixed) {
      // Ask about match source before deleting
      await _showMarriageSurvey();
    } else {
      await _showGracePeriodConfirm();
    }
  }

  // ── Marriage fixed flow ──────────────────────────────────────────
  Future<void> _showMarriageSurvey() async {
    final authService = context.read<AuthService>();
    final myProfileId = authService.currentUser?.profileId ?? '';

    final survey = await showDialog<MarriageSurveyResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _MarriageSurveyDialog(myProfileId: myProfileId),
    );

    if (!mounted) return;
    if (survey == null) return; // user cancelled

    setState(() => _loading = true);
    try {
      final uid = authService.currentUser?.id;
      if (uid == null || uid.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final matchSource = survey.matchSource;
      String? imageUrl;
      if (survey.hasPhoto) {
        imageUrl = await SuccessStoryService.uploadSuccessPhoto(
          callerUserDocId: uid,
          photoLocalPath: survey.photoLocalPath,
          photoBytes: survey.photoBytes,
          photoFileName: survey.photoFileName,
        );
        if (imageUrl == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Success photo could not be uploaded; story will be saved without it.',
              ),
              backgroundColor: AppTheme.primaryOrange,
            ),
          );
        }
      }
      final isAppMatch = SuccessStoryService.isAppMatchSource(matchSource);
      if (isAppMatch) {
        final storyOk = await SuccessStoryService.recordAppMarriageIfNeeded(
          matchSource: matchSource,
          callerUserDocId: uid,
          imageUrl: imageUrl,
        );
        if (!storyOk) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not save success story. Check partner Profile ID and try again.',
                ),
                backgroundColor: AppTheme.kumkumRed,
              ),
            );
          }
          return;
        }
      }
      final result = await MarriageSuccessService.complete(
        matchSource: matchSource,
        requesterId: uid,
        skipStoryCreation: isAppMatch,
      );
      if (result['success'] != true) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                (result['error'] as String?) ??
                    'Could not remove profile. Check partner Profile ID or try again.',
              ),
              backgroundColor: AppTheme.kumkumRed,
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _loading = false);
      await CelebrationEffects.showMarriageCongratulations(context);
      if (!mounted) return;
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthSelectionScreen()),
          (r) => false,
        );
      }
      unawaited(authService.logout());
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.kumkumRed),
        );
      }
    }
  }

  // ── 7-day grace period flow ──────────────────────────────────────
  Future<void> _showGracePeriodConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _GracePeriodConfirmDialog(reason: _selected!.label),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _loading = true);
    try {
      final authService = context.read<AuthService>();
      final uid = authService.currentUser?.id;
      if (uid == null || uid.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final scheduled = await authService.initiateProfileDeletion(_selected!.label);
      if (!scheduled) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not schedule deletion. Please try again.'),
              backgroundColor: AppTheme.kumkumRed,
            ),
          );
        }
        return;
      }
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthSelectionScreen()),
          (r) => false,
        );
        unawaited(authService.logout());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile scheduled for deletion in ${ProfileDeletionService.gracePeriodDays} days. Login anytime to restore it.',
            ),
            backgroundColor: AppTheme.primaryOrange,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.kumkumRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(title: 'Delete Profile', showLogo: false),
      body: Stack(
        children: [
          Column(
            children: [
              // Header info
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.kumkumRed.withAlpha(15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.kumkumRed.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 22, color: AppTheme.kumkumRed),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Please select your reason. Some reasons allow a 7-day restore window.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.kumkumRed,
                            ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.1),

              // Reasons list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _reasons.length,
                  itemBuilder: (ctx, i) {
                    final r = _reasons[i];
                    final selected = _selectedIndex == i;
                    final isMarriage = r.type == _DeletionType.marriageFixed;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedIndex = i),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? (isMarriage
                                  ? AppTheme.sacredGreen.withAlpha(20)
                                  : AppTheme.primaryOrange.withAlpha(18))
                              : AC.card(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? (isMarriage ? AppTheme.sacredGreen : AppTheme.primaryOrange)
                                : (AC.border(context)),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isMarriage
                                    ? AppTheme.sacredGreen.withAlpha(20)
                                    : AppTheme.kumkumRed.withAlpha(15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(r.icon,
                                  size: 20,
                                  color: isMarriage
                                      ? AppTheme.sacredGreen
                                      : AppTheme.kumkumRed),
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AC.text(context),
                                        ),
                                  ),
                                  if (r.subtitle != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      r.subtitle!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AC.textSub(context),
                                          ),
                                    ),
                                  ],
                                  // Badge
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isMarriage
                                          ? AppTheme.sacredGreen.withAlpha(25)
                                          : AC.surface(context),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isMarriage
                                          ? '✓ Immediate removal'
                                          : '⏱ 7-day restore window',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isMarriage
                                            ? AppTheme.sacredGreen
                                            : AppTheme.primaryOrange,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Radio<int>(
                              value: i,
                              // ignore: deprecated_member_use
                              groupValue: _selectedIndex,
                              // ignore: deprecated_member_use
                              onChanged: (v) => setState(() => _selectedIndex = v),
                              activeColor: isMarriage
                                  ? AppTheme.sacredGreen
                                  : AppTheme.primaryOrange,
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(delay: Duration(milliseconds: 40 * i)).slideX(begin: 0.05);
                  },
                ),
              ),

              // "Other reason" text field
              if (_selectedIndex != null &&
                  _reasons[_selectedIndex!].label == 'Other reason')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _otherController,
                    maxLines: 2,
                    style: TextStyle(color: AC.text(context)),
                    decoration: InputDecoration(
                      hintText: 'Please tell us your reason (optional)…',
                      hintStyle: TextStyle(color: AC.textMuted(context)),
                      filled: true,
                      fillColor: AC.surface(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AC.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AC.border(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppTheme.primaryOrange, width: 2),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ).animate().fadeIn(),

              // Proceed button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_selectedIndex != null && !_loading)
                        ? _proceed
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.kumkumRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _selectedIndex == null
                          ? 'Select a reason to continue'
                          : (_isMarriageFixed
                              ? '🎉 Confirm — Delete Immediately'
                              : 'Continue — Schedule Deletion'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.primaryOrange,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Marriage survey dialog ─────────────────────────────────────────
class _MarriageSurveyDialog extends StatefulWidget {
  final String myProfileId;
  const _MarriageSurveyDialog({required this.myProfileId});

  @override
  State<_MarriageSurveyDialog> createState() => _MarriageSurveyDialogState();
}

class _MarriageSurveyDialogState extends State<_MarriageSurveyDialog> {
  final _partnerController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  String? _selectedSource;
  String? _photoLocalPath;
  Uint8List? _photoBytes;
  String _photoFileName = 'success.jpg';
  bool _pickingPhoto = false;

  @override
  void dispose() {
    _partnerController.dispose();
    super.dispose();
  }

  Future<void> _pickSuccessPhoto() async {
    setState(() => _pickingPhoto = true);
    try {
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (result != null && result.files.single.path != null) {
          _photoLocalPath = result.files.single.path;
          _photoBytes = null;
          _photoFileName = result.files.single.name;
        }
      } else {
        final picked = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 85,
        );
        if (picked != null) {
          if (kIsWeb) {
            _photoBytes = await picked.readAsBytes();
            _photoLocalPath = null;
            _photoFileName = picked.name.isNotEmpty ? picked.name : 'success.jpg';
          } else {
            _photoLocalPath = picked.path;
            _photoBytes = null;
            _photoFileName = picked.name.isNotEmpty ? picked.name : 'success.jpg';
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not pick photo: $e'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _clearPhoto() {
    setState(() {
      _photoLocalPath = null;
      _photoBytes = null;
    });
  }

  bool get _hasPhoto =>
      (_photoLocalPath != null && _photoLocalPath!.isNotEmpty) ||
      (_photoBytes != null && _photoBytes!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Text('💍', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Text(
            'Congratulations!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AC.text(context),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wishing you a beautiful married life! 🌸\n\nWhere did you find your match?',
              style: TextStyle(fontSize: 15, color: AC.textSub(context)),
            ),
            const SizedBox(height: 16),
            _SourceOption(
              label: 'On Mana Vivaaha Vedika',
              icon: Icons.favorite,
              color: AppTheme.kumkumRed,
              selected: _selectedSource == 'mana_Vivaaha Vedika',
              onTap: () => setState(() => _selectedSource = 'mana_Vivaaha Vedika'),
            ),
            const SizedBox(height: 8),
            _SourceOption(
              label: 'Outside this app',
              icon: Icons.people_alt,
              color: AppTheme.primaryOrange,
              selected: _selectedSource == 'external',
              onTap: () => setState(() => _selectedSource = 'external'),
            ),
            if (_selectedSource == 'mana_Vivaaha Vedika') ...[
              const SizedBox(height: 14),
              TextField(
                controller: _partnerController,
                style: TextStyle(color: AC.text(context)),
                decoration: InputDecoration(
                  hintText: "Partner's Profile ID (e.g. MB12345)",
                  hintStyle: TextStyle(color: AC.textMuted(context)),
                  prefixIcon: Icon(Icons.person_search, color: AC.textSub(context)),
                  filled: true,
                  fillColor: AC.surface(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AC.border(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AC.border(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.primaryOrange, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your Profile ID: ${widget.myProfileId}',
                style: TextStyle(
                    fontSize: 12, color: AC.textSub(context)),
              ),
            ],
            if (_selectedSource != null) ...[
              const SizedBox(height: 16),
              Text(
                'Success photo (optional)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AC.text(context),
                ),
              ),
              const SizedBox(height: 8),
              if (_hasPhoto)
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _photoBytes != null
                          ? Image.memory(
                              _photoBytes!,
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(_photoLocalPath!),
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                    ),
                    IconButton(
                      onPressed: _clearPhoto,
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  onPressed: _pickingPhoto ? null : _pickSuccessPhoto,
                  icon: _pickingPhoto
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _pickingPhoto ? 'Opening gallery…' : 'Upload success photo',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryOrange,
                    side: const BorderSide(color: AppTheme.primaryOrange),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Shown on Success Stories after you confirm.',
                style: TextStyle(fontSize: 11, color: AC.textMuted(context)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedSource == null || _pickingPhoto
              ? null
              : () {
                  final source = _selectedSource!;
                  if (source == 'mana_Vivaaha Vedika' &&
                      _partnerController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Enter your partner's Profile ID (e.g. MB12345).",
                        ),
                        backgroundColor: AppTheme.kumkumRed,
                      ),
                    );
                    return;
                  }
                  String payload = source;
                  if (source == 'mana_Vivaaha Vedika') {
                    payload =
                        'mana_Vivaaha Vedika:${_partnerController.text.trim()}';
                  }
                  Navigator.pop(
                    context,
                    MarriageSurveyResult(
                      matchSource: payload,
                      photoLocalPath: _photoLocalPath,
                      photoBytes: _photoBytes,
                      photoFileName: _photoFileName,
                    ),
                  );
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.sacredGreen,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirm & Delete Profile'),
        ),
      ],
    );
  }
}

class _SourceOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SourceOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : AC.border(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: AC.text(context),
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── 7-day grace period confirm dialog ─────────────────────────────
class _GracePeriodConfirmDialog extends StatelessWidget {
  final String reason;
  const _GracePeriodConfirmDialog({required this.reason});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.timer_outlined, color: AC.textSub(context)),
          SizedBox(width: 8),
          Text(
            'Schedule Deletion',
            style: TextStyle(
              color: AC.text(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AC.surface(context),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AC.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, size: 18, color: AppTheme.primaryOrange),
                  SizedBox(width: 6),
                  Text(
                    '7-Day Grace Period',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  '• Your profile will be hidden immediately\n'
                  '• You have 7 days to change your mind\n'
                  '• Log back in anytime to restore your profile\n'
                  '• After 7 days, data is permanently removed',
                  style: TextStyle(fontSize: 13, color: AC.textSub(context)),
                ),
              ],
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Reason: "$reason"',
            style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AC.textSub(context)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.kumkumRed,
            foregroundColor: Colors.white,
          ),
          child: const Text('Yes, Schedule Deletion'),
        ),
      ],
    );
  }
}
