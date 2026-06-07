import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/dimensions.dart';
import '../../../../core/services/doctor_link_request_service.dart';
import '../../../../core/theme/app_color_palette.dart';
import '../../../../core/usecases/notification_usecases.dart';
import '../../../../l10n/app_localizations.dart';

enum _SosStage { confirm, sending, sent }

class SosPage extends StatefulWidget {
  const SosPage({super.key});

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  _SosStage _stage = _SosStage.confirm;
  bool _sendingHelp = false;
  String _lastSharedLocationText = '';

  Stream<DocumentSnapshot<Map<String, dynamic>>?> _latestEmergencyRequestStream(
    String patientUid,
  ) {
    if (patientUid.trim().isEmpty) return Stream.value(null);
    return FirebaseFirestore.instance
        .collection('emergencyRequests')
        .where('patientUid', isEqualTo: patientUid)
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((query) => query.docs.isEmpty ? null : query.docs.first);
  }

  Stream<String> _caregiverNameStream(String patientUid) {
    if (patientUid.trim().isEmpty) return Stream.value('');
    return DoctorLinkRequestService.watchLatestAcceptedForPatient(
      patientUid,
    ).map((doc) {
      final data = doc?.data();
      return (data?['doctorName'] as String?)?.trim() ?? '';
    });
  }

  Future<String> _resolveEmergencyContactPhone(String patientUid) {
    return DoctorLinkRequestService.resolveLinkedDoctorPhone(patientUid);
  }

