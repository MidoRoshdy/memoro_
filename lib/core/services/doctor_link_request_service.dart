import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/patient_public_profile.dart';
import 'auth_service.dart';

/// UI phase derived from the caregiver's `doctorsRequests` documents (streamed).
enum DoctorLinkUiPhase { connect, pending, linked }

/// Latest mapped state from [watchDoctorLinkUiState].
class DoctorLinkStreamState {
  const DoctorLinkStreamState({
    required this.phase,
    this.requestId,
    this.requestData,
  });

  final DoctorLinkUiPhase phase;
  final String? requestId;
  final Map<String, dynamic>? requestData;
}

/// Writes to [collectionName] with doctor fields plus patient snapshot fields.
abstract final class DoctorLinkRequestService {
  DoctorLinkRequestService._();

  static const String collectionName = 'doctorsRequests';

  static const String requestStatusPending = 'pending';
  static const String requestStatusAccepted = 'accepted';

  static CollectionReference<Map<String, dynamic>> _requests() {
    return FirebaseFirestore.instance.collection(collectionName);
  }

  static DocumentReference<Map<String, dynamic>> requestRef(String requestId) {
    return _requests().doc(requestId);
  }

  static DoctorLinkStreamState mapRequestDocsToUiState(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final pending = pickLatestWithStatus(docs, requestStatusPending);
    if (pending != null) {
      return DoctorLinkStreamState(
        phase: DoctorLinkUiPhase.pending,
        requestId: pending.id,
        requestData: pending.data(),
      );
    }
    final accepted = pickLatestWithStatus(docs, requestStatusAccepted);
    if (accepted != null) {
      return DoctorLinkStreamState(
        phase: DoctorLinkUiPhase.linked,
        requestId: accepted.id,
        requestData: accepted.data(),
      );
    }
    return const DoctorLinkStreamState(phase: DoctorLinkUiPhase.connect);
  }

  /// Emits whenever any of this doctor's requests change (pending / accepted / new doc).
  static Stream<DoctorLinkStreamState> watchDoctorLinkUiState(
    String doctorUid,
  ) {
    return _requests()
        .where('doctorId', isEqualTo: doctorUid)
        .snapshots()
        .map((snap) => mapRequestDocsToUiState(snap.docs));
  }

