import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/family_member.dart';
import '../models/family_memory.dart';

abstract final class FamilyService {
  FamilyService._();

  static const String collectionName = 'family';
  static const String membersSubcollection = 'members';
  static const String memoriesSubcollection = 'memories';
  static const String memberMemoriesSubcollection = 'memories';

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String buildFamilyDocId(String uidA, String uidB) {
    final a = uidA.trim();
    final b = uidB.trim();
    if (a.isEmpty || b.isEmpty) {
      throw ArgumentError('Both user IDs are required.');
    }
    final sorted = <String>[a, b]..sort();
    return '${sorted.first}_${sorted.last}';
  }

  static DocumentReference<Map<String, dynamic>> familyRef(String familyDocId) {
    return _db.collection(collectionName).doc(familyDocId);
  }

  static CollectionReference<Map<String, dynamic>> _membersRef(
    String familyDocId,
  ) {
    return familyRef(familyDocId).collection(membersSubcollection);
  }

  static CollectionReference<Map<String, dynamic>> _memoriesRef(
    String familyDocId,
  ) {
    return familyRef(familyDocId).collection(memoriesSubcollection);
  }

  static CollectionReference<Map<String, dynamic>> _memberMemoriesRef(
    String familyDocId,
    String memberId,
  ) {
    return _membersRef(
      familyDocId,
    ).doc(memberId.trim()).collection(memberMemoriesSubcollection);
  }

