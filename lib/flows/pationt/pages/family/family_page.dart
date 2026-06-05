import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/constants/dimensions.dart';
import '../../../../core/models/family_member.dart';
import '../../../../core/models/family_memory.dart';
import '../../../../core/services/doctor_link_request_service.dart';
import '../../../../core/services/family_service.dart';
import '../../../../core/theme/app_color_palette.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../shared/family/family_memories_gallery_page.dart';
import '../../../shared/family/family_member_profile_page.dart';

class FamilyPage extends StatelessWidget {
  const FamilyPage({super.key});

  Widget _memberCard({
    required BuildContext context,
    required FamilyMember member,
    required String familyDocId,
    required String doctorUid,
    required String patientUid,
    required String currentUid,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: Dimensions.verticalSpacingRegular),
      padding: const EdgeInsets.all(Dimensions.verticalSpacingRegular),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(Dimensions.cardCornerRadius),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColorPalette.blueSteel.withValues(
                  alpha: 0.16,
                ),
                backgroundImage: member.imageUrl.isNotEmpty
                    ? NetworkImage(member.imageUrl)
                    : null,
                child: member.imageUrl.isEmpty
                    ? const Icon(Icons.person, color: AppColorPalette.blueSteel)
                    : null,
              ),
              const SizedBox(width: Dimensions.horizontalSpacingRegular),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      member.relation,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColorPalette.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.verticalSpacingRegular),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Call'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColorPalette.blueSteel,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Dimensions.horizontalSpacingRegular),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FamilyMemberProfilePage(
                          member: member,
                          familyDocId: familyDocId,
                          doctorUid: doctorUid,
                          patientUid: patientUid,
                          currentUserUid: currentUid,
                          allowAddMemory: false,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline_rounded, size: 16),
                  label: const Text('Profile'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _memoriesSection(
    BuildContext context,
    List<FamilyMemory> memories,
    VoidCallback onSeeAll,
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
              GestureDetector(
                onTap: onSeeAll,
                child: Text(
                  'See All',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
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
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    memories[index].imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                );
              }
              if (index == 5 && memories.length > 5) {
                final extra = memories.length - 5;
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
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
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
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
    final l10n = AppLocalizations.of(context)!;
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: appPadding,
          child: StreamBuilder<QueryDocumentSnapshot<Map<String, dynamic>>?>(
            stream: currentUid.isEmpty
                ? const Stream<
                    QueryDocumentSnapshot<Map<String, dynamic>>?
                  >.empty()
                : DoctorLinkRequestService.watchLatestAcceptedForPatient(
                    currentUid,
                  ),
            builder: (context, requestSnap) {
              final data = requestSnap.data?.data();
              final doctorUid = (data?['doctorId'] as String?)?.trim() ?? '';
              if (doctorUid.isEmpty) {
                return Center(
                  child: Text(
                    'No connected doctor yet.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }
              final familyDocId = FamilyService.buildFamilyDocId(
                doctorUid,
                currentUid,
              );
              return Column(
                children: [
                  Row(
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
                          l10n.familyScreenTitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: Dimensions.verticalSpacingRegular),
                  Expanded(
                    child: StreamBuilder<List<FamilyMember>>(
                      stream: FamilyService.watchMembers(familyDocId),
                      builder: (context, memberSnap) {
                        final members =
                            memberSnap.data ?? const <FamilyMember>[];
                        return StreamBuilder<List<FamilyMemory>>(
                          stream: FamilyService.watchFamilyMemories(
                            familyDocId,
                            limit: 12,
                            forPatient: true,
                          ),
                          builder: (context, memorySnap) {
                            final memories =
                                memorySnap.data ?? const <FamilyMemory>[];
                            return ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                for (final member in members)
                                  _memberCard(
                                    context: context,
                                    member: member,
                                    familyDocId: familyDocId,
                                    doctorUid: doctorUid,
                                    patientUid: currentUid,
                                    currentUid: currentUid,
                                  ),
                                _memoriesSection(context, memories, () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => FamilyMemoriesGalleryPage(
                                        familyDocId: familyDocId,
                                        title: 'All Memories',
                                        forPatient: true,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
