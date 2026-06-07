import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity_item.dart';
import '../models/medicine_item.dart';
import '../services/activity_service.dart';
import '../services/emergency_request_service.dart';
import '../services/local_notification_service.dart';

class SendHelpRequestUseCase {
  Future<void> execute({
    required String pairId,
    required String patientUid,
    required String doctorUid,
    String message = '',
    String patientName = '',
    String patientPhone = '',
    double? latitude,
    double? longitude,
    String locationText = '',
    String mapsUrl = '',
  }) async {
    await EmergencyRequestService.requestRef(pairId).set(<String, dynamic>{
      'pairId': pairId,
      'patientUid': patientUid,
      'doctorUid': doctorUid,
      'patientName': patientName.trim(),
      'message': message.trim(),
      'hasRequest': true,
      'isActive': true,
      'requestedAt': DateTime.now(),
      'updatedAt': DateTime.now(),
      'source': 'app',
      if (patientPhone.trim().isNotEmpty) 'patientPhone': patientPhone.trim(),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationText.trim().isNotEmpty) 'locationText': locationText.trim(),
      if (mapsUrl.trim().isNotEmpty) 'mapsUrl': mapsUrl.trim(),
    }, SetOptions(merge: true));
  }
}

class AssignActivityUseCase {
  Future<void> execute({
    required String activityDocId,
    required String doctorUid,
    required String patientUid,
    required String createdByUid,
    required String title,
    required String type,
    required String target,
    required String notes,
    required String scheduledTime,
    String assignedByName = '',
  }) {
    return ActivityService.addActivity(
      activityDocId: activityDocId,
      doctorUid: doctorUid,
      patientUid: patientUid,
      createdByUid: createdByUid,
      title: title,
      type: type,
      target: target,
      notes: notes,
      scheduledTime: scheduledTime,
      assignedByName: assignedByName,
    );
  }
}

class MarkActivityDoneUseCase {
  Future<void> execute({
    required String activityDocId,
    required String activityItemId,
  }) {
    return ActivityService.markCompleted(
      activityDocId: activityDocId,
      activityItemId: activityItemId,
    );
  }
}

class ScheduleMedicationReminderUseCase {
  Future<void> execute({
    required MedicineItem item,
    required String pairId,
  }) async {
    final times = item.scheduledTimes.isEmpty
        ? <String>[item.scheduledTime]
        : item.scheduledTimes;
    for (var i = 0; i < times.length; i++) {
      final parsed = _parseTime(times[i]);
      if (parsed == null) continue;
      await LocalNotificationService.scheduleDaily(
        id: _stableId('medication:$pairId:${item.id}:$i'),
        title: 'Medication reminder',
        body: '${item.name} - ${item.formattedDose}',
        time: parsed,
        channelId: LocalNotificationService.medicationChannelId,
        payload: <String, dynamic>{
          'type': 'medication_reminder',
          'pairId': pairId,
          'entityId': item.id,
          'data': <String, dynamic>{'medicineName': item.name},
        },
      );
    }
  }
}

class ScheduleActivityReminderUseCase {
  Future<void> execute({
    required ActivityItem item,
    required String pairId,
  }) async {
    final parsed = _parseTime(item.scheduledTime);
    if (parsed == null) return;
    await LocalNotificationService.scheduleDaily(
      id: _stableId('activity:$pairId:${item.id}'),
      title: 'Activity reminder',
      body: item.title,
      time: parsed,
      channelId: LocalNotificationService.activityChannelId,
      payload: <String, dynamic>{
        'type': 'activity_reminder',
        'pairId': pairId,
        'entityId': item.id,
      },
    );
  }
}

TimeOfDay? _parseTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final lower = value.toLowerCase();
  final isPm = lower.contains('pm');
  final isAm = lower.contains('am');
  final clean = lower.replaceAll('am', '').replaceAll('pm', '').trim();
  final parts = clean.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0].trim());
  final minute = int.tryParse(parts[1].trim());
  if (hour == null || minute == null) return null;
  var h = hour;
  if (isPm && h < 12) h += 12;
  if (isAm && h == 12) h = 0;
  if (h < 0 || h > 23 || minute < 0 || minute > 59) return null;
  return TimeOfDay(hour: h, minute: minute);
}

int _stableId(String value) {
  return value.hashCode & 0x7fffffff;
}
