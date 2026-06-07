import 'package:cloud_firestore/cloud_firestore.dart';

import 'doctor_link_request_service.dart';

abstract final class EmergencyRequestService {
  EmergencyRequestService._();

  static const String collectionName = 'emergencyRequests';
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String buildEmergencyRequestDocId(String uidA, String uidB) {
    final a = uidA.trim();
    final b = uidB.trim();
    if (a.isEmpty || b.isEmpty) {
      throw ArgumentError('Both user IDs are required.');
    }
    final sorted = <String>[a, b]..sort();
    return '${sorted.first}_${sorted.last}';
  }

  static DocumentReference<Map<String, dynamic>> requestRef(String requestDocId) {
    return _db.collection(collectionName).doc(requestDocId);
  }

  static Stream<Map<String, dynamic>?> watchRequest(String requestDocId) {
    return requestRef(requestDocId).snapshots().map((snap) => snap.data());
  }

  static Future<String> resolvePatientPhone({
    Map<String, dynamic>? emergencyData,
    required String patientUid,
    Map<String, dynamic>? linkData,
    String fallbackPhone = '',
  }) async {
    final fromEmergency =
        (emergencyData?['patientPhone'] as String?)?.trim() ?? '';
    if (fromEmergency.isNotEmpty) return fromEmergency;

    return DoctorLinkRequestService.resolvePatientPhone(
      patientUid: patientUid,
      linkData: linkData,
      fallbackPhone: fallbackPhone,
    );
  }
}