  static Future<void> ensureFamilyDocument({
    required String familyDocId,
    required String doctorUid,
    required String patientUid,
  }) async {
    final participants = <String>[doctorUid.trim(), patientUid.trim()]..sort();
    final ref = familyRef(familyDocId);
    final existing = await ref.get();
    if (existing.exists) {
      await ref.set(<String, dynamic>{
        'familyId': familyDocId,
        'doctorUid': doctorUid.trim(),
        'patientUid': patientUid.trim(),
        'participantIds': participants,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    await ref.set(<String, dynamic>{
      'familyId': familyDocId,
      'doctorUid': doctorUid.trim(),
      'patientUid': patientUid.trim(),
      'participantIds': participants,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<List<FamilyMember>> watchMembers(String familyDocId) {
    return _membersRef(familyDocId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => FamilyMember.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  static Stream<FamilyMember?> watchMember(
    String familyDocId,
    String memberId,
  ) {
    return _membersRef(familyDocId).doc(memberId.trim()).snapshots().map((
      snap,
    ) {
      final data = snap.data();
      if (data == null) return null;
      return FamilyMember.fromFirestore(snap.id, data);
    });
  }

  static Stream<String?> watchFavoriteMemberId(String familyDocId) {
    return familyRef(familyDocId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      final value = (data['favoriteMemberId'] as String?)?.trim() ?? '';
      return value.isEmpty ? null : value;
    });
  }

  static Stream<List<FamilyMemory>> watchRecentMemories(
    String familyDocId, {
    int limit = 6,
  }) {
    return _memoriesRef(familyDocId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => FamilyMemory.fromFirestore(d.id, d.data()))
              .where((m) => m.imageUrl.isNotEmpty)
              .toList(),
        );
  }

  static Stream<List<FamilyMemory>> watchFamilyMemories(
    String familyDocId, {
    int limit = 20,
    bool forPatient = false,
  }) {
    return _memoriesRef(familyDocId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => FamilyMemory.fromFirestore(d.id, d.data()))
              .where((m) => !forPatient || !m.hiddenForPatient)
              .where((m) => m.imageUrl.isNotEmpty)
              .toList(),
        );
  }

  static Stream<List<FamilyMemory>> watchProfileMemories(
    String familyDocId,
    String memberId, {
    bool forPatient = false,
  }) {
    return _memberMemoriesRef(familyDocId, memberId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => FamilyMemory.fromFirestore(d.id, d.data()))
              .where((m) => !forPatient || !m.hiddenForPatient)
              .where((m) => m.imageUrl.isNotEmpty)
              .toList(),
        );
  }

  static Future<void> addMember({
    required String familyDocId,
    required String doctorUid,
    required String patientUid,
    required String createdByUid,
    required String name,
    required String phone,
    required String relation,
    required bool isEmergencyContact,
    String imageUrl = '',
  }) async {
    await ensureFamilyDocument(
      familyDocId: familyDocId,
      doctorUid: doctorUid,
      patientUid: patientUid,
    );
    final memberRef = _membersRef(familyDocId).doc();
    await memberRef.set(<String, dynamic>{
      'memberId': memberRef.id,
      'name': name.trim(),
      'phone': phone.trim(),
      'relation': relation.trim(),
      'isEmergencyContact': isEmergencyContact,
      'imageUrl': imageUrl.trim(),
      'personalNote': '',
      'createdByUid': createdByUid.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await familyRef(familyDocId).set(<String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'membersCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  static Future<void> addMemory({
    required String familyDocId,
    required String doctorUid,
    required String patientUid,
    required String imageUrl,
    required String createdByUid,
    String caption = '',
  }) async {
    await ensureFamilyDocument(
      familyDocId: familyDocId,
      doctorUid: doctorUid,
      patientUid: patientUid,
    );
    final ref = _memoriesRef(familyDocId).doc();
    await ref.set(<String, dynamic>{
      'memoryId': ref.id,
      'familyDocId': familyDocId,
      'memberId': '',
      'memberName': '',
      'imageUrl': imageUrl.trim(),
      'caption': caption.trim(),
      'createdByUid': createdByUid.trim(),
      'hiddenForPatient': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await familyRef(familyDocId).set(<String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'memoriesCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  static Future<void> addMemoryToProfile({
    required String familyDocId,
    required String doctorUid,
    required String patientUid,
    required String memberId,
    required String imageUrl,
    required String createdByUid,
    String caption = '',
    String memberName = '',
  }) async {
    await ensureFamilyDocument(
      familyDocId: familyDocId,
      doctorUid: doctorUid,
      patientUid: patientUid,
    );
    final ref = _memberMemoriesRef(familyDocId, memberId).doc();
    await ref.set(<String, dynamic>{
      'memoryId': ref.id,
      'familyDocId': familyDocId,
      'memberId': memberId.trim(),
      'memberName': memberName.trim(),
      'imageUrl': imageUrl.trim(),
      'caption': caption.trim(),
      'createdByUid': createdByUid.trim(),
      'hiddenForPatient': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await familyRef(familyDocId).set(<String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'memoriesCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  static Future<void> updateMemberPersonalNote({
    required String familyDocId,
    required String memberId,
    required String personalNote,
  }) async {
    await _membersRef(familyDocId).doc(memberId.trim()).set(<String, dynamic>{
      'personalNote': personalNote.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await familyRef(familyDocId).set(<String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> setFavoriteMember({
    required String familyDocId,
    required String memberId,
  }) async {
    await familyRef(familyDocId).set(<String, dynamic>{
      'favoriteMemberId': memberId.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> setFamilyMemoryHiddenForPatient({
    required String familyDocId,
    required String memoryId,
    required bool hiddenForPatient,
  }) async {
    await _memoriesRef(familyDocId).doc(memoryId.trim()).set(<String, dynamic>{
      'hiddenForPatient': hiddenForPatient,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> deleteMember({
    required String familyDocId,
    required String memberId,
  }) async {
    final trimmedId = memberId.trim();
    final memberRef = _membersRef(familyDocId).doc(trimmedId);
    final snap = await memberRef.get();
    if (!snap.exists) return;

    final imageUrl = (snap.data()?['imageUrl'] as String?)?.trim() ?? '';

    final profileMemories = await _memberMemoriesRef(
      familyDocId,
      trimmedId,
    ).get();
    for (final doc in profileMemories.docs) {
      final memoryImageUrl = (doc.data()['imageUrl'] as String?)?.trim() ?? '';
      await doc.reference.delete();
      if (memoryImageUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(memoryImageUrl).delete();
        } catch (_) {
          // Best effort only.
        }
      }
    }

    await memberRef.delete();

    final familySnap = await familyRef(familyDocId).get();
    final favoriteId =
        (familySnap.data()?['favoriteMemberId'] as String?)?.trim() ?? '';
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'membersCount': FieldValue.increment(-1),
    };
    if (favoriteId == trimmedId) {
      updates['favoriteMemberId'] = FieldValue.delete();
    }
    await familyRef(familyDocId).set(updates, SetOptions(merge: true));

    if (imageUrl.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(imageUrl).delete();
      } catch (_) {
        // Best effort only.
      }
    }
  }

  static Future<void> deleteFamilyMemory({
    required String familyDocId,
    required String memoryId,
  }) async {
    final ref = _memoriesRef(familyDocId).doc(memoryId.trim());
    final snap = await ref.get();
    final imageUrl = (snap.data()?['imageUrl'] as String?)?.trim() ?? '';
    await ref.delete();
    await familyRef(familyDocId).set(<String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'memoriesCount': FieldValue.increment(-1),
    }, SetOptions(merge: true));
    if (imageUrl.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(imageUrl).delete();
      } catch (_) {
        // Best effort only; document deletion already succeeded.
      }
    }
  }
}
