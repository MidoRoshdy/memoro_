import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/dimensions.dart';
import '../../../../core/models/family_member.dart';
import '../../../../core/models/medicine_item.dart';
import '../../../../core/models/activity_item.dart';
import '../../../../core/models/patient_public_profile.dart';
import '../../../../core/services/activity_service.dart';
import '../../../../core/services/emergency_request_service.dart';
import '../../../../core/services/family_service.dart';
import '../../../../core/services/medicine_service.dart';
import '../../../../core/theme/app_color_palette.dart';
import '../../../../l10n/app_localizations.dart';
import '../family/doctor_family_page.dart';

const double _doctorCardRadius = 16;

const Color _doctorAccentBlue = Color(0xFF7EC8EB);

const double _emergencyButtonRadius = 8;

/// Pinkish-white emergency card surface.
const Color _emergencyCardSurface = Color(0xFFFFF7F7);

/// Medium red for patient name and timestamp on the emergency card.
const Color _emergencySecondaryRed = Color(0xFFC62828);

class DoctorPatientCareDashboardPage extends StatelessWidget {
  const DoctorPatientCareDashboardPage({
    super.key,
    required this.patient,
    required this.onOpenChatTab,
    required this.onOpenActivityTab,
    required this.onOpenMedicineTab,
  });

  final PatientPublicProfile patient;
  final VoidCallback onOpenChatTab;
  final VoidCallback onOpenActivityTab;
  final VoidCallback onOpenMedicineTab;

  static _NextDoseInfo? _nextDoseInfo(List<MedicineItem> medicines) {
    if (medicines.isEmpty) return null;
    final now = DateTime.now();
    _NextDoseInfo? best;

    for (final medicine in medicines) {
      final times = medicine.scheduledTimes.isNotEmpty
          ? medicine.scheduledTimes
          : <String>[medicine.scheduledTime];
      final fallbackRaw = medicine.primaryTime.trim();

      DateTime? localBestForMedicine;
      String localRaw = fallbackRaw;
      for (final raw in times) {
        final parsed = _parse24HourTime(raw);
        if (parsed == null) continue;
        var candidate = DateTime(
          now.year,
          now.month,
          now.day,
          parsed.$1,
          parsed.$2,
        );
        if (candidate.isBefore(now)) {
          candidate = candidate.add(const Duration(days: 1));
        }
        if (localBestForMedicine == null ||
            candidate.isBefore(localBestForMedicine)) {
          localBestForMedicine = candidate;
          localRaw = raw;
        }
      }

      final info = _NextDoseInfo(
        medicine: medicine,
        nextAt: localBestForMedicine,
        rawTime: localRaw,
      );
      if (best == null) {
        best = info;
        continue;
      }
      if (best.nextAt == null && info.nextAt != null) {
        best = info;
        continue;
      }
      if (best.nextAt != null &&
          info.nextAt != null &&
          info.nextAt!.isBefore(best.nextAt!)) {
        best = info;
      }
    }
    return best;
  }

  static (int, int)? _parse24HourTime(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  static String _formatDoseTime(BuildContext context, _NextDoseInfo info) {
    final nextAt = info.nextAt;
    if (nextAt != null) {
      return MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(nextAt));
    }
    return info.rawTime.trim().isNotEmpty ? info.rawTime : '--';
  }

