import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  GothramConflictResult — returned by showGothramConflictSheet
// ─────────────────────────────────────────────────────────────────────────────

enum GothramConflictResult {
  /// Both gothrams differ — no conflict, proceed silently.
  noConflict,

  /// Same gothram detected — user chose to proceed anyway.
  proceedAnyway,

  /// Same gothram detected — user chose to cancel sending interest.
  cancelled,

  /// One or both gothrams are unknown/null/"Other" — skip check, proceed.
  unknown,
}

// ─────────────────────────────────────────────────────────────────────────────
//  checkGothramConflict
//
//  Call this before sending an interest. Returns a GothramConflictResult:
//    • noConflict  → proceed immediately, no sheet shown
//    • unknown     → proceed immediately, no sheet shown
//    • proceedAnyway / cancelled → sheet was shown, honour user's choice
// ─────────────────────────────────────────────────────────────────────────────

Future<GothramConflictResult> checkGothramConflict({
  required BuildContext context,
  required String? myGothram,
  required String? theirGothram,
  required String theirFirstName,
}) async {
  // Normalise
  final mine  = myGothram?.trim().toLowerCase() ?? '';
  final theirs = theirGothram?.trim().toLowerCase() ?? '';

  // Skip if either is missing or "other"
  if (mine.isEmpty || theirs.isEmpty || mine == 'other' || theirs == 'other') {
    return GothramConflictResult.unknown;
  }

  // No conflict
  if (mine != theirs) return GothramConflictResult.noConflict;

  // Same gothram — show the warning sheet
  if (!context.mounted) return GothramConflictResult.cancelled;

  final result = await showModalBottomSheet<GothramConflictResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GothramConflictSheet(
      gothram: myGothram!,
      theirFirstName: theirFirstName,
    ),
  );

  return result ?? GothramConflictResult.cancelled;
}

// ─────────────────────────────────────────────────────────────────────────────
//  _GothramConflictSheet  (private — use checkGothramConflict() above)
// ─────────────────────────────────────────────────────────────────────────────

class _GothramConflictSheet extends StatelessWidget {
  final String gothram;
  final String theirFirstName;

  const _GothramConflictSheet({
    required this.gothram,
    required this.theirFirstName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(80),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Icon ─────────────────────────────────────────────────────────
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.primaryGold.withAlpha(80),
                width: 1.5,
              ),
            ),
            child: const Center(
              child: Text('🪔', style: TextStyle(fontSize: 34)),
            ),
          ),
          const SizedBox(height: 18),

          // ── Headline ─────────────────────────────────────────────────────
          const Text(
            'Same Gothram Detected',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // ── Gothram badge ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryGold.withAlpha(20),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppTheme.primaryGold.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_tree_outlined,
                    size: 15, color: AppTheme.primaryGold),
                const SizedBox(width: 6),
                Text(
                  '$gothram Gothram',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7A5200),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Explanation ───────────────────────────────────────────────────
          Text(
            'You and $theirFirstName belong to the same gothram — $gothram. '
            'In Brahmin tradition, same-gothram marriages are generally considered '
            'sagotra and many families observe this as a restriction.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF555566),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),

          // ── Advisory box ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryGold.withAlpha(70),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 17, color: AppTheme.primaryGold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'We recommend discussing this with your family before proceeding. '
                    'This is an advisory notice only — the final decision is entirely yours.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.55,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Buttons ───────────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, GothramConflictResult.cancelled),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: Colors.grey.withAlpha(100),
                  ),
                ),
                child: const Text(
                  'Go Back',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.pop(context, GothramConflictResult.proceedAnyway),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Send Anyway',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),

          // ── Fine print ────────────────────────────────────────────────────
          Text(
            'Your choice is private and not shared with $theirFirstName.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
