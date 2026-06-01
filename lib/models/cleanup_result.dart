/// Data models for LikeService cleanup operations
library;

/// Result of corrupted data cleanup operation
class CleanupResult {
  final int totalDocuments;
  final int validDocuments;
  final int corruptedDocuments;
  final int deletedDocuments;
  final DateTime timestamp;

  CleanupResult({
    required this.totalDocuments,
    required this.validDocuments,
    required this.corruptedDocuments,
    required this.deletedDocuments,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'CleanupResult('
        'total: $totalDocuments, '
        'valid: $validDocuments, '
        'corrupted: $corruptedDocuments, '
        'deleted: $deletedDocuments, '
        'timestamp: $timestamp)';
  }

  /// Whether cleanup was successful (all corrupted documents deleted)
  bool get isSuccess => corruptedDocuments == deletedDocuments;

  /// Whether any corrupted documents were found
  bool get hasCorruption => corruptedDocuments > 0;
}

/// Report of data integrity validation for current user
class DataIntegrityReport {
  final bool isValid;
  final String? issue;
  final int corruptedDocuments;
  final int validDocuments;
  final List<String> affectedDocIds;
  final DateTime timestamp;

  DataIntegrityReport({
    required this.isValid,
    this.issue,
    required this.corruptedDocuments,
    required this.validDocuments,
    required this.affectedDocIds,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'DataIntegrityReport('
        'valid: $isValid, '
        'issue: $issue, '
        'corrupted: $corruptedDocuments, '
        'valid: $validDocuments, '
        'affectedDocs: ${affectedDocIds.length}, '
        'timestamp: $timestamp)';
  }

  /// Whether user's data is clean (no corruption)
  bool get isClean => isValid && corruptedDocuments == 0;

  /// Whether user has any corrupted data that needs cleanup
  bool get needsCleanup => corruptedDocuments > 0;
}