  static bool _isEmergencyRequestActive(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['hasRequest'] == true || data['isActive'] == true) return true;
    final status =
        ((data['requestStatus'] ?? data['status']) as String?)
            ?.trim()
            .toLowerCase() ??
        '';
    return status == 'pending' ||
        status == 'active' ||
        status == 'open' ||
        status == 'sent' ||
        status == 'requested' ||
        status == 'new';
  }

  static DateTime? _extractEmergencyDate(Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw =
        data['requestedAt'] ??
        data['createdAt'] ??
        data['timestamp'] ??
        data['updatedAt'];
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  static String _extractEmergencyName(
    Map<String, dynamic>? data,
    String fallbackName,
  ) {
    final name =
        ((data?['requesterName'] ??
                    data?['patientName'] ??
                    data?['name'] ??
                    data?['requestedByName'])
                as String?)
            ?.trim() ??
        '';
    if (name.isNotEmpty) return name;
    return fallbackName;
  }

  static String _formatEmergencyTimeLabel(
    BuildContext context,
    DateTime? date,
    AppLocalizations l10n,
    bool hasRequest,
  ) {
    if (!hasRequest) return l10n.doctorMedAllGoodToday;
    if (date == null) return l10n.doctorMedRequiresAttention;
    final local = date.toLocal();
    final formattedDate = MaterialLocalizations.of(
      context,
    ).formatShortDate(local);
    final formattedTime = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$formattedDate, $formattedTime';
  }

  static double? _asDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  Future<void> _openEmergencyLocation(
    BuildContext context,
    Map<String, dynamic>? emergencyData,
  ) async {
    final mapsUrl = (emergencyData?['mapsUrl'] as String?)?.trim() ?? '';
    Uri? uri;
    if (mapsUrl.isNotEmpty) {
      uri = Uri.tryParse(mapsUrl);
    }
    uri ??= () {
      final lat = _asDouble(emergencyData?['latitude']);
      final lng = _asDouble(emergencyData?['longitude']);
      if (lat == null || lng == null) return null;
      return Uri.parse('https://maps.google.com/?q=$lat,$lng');
    }();

    if (uri == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No location available for this SOS request'),
        ),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open location map')),
      );
    }
  }

  Future<void> _markEmergencyRequestDone(
    BuildContext context, {
    required String emergencyRequestDocId,
    required String doctorUid,
  }) async {
    if (emergencyRequestDocId.trim().isEmpty) return;
    try {
      await EmergencyRequestService.requestRef(
        emergencyRequestDocId,
      ).set(<String, dynamic>{
        'hasRequest': false,
        'isActive': false,
        'requestStatus': 'resolved',
        'resolvedBy': doctorUid.trim(),
        'resolvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency request marked as done')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not close emergency request')),
      );
    }
  }

  String _resolveEmergencyPhone(Map<String, dynamic>? emergencyData) {
    final fromEmergency =
        (emergencyData?['patientPhone'] as String?)?.trim() ?? '';
    if (fromEmergency.isNotEmpty) return fromEmergency;
    return patient.phone.trim();
  }

  Future<void> _openEmergencyCall(
    BuildContext context,
    Map<String, dynamic>? emergencyData,
  ) async {
    final phone = await EmergencyRequestService.resolvePatientPhone(
      emergencyData: emergencyData,
      patientUid: patient.uid,
      fallbackPhone: _resolveEmergencyPhone(emergencyData),
    );
    if (phone.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available')),
      );
      return;
    }
    final normalizedPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri(scheme: 'tel', path: normalizedPhone);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone dialer')),
      );
    }
  }

  static _OverdueActivityInfo? _findOverdueActivity(
    List<ActivityItem> activities,
  ) {
    if (activities.isEmpty) return null;
    final now = DateTime.now();
    _OverdueActivityInfo? best;

    for (final activity in activities) {
      if (activity.isCompleted) continue;
      final parsed = _parse24HourTime(activity.scheduledTime);
      if (parsed == null) continue;
      final scheduled = DateTime(
        now.year,
        now.month,
        now.day,
        parsed.$1,
        parsed.$2,
      );
      if (!scheduled.isBefore(now)) continue;
      final overdue = now.difference(scheduled);
      if (best == null || overdue > best.overdueBy) {
        best = _OverdueActivityInfo(activity: activity, overdueBy: overdue);
      }
    }
    return best;
  }

  static String _formatOverdueDuration(
    AppLocalizations l10n,
    Duration duration,
  ) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return l10n.doctorActivityDurationHoursMinutes(hours, minutes);
    }
    final safeMinutes = duration.inMinutes <= 0 ? 1 : duration.inMinutes;
    return l10n.doctorActivityDurationMinutes(safeMinutes);
  }

  static _OverdueMedicationInfo? _findOverdueMedication(
    List<MedicineItem> medicines,
  ) {
    if (medicines.isEmpty) return null;
    final now = DateTime.now();
    _OverdueMedicationInfo? best;

    for (final medicine in medicines) {
      if (medicine.isTaken) continue;
      final times = medicine.scheduledTimes.isNotEmpty
          ? medicine.scheduledTimes
          : <String>[medicine.scheduledTime];
      for (final raw in times) {
        final parsed = _parse24HourTime(raw);
        if (parsed == null) continue;
        final scheduled = DateTime(
          now.year,
          now.month,
          now.day,
          parsed.$1,
          parsed.$2,
        );
        if (!scheduled.isBefore(now)) continue;
        final overdue = now.difference(scheduled);
        if (best == null || overdue > best.overdueBy) {
          best = _OverdueMedicationInfo(
            medicine: medicine,
            overdueBy: overdue,
            scheduledTime: raw,
          );
        }
      }
    }
    return best;
  }

  static Widget _doctorSolidCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: appPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_doctorCardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  static Widget _doctorDashedCard({required Widget child}) {
    return CustomPaint(
      foregroundPainter: _DoctorDashBorderPainter(
        radius: _doctorCardRadius,
        color: _doctorAccentBlue.withValues(alpha: 0.85),
      ),
      child: _doctorSolidCard(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final doctorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final familyDocId = doctorUid.isEmpty
        ? ''
        : FamilyService.buildFamilyDocId(doctorUid, patient.uid);
    final medicineDocId = doctorUid.isEmpty
        ? ''
        : MedicineService.buildMedicineDocId(doctorUid, patient.uid);
    final activityDocId = doctorUid.isEmpty
        ? ''
        : ActivityService.buildActivityDocId(doctorUid, patient.uid);
    final emergencyRequestDocId = doctorUid.isEmpty
        ? ''
        : EmergencyRequestService.buildEmergencyRequestDocId(
            doctorUid,
            patient.uid,
          );
    final displayName = patient.name.trim().isNotEmpty
        ? patient.name.trim()
        : l10n.profilePlaceholderUserName;
    final ageLabel = patient.age != null ? '${patient.age}' : '—';
    final imageUrl = patient.imageUrl.trim();
    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Dimensions.verticalSpacingShort),
              StreamBuilder<Map<String, dynamic>?>(
                stream: emergencyRequestDocId.isEmpty
                    ? const Stream<Map<String, dynamic>?>.empty()
                    : EmergencyRequestService.watchRequest(
                        emergencyRequestDocId,
                      ),
                builder: (context, emergencySnap) {
                  final emergencyData = emergencySnap.data;
                  final hasRequest = _isEmergencyRequestActive(emergencyData);
                  final nameLine = _extractEmergencyName(
                    emergencyData,
                    displayName,
                  );
                  final timeLine = _formatEmergencyTimeLabel(
                    context,
                    _extractEmergencyDate(emergencyData),
                    l10n,
                    hasRequest,
                  );
                  final accent = hasRequest
                      ? AppColorPalette.redBright
                      : const Color(0xFF4CAF50);
                  final icon = hasRequest
                      ? Icons.warning_rounded
                      : Icons.verified_rounded;

                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _emergencyCardSurface,
                      borderRadius: BorderRadius.circular(_doctorCardRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(width: 6, color: accent),
                          Expanded(
                            child: Padding(
                              padding: appPadding,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(icon, size: 30, color: accent),
                                      const SizedBox(
                                        width:
                                            Dimensions.verticalSpacingRegular,
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                l10n.doctorEmergencyRequestTitle,
                                                style: theme
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: hasRequest
                                                          ? AppColorPalette
                                                                .redDark
                                                          : AppColorPalette
                                                                .emerald,
                                                      height: 1.2,
                                                    ),
                                              ),
                                              if (hasRequest) ...[
                                                const SizedBox(
                                                  height: Dimensions
                                                      .verticalSpacingExtraShort,
                                                ),
                                                Text(
                                                  nameLine,
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color:
                                                            _emergencySecondaryRed,
                                                        height: 1.25,
                                                      ),
                                                ),
                                              ],
                                              const SizedBox(
                                                height: Dimensions
                                                    .verticalSpacingExtraShort,
                                              ),
                                              Text(
                                                timeLine,
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: hasRequest
                                                          ? _emergencySecondaryRed
                                                          : AppColorPalette
                                                                .tealDark,
                                                      height: 1.25,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (hasRequest)
                                        TextButton.icon(
                                          onPressed: () =>
                                              _markEmergencyRequestDone(
                                                context,
                                                emergencyRequestDocId:
                                                    emergencyRequestDocId,
                                                doctorUid: doctorUid,
                                              ),
                                          icon: const Icon(
                                            Icons.check_circle_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Done'),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                AppColorPalette.emerald,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            minimumSize: const Size(0, 32),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (hasRequest) ...[
                                    const SizedBox(
                                      height: Dimensions.verticalSpacingRegular,
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: () => _openEmergencyCall(
                                              context,
                                              emergencyData,
                                            ),
                                            icon: const Icon(
                                              Icons.call_rounded,
                                              size: 18,
                                            ),
                                            label: Text(l10n.doctorCallButton),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFFE53935,
                                              ),
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      _emergencyButtonRadius,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                          width:
                                              Dimensions.verticalSpacingShort,
                                        ),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _openEmergencyLocation(
                                                  context,
                                                  emergencyData,
                                                ),
                                            icon: const Icon(
                                              Icons.location_on_outlined,
                                              size: 18,
                                            ),
                                            label: Text(
                                              l10n.doctorLocationButton,
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFFE53935,
                                              ),
                                              backgroundColor: Colors.white,
                                              side: BorderSide(
                                                color: AppColorPalette.redBright
                                                    .withValues(alpha: 0.45),
                                                width: 1.2,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      _emergencyButtonRadius,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                          width:
                                              Dimensions.verticalSpacingShort,
                                        ),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: onOpenChatTab,
                                            icon: const Icon(
                                              Icons.chat_bubble_outline_rounded,
                                              size: 18,
                                            ),
                                            label: Text(
                                              l10n.doctorMessageButton,
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFFE53935,
                                              ),
                                              backgroundColor: Colors.white,
                                              side: BorderSide(
                                                color: AppColorPalette.redBright
                                                    .withValues(alpha: 0.45),
                                                width: 1.2,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      _emergencyButtonRadius,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: Dimensions.verticalSpacingRegular),
              _doctorDashedCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _doctorAccentBlue,
                              width: 4,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColorPalette.blueSteel
                                .withValues(alpha: 0.12),
                            backgroundImage: imageUrl.isNotEmpty
                                ? NetworkImage(imageUrl)
                                : null,
                            child: imageUrl.isEmpty
                                ? Icon(
                                    Icons.person_rounded,
                                    size: 44,
                                    color: AppColorPalette.blueSteel,
                                  )
                                : null,
                          ),
                        ),
                        PositionedDirectional(
                          end: 4,
                          bottom: 4,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingRegular),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF4A90E2),
                      ),
                    ),
                    const SizedBox(
                      height: Dimensions.verticalSpacingExtraShort,
                    ),
                    Text(
                      l10n.doctorPatientAgeRoom(ageLabel, '—'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingRegular),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Dimensions.verticalSpacingShort + 4,
                        vertical: Dimensions.verticalSpacingExtraShort + 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColorPalette.mint.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.doctorStatusStable,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppColorPalette.tealDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Dimensions.verticalSpacingRegular),
              _doctorDashedCard(
                child: StreamBuilder<List<MedicineItem>>(
                  stream: medicineDocId.isEmpty
                      ? const Stream<List<MedicineItem>>.empty()
                      : MedicineService.watchMedicines(medicineDocId),
                  builder: (context, medSnap) {
                    final meds = medSnap.data ?? const <MedicineItem>[];
                    final medsDone = meds.where((m) => m.isTaken).length;
                    return StreamBuilder<List<ActivityItem>>(
                      stream: activityDocId.isEmpty
                          ? const Stream<List<ActivityItem>>.empty()
                          : ActivityService.watchActivities(activityDocId),
                      builder: (context, activitySnap) {
                        final activities =
                            activitySnap.data ?? const <ActivityItem>[];
                        final activitiesDone = activities
                            .where((a) => a.isCompleted)
                            .length;
                        final totalCount = meds.length + activities.length;
                        final completedCount = medsDone + activitiesDone;
                        final progressValue = totalCount == 0
                            ? 0.0
                            : (completedCount / totalCount).clamp(0.0, 1.0);
                        final percent = (progressValue * 100).round();
                        final summary = totalCount == 0
                            ? l10n.doctorProgressNoItemsYet
                            : l10n.doctorProgressSummary(
                                completedCount,
                                totalCount,
                              );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l10n.doctorPatientProgressTitle,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF4A90E2),
                                  ),
                                ),
                                Text(
                                  l10n.doctorWellnessPercent('$percent'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF4A90E2),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(
                              height: Dimensions.verticalSpacingShort,
                            ),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progressValue,
                                minHeight: 14,
                                backgroundColor: const Color(0xFFE8EEF2),
                                color: const Color(0xFF4A90E2),
                              ),
                            ),
                            const SizedBox(
                              height: Dimensions.verticalSpacingShort,
                            ),
                            Text(
                              summary,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColorPalette.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: Dimensions.verticalSpacingLarge),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.doctorAlertsSectionTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    l10n.doctorActiveAlertsCount(2),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColorPalette.blueSteel,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Dimensions.verticalSpacingRegular),
              _doctorSolidCard(
                child: Column(
                  children: [
                    StreamBuilder<List<MedicineItem>>(
                      stream: medicineDocId.isEmpty
                          ? const Stream<List<MedicineItem>>.empty()
                          : MedicineService.watchMedicines(medicineDocId),
                      builder: (context, medSnap) {
                        final medicines =
                            medSnap.data ?? const <MedicineItem>[];
                        final overdue = _findOverdueMedication(medicines);
                        if (overdue == null) {
                          return _alertDetailBlock(
                            context,
                            icon: Icons.check_circle_outline_rounded,
                            iconColor: AppColorPalette.emerald,
                            iconBg: AppColorPalette.mint.withValues(
                              alpha: 0.75,
                            ),
                            title: l10n.doctorAlertMissedMedication,
                            detail: l10n.doctorMedNoMissedNow,
                            meta: l10n.doctorMedAllGoodToday,
                            metaColor: AppColorPalette.emerald,
                            actionLabel: l10n.doctorMedViewDetails,
                            onActionTap: onOpenMedicineTab,
                          );
                        }
                        final overdueDurationLabel = _formatOverdueDuration(
                          l10n,
                          overdue.overdueBy,
                        );
                        final overdueDetail = overdue.scheduledTime.isNotEmpty
                            ? l10n.doctorMedLatestWithTime(
                                overdue.medicine.name,
                                overdue.scheduledTime,
                              )
                            : overdue.medicine.name;
                        return _alertDetailBlock(
                          context,
                          icon: Icons.error_outline_rounded,
                          iconColor: AppColorPalette.redBright,
                          iconBg: AppColorPalette.peachPink,
                          title: l10n.doctorAlertMissedMedication,
                          detail: overdueDetail,
                          meta: l10n.doctorActivityOverdueBy(
                            overdueDurationLabel,
                          ),
                          metaColor: AppColorPalette.redBright,
                          actionLabel: l10n.doctorMedViewDetails,
                          onActionTap: onOpenMedicineTab,
                        );
                      },
                    ),
                    Divider(
                      height: Dimensions.verticalSpacingLarge,
                      color: AppColorPalette.lightGrey.withValues(alpha: 0.5),
                    ),
                    StreamBuilder<List<ActivityItem>>(
                      stream: activityDocId.isEmpty
                          ? const Stream<List<ActivityItem>>.empty()
                          : ActivityService.watchActivities(activityDocId),
                      builder: (context, activitySnap) {
                        final activities =
                            activitySnap.data ?? const <ActivityItem>[];
                        final overdue = _findOverdueActivity(activities);
                        if (overdue == null) {
                          return _alertDetailBlock(
                            context,
                            icon: Icons.check_circle_outline_rounded,
                            iconColor: AppColorPalette.emerald,
                            iconBg: AppColorPalette.mint.withValues(
                              alpha: 0.75,
                            ),
                            title: l10n.doctorAlertActivityReminder,
                            detail: l10n.doctorActivityNoMissedNow,
                            meta: l10n.doctorMedAllGoodToday,
                            metaColor: AppColorPalette.emerald,
                          );
                        }
                        final overdueDurationLabel = _formatOverdueDuration(
                          l10n,
                          overdue.overdueBy,
                        );
                        final overdueDetail =
                            overdue.activity.scheduledTime.isNotEmpty
                            ? l10n.doctorActivityLatestWithTime(
                                overdue.activity.title,
                                overdue.activity.scheduledTime,
                              )
                            : overdue.activity.title;

                        return _alertDetailBlock(
                          context,
                          icon: Icons.notifications_active_outlined,
                          iconColor: const Color(0xFFEA580C),
                          iconBg: AppColorPalette.gold.withValues(alpha: 0.45),
                          title: l10n.doctorAlertActivityReminder,
                          detail: overdueDetail,
                          meta: l10n.doctorActivityOverdueBy(
                            overdueDurationLabel,
                          ),
                          metaColor: const Color(0xFFEA580C),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Dimensions.verticalSpacingLarge),
              _doctorSolidCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.medScreenTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onOpenMedicineTab,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColorPalette.blueSteel,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            l10n.doctorMedViewAll,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: AppColorPalette.blueSteel,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingRegular),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Dimensions.verticalSpacingRegular,
                        vertical: Dimensions.verticalSpacingRegular,
                      ),
                      decoration: BoxDecoration(
                        color: AppColorPalette.lightGrey.withValues(
                          alpha: 0.32,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: StreamBuilder<List<MedicineItem>>(
                        stream: medicineDocId.isEmpty
                            ? const Stream<List<MedicineItem>>.empty()
                            : MedicineService.watchMedicines(medicineDocId),
                        builder: (context, medicinesSnap) {
                          final medicines =
                              medicinesSnap.data ?? const <MedicineItem>[];
                          final nextDose = _nextDoseInfo(medicines);
                          final hasDose = nextDose != null;
                          final doseTime = hasDose
                              ? _formatDoseTime(context, nextDose)
                              : '';
                          final doseLine = hasDose
                              ? '${nextDose.medicine.name} - $doseTime'
                              : l10n.doctorMedNoMedicationYet;
                          final trailing = hasDose
                              ? (nextDose.nextAt != null
                                    ? l10n.doctorMedNextAt(doseTime)
                                    : nextDose.medicine.frequency)
                              : '--';

                          return Row(
                            children: [
                              Icon(
                                Icons.medication_rounded,
                                color: AppColorPalette.blueSteel,
                                size: 28,
                              ),
                              const SizedBox(
                                width: Dimensions.verticalSpacingRegular,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.doctorNextDoseLabel,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: AppColorPalette.grey,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(
                                      height:
                                          Dimensions.verticalSpacingExtraShort,
                                    ),
                                    Text(
                                      doseLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                trailing,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: AppColorPalette.blueSteel,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingRegular),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onOpenMedicineTab,
                        icon: const Icon(Icons.add_rounded, size: 22),
                        label: Text(
                          l10n.doctorAddMedication,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColorPalette.blueSteel,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              containerRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Dimensions.verticalSpacingRegular),
              _doctorSolidCard(
                child: StreamBuilder<List<ActivityItem>>(
                  stream: activityDocId.isEmpty
                      ? const Stream<List<ActivityItem>>.empty()
                      : ActivityService.watchActivities(activityDocId),
                  builder: (context, activitiesSnap) {
                    final activities =
                        activitiesSnap.data ?? const <ActivityItem>[];
                    final completedCount = activities
                        .where((a) => a.isCompleted)
                        .length;
                    final latest = activities.isNotEmpty
                        ? activities.first
                        : null;
                    final progressLine = latest == null
                        ? l10n.doctorActivityNoActivitiesYet
                        : (latest.scheduledTime.isNotEmpty
                              ? l10n.doctorActivityLatestWithTime(
                                  latest.title,
                                  latest.scheduledTime,
                                )
                              : latest.title);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.doctorActivitiesTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              l10n.doctorActivitiesCompletedCount(
                                completedCount,
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: AppColorPalette.emerald,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Dimensions.verticalSpacingShort),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColorPalette.mint.withValues(
                                  alpha: 0.85,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: AppColorPalette.emerald,
                                size: 24,
                              ),
                            ),
                            const SizedBox(
                              width: Dimensions.verticalSpacingShort,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.doctorTodaysProgressLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColorPalette.grey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(
                                    height:
                                        Dimensions.verticalSpacingExtraShort,
                                  ),
                                  Text(
                                    progressLine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: Dimensions.verticalSpacingRegular,
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: onOpenActivityTab,
                            icon: const Icon(
                              Icons.calendar_month_rounded,
                              size: 22,
                            ),
                            label: Text(
                              l10n.doctorAssignActivity,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColorPalette.blueSteel,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  containerRadius,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: Dimensions.verticalSpacingRegular),
              _doctorSolidCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.doctorFamilyMembersTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingRegular),
                    SizedBox(
                      height: 48,
                      child: StreamBuilder<List<FamilyMember>>(
                        stream: familyDocId.isEmpty
                            ? const Stream<List<FamilyMember>>.empty()
                            : FamilyService.watchMembers(familyDocId),
                        builder: (context, membersSnap) {
                          final members =
                              membersSnap.data ?? const <FamilyMember>[];
                          return Stack(
                            clipBehavior: Clip.none,
                            children: List.generate(3, (i) {
                              final member = i < members.length
                                  ? members[i]
                                  : null;
                              final memberImageUrl =
                                  member?.imageUrl.trim() ?? '';
                              final showImage = memberImageUrl.isNotEmpty;
                              return PositionedDirectional(
                                start: i * 28,
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.white,
                                  child: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppColorPalette.blueSteel
                                        .withValues(alpha: 0.12 + i * 0.06),
                                    backgroundImage: showImage
                                        ? NetworkImage(memberImageUrl)
                                        : null,
                                    child: showImage
                                        ? null
                                        : Icon(
                                            Icons.person_outline_rounded,
                                            color: AppColorPalette.blueSteel,
                                          ),
                                  ),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingShort),
                    StreamBuilder<List<FamilyMember>>(
                      stream: familyDocId.isEmpty
                          ? const Stream<List<FamilyMember>>.empty()
                          : FamilyService.watchMembers(familyDocId),
                      builder: (context, membersSnap) {
                        final membersCount = membersSnap.data?.length ?? 0;
                        return Text(
                          l10n.doctorFamilyAccessLine(membersCount),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColorPalette.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingRegular),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (doctorUid.isEmpty) return;
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DoctorFamilyPage(
                                doctorUid: doctorUid,
                                patientUid: patient.uid,
                                patientName: displayName,
                              ),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColorPalette.blueSteel,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              containerRadius,
                            ),
                          ),
                        ),
                        child: Text(
                          l10n.doctorManageFamily,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: bottomNavigationBarPadding + 56),
            ],
          ),
        ),
        PositionedDirectional(
          end: 0,
          bottom: bottomNavigationBarPadding - 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _roundFab(
                icon: Icons.chat_bubble_outline_rounded,
                label: l10n.doctorFloatingChat,
                onTap: onOpenChatTab,
              ),
              const SizedBox(height: Dimensions.verticalSpacingShort),
              _roundFab(
                icon: Icons.phone_in_talk_rounded,
                label: l10n.doctorFloatingCall,
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _alertDetailBlock(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String detail,
    required String meta,
    required Color metaColor,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: Dimensions.verticalSpacingRegular),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: Dimensions.verticalSpacingExtraShort),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColorPalette.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Dimensions.verticalSpacingExtraShort),
              Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: metaColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (actionLabel != null && onActionTap != null) ...[
                const SizedBox(height: Dimensions.verticalSpacingExtraShort),
                TextButton(
                  onPressed: onActionTap,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColorPalette.blueSteel,
                  ),
                  child: Text(
                    actionLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColorPalette.blueSteel,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static Widget _roundFab({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: Material(
        color: AppColorPalette.blueSteel,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

class _NextDoseInfo {
  const _NextDoseInfo({
    required this.medicine,
    required this.nextAt,
    required this.rawTime,
  });

  final MedicineItem medicine;
  final DateTime? nextAt;
  final String rawTime;
}

class _OverdueActivityInfo {
  const _OverdueActivityInfo({required this.activity, required this.overdueBy});

  final ActivityItem activity;
  final Duration overdueBy;
}

class _OverdueMedicationInfo {
  const _OverdueMedicationInfo({
    required this.medicine,
    required this.overdueBy,
    required this.scheduledTime,
  });

  final MedicineItem medicine;
  final Duration overdueBy;
  final String scheduledTime;
}

class _DoctorDashBorderPainter extends CustomPainter {
  _DoctorDashBorderPainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  static const double _strokeWidth = 1.25;
  static const double _dashLength = 5;
  static const double _gapLength = 4;

  static void _paintDashedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double dash,
    double gap,
  ) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final inset = _strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - _strokeWidth,
      size.height - _strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    _paintDashedPath(canvas, path, paint, _dashLength, _gapLength);
  }

  @override
  bool shouldRepaint(covariant _DoctorDashBorderPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.color != color;
  }
}