  Future<void> _callEmergencyContact() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    final phone = await _resolveEmergencyContactPhone(uid);
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency contact phone not available')),
      );
      return;
    }
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s+'), '')),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open phone app')));
    }
  }

  Future<({double? latitude, double? longitude, String locationText, String mapsUrl})>
  _readCurrentLocation() async {
    ({double? latitude, double? longitude, String locationText, String mapsUrl})
    fromPosition(Position pos) {
      final lat = pos.latitude;
      final lng = pos.longitude;
      final locationText = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      return (
        latitude: lat,
        longitude: lng,
        locationText: locationText,
        mapsUrl: 'https://maps.google.com/?q=$lat,$lng',
      );
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (
          latitude: null,
          longitude: null,
          locationText: 'Location service disabled',
          mapsUrl: '',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (
          latitude: null,
          longitude: null,
          locationText: 'Location permission denied',
          mapsUrl: '',
        );
      }

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        return fromPosition(pos);
      } catch (_) {
        // Fallback to a faster/lower-accuracy request first.
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 6),
            ),
          );
          return fromPosition(pos);
        } catch (_) {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            return fromPosition(lastKnown);
          }
        }
      }
      return (
        latitude: null,
        longitude: null,
        locationText: 'Location unavailable',
        mapsUrl: '',
      );
    } catch (_) {
      return (
        latitude: null,
        longitude: null,
        locationText: 'Location unavailable',
        mapsUrl: '',
      );
    }
  }

  Future<void> _triggerHelpRequest() async {
    if (_sendingHelp) return;
    setState(() {
      _sendingHelp = true;
      _stage = _SosStage.sending;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Please sign in first');
      }
      final linked = await DoctorLinkRequestService.watchLatestAcceptedForPatient(
        user.uid,
      ).first;
      final data = linked?.data();
      if (data == null) {
        throw Exception('No connected doctor found');
      }
      final doctorUid = (data['doctorId'] as String?)?.trim() ?? '';
      final patientName =
          (data['patientName'] as String?)?.trim().isNotEmpty == true
          ? (data['patientName'] as String).trim()
          : (user.displayName?.trim() ?? '');
      if (doctorUid.isEmpty) {
        throw Exception('No connected doctor found');
      }
      final pairId = [doctorUid, user.uid]..sort();
      final location = await _readCurrentLocation();
      final patientPhone = await DoctorLinkRequestService.resolvePatientPhone(
        patientUid: user.uid,
        linkData: data,
      );
      await SendHelpRequestUseCase().execute(
        pairId: '${pairId.first}_${pairId.last}',
        patientUid: user.uid,
        doctorUid: doctorUid,
        patientName: patientName,
        patientPhone: patientPhone,
        latitude: location.latitude,
        longitude: location.longitude,
        locationText: location.locationText,
        mapsUrl: location.mapsUrl,
      );
      if (!mounted) return;
      setState(() {
        _lastSharedLocationText = location.locationText;
        _stage = _SosStage.sent;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = _SosStage.confirm);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingHelp = false);
      }
    }
  }

  Widget _topBar(BuildContext context, String title) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _surfaceCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: appPadding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(Dimensions.cardCornerRadius),
      ),
      child: child,
    );
  }

  Widget _confirmStage(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: [
        _topBar(context, ''),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        const CircleAvatar(
          radius: 50,
          backgroundColor: Color(0xFFFFE9EC),
          child: Icon(
            Icons.warning_amber_rounded,
            color: AppColorPalette.redDark,
            size: 56,
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        Text(
          l10n.sosNeedHelpTitle,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        Text(
          l10n.sosConfirmAssistanceBody,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
            height: 1.5,
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _triggerHelpRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColorPalette.redBright,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(containerRadius),
              ),
            ),
            child: Text(
              l10n.sosYesSendHelp,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColorPalette.redDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(containerRadius),
              ),
            ),
            child: Text(
              l10n.cancel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        _surfaceCard(
          child: Column(
            children: [
              const SizedBox(height: Dimensions.verticalSpacingShort),
              const CircularProgressIndicator(strokeWidth: 3),
              const SizedBox(height: Dimensions.verticalSpacingRegular),
              Text(
                l10n.sosSendingCardTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColorPalette.blueSteel,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Dimensions.verticalSpacingShort),
              Text(
                l10n.sosConnectingContactsLine,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColorPalette.grey),
              ),
              const SizedBox(height: Dimensions.verticalSpacingRegular),
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  Dimensions.verticalSpacingLarge,
                ),
                child: const LinearProgressIndicator(
                  minHeight: 8,
                  value: 0.75,
                  color: AppColorPalette.blueSteel,
                  backgroundColor: Color(0xFFE8EEF2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.phone, color: AppColorPalette.blueBright),
          label: Text(l10n.sosViewEmergencyContacts),
        ),
      ],
    );
  }

  Widget _sendingStage(BuildContext context, AppLocalizations l10n) {
    final patientUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Column(
      children: [
        _topBar(context, l10n.sosAppBarEmergencySos),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        Container(
          width: 120,
          height: 120,
          decoration: const BoxDecoration(
            color: AppColorPalette.redBright,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            l10n.sosFabLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 0.9,
            ),
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        Text(
          l10n.sosHelpRequestSent,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),

        Container(
          width: 300,
          padding: appPadding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: Dimensions.horizontalSpacingRegular),
              Text(
                l10n.sosContactingFamily,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColorPalette.blueSteel,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        Text(
          l10n.sosSendingGuidanceBody,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.92),
            height: 1.5,
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
          stream: _latestEmergencyRequestStream(patientUid),
          builder: (context, requestSnap) {
            final requestData = requestSnap.data?.data();
            final locationFromDb =
                (requestData?['locationText'] as String?)?.trim() ?? '';
            final locationText = locationFromDb.isNotEmpty
                ? locationFromDb
                : (_lastSharedLocationText.trim().isNotEmpty
                      ? _lastSharedLocationText
                      : l10n.sosSampleAddress);
            return _surfaceCard(
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFDFF1F8),
                    child: Icon(
                      Icons.location_on_outlined,
                      color: AppColorPalette.blueSteel,
                    ),
                  ),
                  const SizedBox(width: Dimensions.horizontalSpacingRegular),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.sosLabelCurrentLocation,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorPalette.grey,
                        ),
                      ),
                      Text(
                        locationText,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        StreamBuilder<String>(
          stream: _caregiverNameStream(patientUid),
          builder: (context, doctorNameSnap) {
            final doctorName = doctorNameSnap.data?.trim() ?? '';
            return _surfaceCard(
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFFFEFD7),
                    child: Icon(
                      Icons.perm_phone_msg_outlined,
                      color: AppColorPalette.brownOlive,
                    ),
                  ),
                  const SizedBox(width: Dimensions.horizontalSpacingRegular),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.sosLabelPrimaryContact,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorPalette.grey,
                        ),
                      ),
                      Text(
                        doctorName.isNotEmpty
                            ? doctorName
                            : l10n.sosSamplePrimaryContact,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => setState(() => _stage = _SosStage.confirm),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(l10n.sosCancelRequest),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColorPalette.redDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(containerRadius),
              ),
            ),
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        Text(
          l10n.sosMistakeHint,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColorPalette.grey),
        ),
      ],
    );
  }

  Widget _sentStage(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: [
        _topBar(context, l10n.sosAppBarSosSent),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        const CircleAvatar(
          radius: 60,
          backgroundColor: Colors.white,
          child: CircleAvatar(
            radius: 36,
            backgroundColor: AppColorPalette.blueSteel,
            child: Icon(Icons.check, color: Colors.white, size: 50),
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        Text(
          l10n.sosSentSuccessTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        Text(
          l10n.sosSentSuccessBody,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
            height: 1.5,
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        _surfaceCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFDFF1F8),
                child: Icon(
                  Icons.gps_fixed_rounded,
                  color: AppColorPalette.blueSteel,
                ),
              ),
              const SizedBox(width: Dimensions.horizontalSpacingRegular),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sosLocationSharedTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    l10n.sosLocationSharedBody,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColorPalette.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingLarge),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColorPalette.blueSteel,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: Text(
              l10n.sosBackToHome,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton.icon(
            onPressed: _callEmergencyContact,
            icon: const Icon(Icons.phone_outlined, size: 25),
            label: Text(
              l10n.sosCallEmergencyNumber,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColorPalette.blueSteel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
        const SizedBox(height: Dimensions.verticalSpacingRegular),
        Text(
          l10n.sosHelpEtaNote,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColorPalette.grey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final content = switch (_stage) {
      _SosStage.confirm => _confirmStage(context, l10n),
      _SosStage.sending => _sendingStage(context, l10n),
      _SosStage.sent => _sentStage(context, l10n),
    };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: appPadding,
          child: Column(
            children: [
              Expanded(child: SingleChildScrollView(child: content)),
              if (_stage == _SosStage.sending)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _sendingHelp ? null : () => setState(() => _stage = _SosStage.sent),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColorPalette.blueSteel.withValues(
                        alpha: 0.25,
                      ),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(l10n.sosSimulateSent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
