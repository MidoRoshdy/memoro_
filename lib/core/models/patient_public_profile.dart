import 'package:cloud_firestore/cloud_firestore.dart';

class PatientPublicProfile {
  const PatientPublicProfile({
    required this.uid,
    required this.patientId,
    required this.name,
    required this.email,
    required this.phone,
    required this.gender,
    required this.imageUrl,
    this.age,
  });

  final String uid;
  final String patientId;
  final String name;
  final String email;
  final String phone;
  final String gender;
  final String imageUrl;
  final int? age;

  factory PatientPublicProfile.fromFirestore(
    String documentId,
    Map<String, dynamic> data,
  ) {
    int? age;
    final rawAge = data['age'];
    if (rawAge is int) {
      age = rawAge;
    } else if (rawAge is num) {
      age = rawAge.toInt();
    }

    return PatientPublicProfile(
      uid: (data['uid'] as String?)?.trim() ?? documentId,
      patientId: (data['patientId'] as String?)?.trim() ?? '',
      name: (data['name'] as String?)?.trim() ?? '',
      email: (data['email'] as String?)?.trim() ?? '',
      phone: (data['phone'] as String?)?.trim() ?? '',
      gender: (data['gender'] as String?)?.trim() ?? '',
      imageUrl: (data['imageUrl'] as String?)?.trim() ?? '',
      age: age,
    );
  }

  static PatientPublicProfile? fromDocumentSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data();
    if (data == null) return null;
    return PatientPublicProfile.fromFirestore(snap.id, data);
  }

  /// Builds a profile from a `doctorsRequests` document (patient* snapshot fields).
  factory PatientPublicProfile.fromDoctorLinkRequest(Map<String, dynamic> data) {
    int? age;
    final rawAge = data['patientAge'];
    if (rawAge is int) {
      age = rawAge;
    } else if (rawAge is num) {
      age = rawAge.toInt();
    }

    return PatientPublicProfile(
      uid: (data['patientUid'] as String?)?.trim() ?? '',
      patientId: (data['patientId'] as String?)?.trim() ?? '',
      name: (data['patientName'] as String?)?.trim() ?? '',
      email: '',
      phone: (data['patientPhone'] as String?)?.trim() ?? '',
      gender: '',
      imageUrl: (data['patientImageUrl'] as String?)?.trim() ?? '',
      age: age,
    );
  }
}