  static QueryDocumentSnapshot<Map<String, dynamic>>? pickLatestWithStatus(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String status,
  ) {
    final filtered = docs
        .where((d) => (d.data()['requestStatus'] as String?) == status)
        .toList();
    if (filtered.isEmpty) return null;
    filtered.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      if (ta is! Timestamp) return 1;
      if (tb is! Timestamp) return -1;
      return tb.compareTo(ta);
    });
    return filtered.first;
  }

  static QueryDocumentSnapshot<Map<String, dynamic>>? pickLatestForPatient(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String patientUid, {
    required String status,
  }) {
    final filtered = docs.where((d) {
      final data = d.data();
      return (data['patientUid'] as String?) == patientUid &&
          (data['requestStatus'] as String?) == status;
    }).toList();
    if (filtered.isEmpty) return null;
    filtered.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      if (ta is! Timestamp) return 1;
      if (tb is! Timestamp) return -1;
      return tb.compareTo(ta);
    });
    return filtered.first;
  }

  static Stream<QueryDocumentSnapshot<Map<String, dynamic>>?>
  watchLatestAcceptedForPatient(String patientUid) {
    return _requests()
        .where('patientUid', isEqualTo: patientUid)
        .snapshots()
        .map((snap) {
      return pickLatestForPatient(
        snap.docs,
        patientUid,
        status: requestStatusAccepted,
      );
    });
  }

  /// Pending request for this doctor + patient pair, if any.
  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  findPendingForDoctorAndPatient(String doctorUid, String patientUid) async {
    final snap = await _requests()
        .where('doctorId', isEqualTo: doctorUid)
        .get();
    for (final d in snap.docs) {
      final m = d.data();
      if (m['patientUid'] == patientUid &&
          m['requestStatus'] == requestStatusPending) {
        return d;
      }
    }
    return null;
  }

  /// Creates a pending request or returns the existing pending doc id for the pair.
  static Future<String> ensurePendingRequest({
    required PatientPublicProfile patient,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'no-current-user',
        message: 'Not signed in',
      );
    }

    final uid = user.uid;
    final existing = await findPendingForDoctorAndPatient(uid, patient.uid);
    if (existing != null) {
      return existing.id;
    }

    Map<String, dynamic>? cg;
    try {
      final snap = await AuthService.caregiverProfileRef(uid).get();
      cg = snap.data();
    } on FirebaseException {
      cg = null;
    }

    final doctorName = (cg?['name'] as String?)?.trim().isNotEmpty == true
        ? (cg!['name'] as String).trim()
        : (user.displayName?.trim() ?? '');
    final doctorPhone = (cg?['phone'] as String?)?.trim() ?? '';
    final doctorGender = (cg?['gender'] as String?)?.trim() ?? '';
    final doctorImageUrl =
        (cg?['imageUrl'] as String?)?.trim().isNotEmpty == true
        ? (cg!['imageUrl'] as String).trim()
        : (user.photoURL ?? '');

    final patientName = patient.name.trim();
    final patientImageUrl = patient.imageUrl.trim();

    final ref = await _requests().add(<String, dynamic>{
      'doctorId': uid,
      'doctorName': doctorName,
      'doctorPhone': doctorPhone,
      'doctorImageUrl': doctorImageUrl,
      'doctorGender': doctorGender,
      'patientUid': patient.uid,
      'patientId': patient.patientId.trim(),
      'patientName': patientName,
      'patientImageUrl': patientImageUrl,
      'patientAge': patient.age,
      'patientPhone': patient.phone.trim(),
      'requestStatus': requestStatusPending,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Resolves the linked doctor/caregiver phone for a patient.
  static Future<String> resolveLinkedDoctorPhone(String patientUid) async {
    final uid = patientUid.trim();
    if (uid.isEmpty) return '';

    final linked = await watchLatestAcceptedForPatient(uid).first;
    final data = linked?.data();
    if (data == null) return '';

    var doctorPhone = (data['doctorPhone'] as String?)?.trim() ?? '';
    if (doctorPhone.isNotEmpty) return doctorPhone;

    var doctorUid =
        (data['doctorId'] as String?)?.trim() ??
        (data['doctorUid'] as String?)?.trim() ??
        '';
    if (doctorUid.isEmpty) {
      final pairId = (data['pairId'] as String?)?.trim() ?? '';
      if (pairId.contains('_')) {
        final parts = pairId.split('_');
        doctorUid = parts.firstWhere(
          (part) => part.trim().isNotEmpty && part.trim() != uid,
          orElse: () => '',
        );
      }
    }
    if (doctorUid.isEmpty) return '';

    try {
      final caregiverSnap = await AuthService.caregiverProfileRef(doctorUid).get();
      return (caregiverSnap.data()?['phone'] as String?)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Resolves a patient's phone from profile documents and link snapshots.
  static Future<String> resolvePatientPhone({
    required String patientUid,
    Map<String, dynamic>? linkData,
    String fallbackPhone = '',
  }) async {
    final uid = patientUid.trim();
    final fromFallback = fallbackPhone.trim();
    if (fromFallback.isNotEmpty) return fromFallback;

    final fromLink = (linkData?['patientPhone'] as String?)?.trim() ?? '';
    if (fromLink.isNotEmpty) return fromLink;

    if (uid.isEmpty) return '';

    try {
      final snap = await AuthService.patientProfileRef(uid).get();
      final phone = (snap.data()?['phone'] as String?)?.trim() ?? '';
      if (phone.isNotEmpty) return phone;
    } catch (_) {}

    try {
      final legacy = await AuthService.legacyPerUserPatientRef(uid).get();
      final phone = (legacy.data()?['phone'] as String?)?.trim() ?? '';
      if (phone.isNotEmpty) return phone;
    } catch (_) {}

    return '';
  }
}
