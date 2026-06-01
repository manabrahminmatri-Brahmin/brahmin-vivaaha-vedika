// FirestoreRepository — Result-based CRUD helpers and identity sync.
//
// Many features still call FirebaseFirestore directly (see `firestore_users_access_map.dart`);
// goal is to route new work here or domain repositories, not to imply this is the sole caller.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'contract.dart';
import 'result.dart';
import 'app_identity.dart';
import '../utils/profile_field_mapping.dart';

/// FirestoreRepository - Base repository for all Firestore operations
class FirestoreRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 15);

  // ==================== IDENTITY ====================
  
  /// Get current user ID (userDocId) - THE ONLY ID for Firestore operations
  static String get currentUserId {
    final id = IdentityProvider.userDocId;
    if (id.isEmpty) {
      throw StateError('No user identity - call IdentityProvider.load() first');
    }
    return id;
  }

  /// Ensure auth_uid is synced (call before writes if needed)
  static Future<Result<void>> syncAuthUid(String userDocId) async {
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) {
        return Result.error(
          ErrorCodes.unauthenticated,
          'Not authenticated',
        );
      }

      await _db.collection(Collections.users).doc(userDocId).set({
        Fields.authUid: authUid,
        Fields.updatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(_timeout);

      return Result.success(null, message: 'Auth UID synced');
    } on FirebaseException catch (e) {
      return _handleFirebaseError(e);
    } catch (e) {
      return Result.error(ErrorCodes.unknown, e.toString(), rawError: e);
    }
  }

  // ==================== READ OPERATIONS ====================

  /// Safe get document
  static Future<Result<Map<String, dynamic>?>> getDocument(
    String collection,
    String docId,
  ) async {
    try {
      final doc = await _db
          .collection(collection)
          .doc(docId)
          .get()
          .timeout(_timeout);

      if (!doc.exists) {
        return Result.success(null);
      }

      final raw = Map<String, dynamic>.from(doc.data() ?? const {});
      return Result.success(_normalizeDocumentMap({'id': doc.id, ...raw}));
    } on FirebaseException catch (e) {
      return _handleFirebaseError(e);
    } catch (e) {
      return Result.error(ErrorCodes.unknown, e.toString(), rawError: e);
    }
  }

  /// Safe query with automatic pagination support
  static Future<Result<List<Map<String, dynamic>>>> query(
    String collection, {
    List<QueryCondition> conditions = const [],
    String? orderBy,
    bool descending = true,
    int? limit,
  }) async {
    try {
      Query query = _db.collection(collection);

      for (final condition in conditions) {
        query = condition.apply(query);
      }

      if (orderBy != null) {
        query = query.orderBy(orderBy, descending: descending);
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      final snapshot = await query.get().timeout(_timeout);

      return Result.success(snapshot.docs.map((d) {
        final raw = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
        return _normalizeDocumentMap({'id': d.id, ...raw});
      }).toList());
    } on FirebaseException catch (e) {
      return _handleFirebaseError(e);
    } catch (e) {
      return Result.error(ErrorCodes.unknown, e.toString(), rawError: e);
    }
  }

  // ==================== WRITE OPERATIONS ====================

  /// Safe set document
  static Future<Result<void>> setDocument(
    String collection,
    String docId,
    Map<String, dynamic> data, {
    bool merge = true,
  }) async {
    try {
      // Always add timestamps
      data[Fields.updatedAt] = FieldValue.serverTimestamp();
      data[Fields.schemaVersion] = 1;
      if (!merge) {
        data[Fields.createdAt] = FieldValue.serverTimestamp();
      }

      await _db
          .collection(collection)
          .doc(docId)
          .set(data, SetOptions(merge: merge))
          .timeout(_timeout);

      return Result.success(null, message: 'Document saved');
    } on FirebaseException catch (e) {
      return _handleFirebaseError(e);
    } catch (e) {
      return Result.error(ErrorCodes.unknown, e.toString(), rawError: e);
    }
  }

  /// Safe update document
  static Future<Result<void>> updateDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      data[Fields.updatedAt] = FieldValue.serverTimestamp();
      data[Fields.schemaVersion] = 1;

      await _db
          .collection(collection)
          .doc(docId)
          .update(data)
          .timeout(_timeout);

      return Result.success(null, message: 'Document updated');
    } on FirebaseException catch (e) {
      return _handleFirebaseError(e);
    } catch (e) {
      return Result.error(ErrorCodes.unknown, e.toString(), rawError: e);
    }
  }

  /// Safe delete document
  static Future<Result<void>> deleteDocument(
    String collection,
    String docId,
  ) async {
    try {
      await _db
          .collection(collection)
          .doc(docId)
          .delete()
          .timeout(_timeout);

      return Result.success(null, message: 'Document deleted');
    } on FirebaseException catch (e) {
      return _handleFirebaseError(e);
    } catch (e) {
      return Result.error(ErrorCodes.unknown, e.toString(), rawError: e);
    }
  }

  /// Safe batch write
  static Future<Result<void>> batchWrite(
    List<BatchOperation> operations,
  ) async {
    try {
      final batch = _db.batch();

      for (final op in operations) {
        op.apply(batch);
      }

      await batch.commit().timeout(_timeout);
      return Result.success(null, message: 'Batch committed');
    } on FirebaseException catch (e) {
      return _handleFirebaseError(e);
    } catch (e) {
      return Result.error(ErrorCodes.unknown, e.toString(), rawError: e);
    }
  }

  // ==================== STREAMS ====================

  /// Safe stream with error handling
  static Stream<Result<List<Map<String, dynamic>>>> streamQuery(
    String collection, {
    List<QueryCondition> conditions = const [],
    String? orderBy,
    bool descending = true,
    int? limit,
    /// Badge-critical listeners should see metadata transitions so cached
    /// snapshots cannot mask newer server values.
    bool includeMetadataChanges = true,
  }) {
    Query query = _db.collection(collection);

    for (final condition in conditions) {
      query = condition.apply(query);
    }

    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    return query
        .snapshots(includeMetadataChanges: includeMetadataChanges)
        .map((snapshot) {
      return Result.success(snapshot.docs.map((d) {
        final raw = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
        return _normalizeDocumentMap({'id': d.id, ...raw});
      }).toList());
    }).handleError((error) {
      return Result.error(
        ErrorCodes.permissionDenied,
        'Access denied',
        rawError: error,
      );
    });
  }

  // ==================== ERROR HANDLING ====================

  static Result<T> _handleFirebaseError<T>(FirebaseException e) {
    String errorCode;
    String message;

    switch (e.code) {
      case 'permission-denied':
        errorCode = ErrorCodes.permissionDenied;
        message = 'Action unavailable';
        break;
      case 'not-found':
        errorCode = ErrorCodes.notFound;
        message = 'Resource not found';
        break;
      case 'already-exists':
        errorCode = ErrorCodes.alreadyExists;
        message = 'Already exists';
        break;
      case 'unauthenticated':
        errorCode = ErrorCodes.unauthenticated;
        message = 'Please sign in';
        break;
      case 'unavailable':
        errorCode = ErrorCodes.unavailable;
        message = 'Service temporarily unavailable';
        break;
      case 'cancelled':
        errorCode = ErrorCodes.cancelled;
        message = 'Request cancelled';
        break;
      case 'deadline-exceeded':
        errorCode = ErrorCodes.deadlineExceeded;
        message = 'Request timed out';
        break;
      default:
        errorCode = e.code;
        message = e.message ?? 'Unknown error';
    }

    return Result.error(errorCode, message, rawError: e);
  }

  static Map<String, dynamic> _normalizeDocumentMap(Map<String, dynamic> raw) {
    final normalized = ProfileFieldMapping.convertProfileToSnakeCase(raw);
    if (normalized[Fields.schemaVersion] == null) {
      normalized[Fields.schemaVersion] = 1;
    }
    return normalized;
  }
}

