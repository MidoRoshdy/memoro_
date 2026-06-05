import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/dimensions.dart';
import '../../../../core/models/family_member.dart';
import '../../../../core/models/family_memory.dart';
import '../../../../core/services/family_service.dart';
import '../../../../core/theme/app_color_palette.dart';
import '../../../shared/family/family_memories_gallery_page.dart';
import '../../../shared/family/family_member_profile_page.dart';
import 'doctor_add_family_member_page.dart';

class DoctorFamilyPage extends StatefulWidget {
  const DoctorFamilyPage({
    super.key,
    required this.doctorUid,
    required this.patientUid,
    required this.patientName,
  });

  final String doctorUid;
  final String patientUid;
  final String patientName;

  @override
  State<DoctorFamilyPage> createState() => _DoctorFamilyPageState();
}

class _DoctorFamilyPageState extends State<DoctorFamilyPage> {
  bool _uploadingMemory = false;

  Future<void> _callMember(BuildContext context, String phone) async {
    final trimmedPhone = phone.trim();
    if (trimmedPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available.')),
      );
      return;
    }
    final normalizedPhone = trimmedPhone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri(scheme: 'tel', path: normalizedPhone);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone app.')),
      );
    }
  }

  Future<void> _addFamilyMemory() async {
    if (_uploadingMemory) return;
    setState(() => _uploadingMemory = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final familyDocId = FamilyService.buildFamilyDocId(
        widget.doctorUid,
        widget.patientUid,
      );
      final path =
          'familyMemories/$familyDocId/${DateTime.now().microsecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      final snap = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final imageUrl = await snap.ref.getDownloadURL();
      await FamilyService.addMemory(
        familyDocId: familyDocId,
        doctorUid: widget.doctorUid,
        patientUid: widget.patientUid,
        imageUrl: imageUrl,
        createdByUid: widget.doctorUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memory added for patient.')),
      );
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open photos.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add memory right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingMemory = false);
      }
    }
  }

  Widget _memberTile(
    BuildContext context,
    FamilyMember member, {
    required bool isFavorite,
    required VoidCallback onToggleFavorite,
    required VoidCallback onOpenProfile,
  }) {
    return GestureDetector(
      onTap: onOpenProfile,
      child: Container(
        margin: const EdgeInsets.only(
          bottom: Dimensions.verticalSpacingRegular,
        ),
        padding: const EdgeInsets.all(Dimensions.verticalSpacingRegular),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(Dimensions.cardCornerRadius),
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColorPalette.blueSteel.withValues(
                    alpha: 0.18,
                  ),
                  backgroundImage: member.imageUrl.isNotEmpty
                      ? NetworkImage(member.imageUrl)
                      : null,
                  child: member.imageUrl.isEmpty
                      ? const Icon(
                          Icons.person_outline_rounded,
                          color: AppColorPalette.blueSteel,
                        )
                      : null,
                ),
                const SizedBox(width: Dimensions.horizontalSpacingRegular),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        member.relation,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorPalette.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Last contacted 2 hours ago',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorPalette.grey.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onToggleFavorite,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 18,
                      color: const Color(0xFFF3B400),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Dimensions.verticalSpacingRegular),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _callMember(context, member.phone),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: const Text('Call'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColorPalette.blueSteel,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentMemoriesSection(
    BuildContext context,
    List<FamilyMemory> memories,
    VoidCallback onSeeAll,
    VoidCallback onAdd,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Dimensions.verticalSpacingRegular),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Dimensions.cardCornerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recent Memories',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (_uploadingMemory)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onSeeAll,
                child: Text(
                  'See All',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.verticalSpacingRegular),
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: 6,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              if (index < memories.length) {
                final memory = memories[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    memory.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withValues(alpha: 0.35),
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                );
              }
              if (index == 5 && memories.length > 5) {
                final extra = memories.length - 5;
                return GestureDetector(
                  onTap: onSeeAll,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '+$extra\nMore',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColorPalette.blueSteel,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              }
              return GestureDetector(
                onTap: _uploadingMemory ? null : onAdd,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 28,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final familyDocId = FamilyService.buildFamilyDocId(
      widget.doctorUid,
      widget.patientUid,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleSpacing: 0,
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Material(
              color: Colors.white.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DoctorAddFamilyMemberPage(
                        familyDocId: familyDocId,
                        doctorUid: widget.doctorUid,
                        patientUid: widget.patientUid,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.add, color: AppColorPalette.blueSteel),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: appPadding,
          child: StreamBuilder<List<FamilyMember>>(
            stream: FamilyService.watchMembers(familyDocId),
            builder: (context, membersSnap) {
              final members = membersSnap.data ?? const <FamilyMember>[];
              return StreamBuilder<String?>(
                stream: FamilyService.watchFavoriteMemberId(familyDocId),
                builder: (context, favoriteSnap) {
                  final favoriteId = favoriteSnap.data;
                  FamilyMember? favorite;
                  if (members.isNotEmpty) {
                    favorite = members.firstWhere(
                      (m) => m.id == favoriteId,
                      orElse: () => members.first,
                    );
                  }
                  return StreamBuilder<List<FamilyMemory>>(
                    stream: FamilyService.watchFamilyMemories(
                      familyDocId,
                      limit: 12,
                    ),
                    builder: (context, memorySnap) {
                      final memories =
                          memorySnap.data ?? const <FamilyMemory>[];
                      return ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColorPalette.blueSteel.withValues(
                                      alpha: 0.5,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '${members.length}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      Text(
                                        'Family Members',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.white.withValues(
                                                alpha: 0.9,
                                              ),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: SizedBox(
                                    height: 72,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Image.asset(
                                              'assets/family/star.png',
                                              width: 12,
                                              height: 12,
                                            ),
                                            const SizedBox(width: 5),
                                            const Text(
                                              'Favorite',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        const Spacer(),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              favorite?.name ?? widget.patientName,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            Text(
                                              favorite?.relation ?? 'Family',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (members.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Text(
                                    'All Family Members',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'View All',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.9,
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          for (final member in members)
                            _memberTile(
                              context,
                              member,
                              isFavorite: member.id == favorite?.id,
                              onToggleFavorite: () {
                                FamilyService.setFavoriteMember(
                                  familyDocId: familyDocId,
                                  memberId: member.id,
                                );
                              },
                              onOpenProfile: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => FamilyMemberProfilePage(
                                      member: member,
                                      familyDocId: familyDocId,
                                      doctorUid: widget.doctorUid,
                                      patientUid: widget.patientUid,
                                      currentUserUid: widget.doctorUid,
                                      allowAddMemory: true,
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 8),
                          _recentMemoriesSection(
                            context,
                            memories,
                            () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => FamilyMemoriesGalleryPage(
                                    familyDocId: familyDocId,
                                    title: 'All Memories',
                                    forPatient: false,
                                    canAdd: true,
                                    doctorUid: widget.doctorUid,
                                    patientUid: widget.patientUid,
                                    createdByUid: widget.doctorUid,
                                  ),
                                ),
                              );
                            },
                            _addFamilyMemory,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => DoctorAddFamilyMemberPage(
                                      familyDocId: familyDocId,
                                      doctorUid: widget.doctorUid,
                                      patientUid: widget.patientUid,
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColorPalette.blueSteel,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                              label: const Text(
                                'Add Family Member',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => FamilyMemoriesGalleryPage(
                                      familyDocId: familyDocId,
                                      title: 'Manage Memories',
                                      forPatient: false,
                                      canManage: true,
                                      canAdd: true,
                                      doctorUid: widget.doctorUid,
                                      patientUid: widget.patientUid,
                                      createdByUid: widget.doctorUid,
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.9,
                                ),
                                foregroundColor: AppColorPalette.blueSteel,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text(
                                'Manage Memories',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: bottomNavigationBarPadding - 20,
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