/// Query condition helper
class QueryCondition {
  final Object field; // Supports String or FieldPath
  final dynamic isEqualTo;
  final dynamic isGreaterThan;
  final dynamic isLessThan;
  final List<dynamic>? whereIn;

  const QueryCondition.equal(this.field, this.isEqualTo)
      : isGreaterThan = null,
        isLessThan = null,
        whereIn = null;

  const QueryCondition.greaterThan(this.field, this.isGreaterThan)
      : isEqualTo = null,
        isLessThan = null,
        whereIn = null;

  const QueryCondition.lessThan(this.field, this.isLessThan)
      : isEqualTo = null,
        isGreaterThan = null,
        whereIn = null;

  const QueryCondition.whereIn(this.field, this.whereIn)
      : isEqualTo = null,
        isGreaterThan = null,
        isLessThan = null;

  Query apply(Query query) {
    if (isEqualTo != null) {
      return query.where(field, isEqualTo: isEqualTo);
    }
    if (isGreaterThan != null) {
      return query.where(field, isGreaterThan: isGreaterThan);
    }
    if (isLessThan != null) {
      return query.where(field, isLessThan: isLessThan);
    }
    if (whereIn != null) {
      return query.where(field, whereIn: whereIn);
    }
    return query;
  }
}

/// Batch operation helper
abstract class BatchOperation {
  void apply(WriteBatch batch);
}

class SetOperation extends BatchOperation {
  final String collection;
  final String docId;
  final Map<String, dynamic> data;
  final bool merge;

  SetOperation(this.collection, this.docId, this.data, {this.merge = true});

  @override
  void apply(WriteBatch batch) {
    final ref = FirebaseFirestore.instance.collection(collection).doc(docId);
    batch.set(ref, data, SetOptions(merge: merge));
  }
}

class UpdateOperation extends BatchOperation {
  final String collection;
  final String docId;
  final Map<String, dynamic> data;

  UpdateOperation(this.collection, this.docId, this.data);

  @override
  void apply(WriteBatch batch) {
    final ref = FirebaseFirestore.instance.collection(collection).doc(docId);
    batch.update(ref, data);
  }
}

class DeleteOperation extends BatchOperation {
  final String collection;
  final String docId;

  DeleteOperation(this.collection, this.docId);

  @override
  void apply(WriteBatch batch) {
    final ref = FirebaseFirestore.instance.collection(collection).doc(docId);
    batch.delete(ref);
  }
}
