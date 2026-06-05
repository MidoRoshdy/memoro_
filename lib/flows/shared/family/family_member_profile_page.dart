import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/dimensions.dart';
import '../../../core/models/family_member.dart';
import '../../../core/models/family_memory.dart';
import '../../../core/services/family_service.dart';
import '../../../core/theme/app_color_palette.dart';
import 'family_memories_gallery_page.dart';

class FamilyMemberProfilePage extends StatefulWidget {
  const FamilyMemberProfilePage({
    super.key,
    required this.member,
    required this.familyDocId,
    required this.doctorUid,
    required this.patientUid,
    required this.currentUserUid,
    this.allowAddMemory = false,
  });

  final FamilyMember member;
  final String familyDocId;
  final String doctorUid;
  final String patientUid;
  final String currentUserUid;
  final bool allowAddMemory;

  @override
  State<FamilyMemberProfilePage> createState() =>
      _FamilyMemberProfilePageState();
}

class _FamilyMemberProfilePageState extends State<FamilyMemberProfilePage> {
  bool _uploadingMemory = false;
  bool _savingNote = false;
  late String _personalNote;

  @override
  void initState() {
    super.initState();
    _personalNote = widget.member.personalNote;
  }

  Future<void> _addMemory() async {
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
      final path =
          'familyMemories/${widget.familyDocId}/${widget.member.id}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      final snap = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final imageUrl = await snap.ref.getDownloadURL();
      await FamilyService.addMemoryToProfile(
        familyDocId: widget.familyDocId,
        doctorUid: widget.doctorUid,
        patientUid: widget.patientUid,
        memberId: widget.member.id,
        memberName: widget.member.name,
        imageUrl: imageUrl,
        createdByUid: widget.currentUserUid,
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

  Widget _memoryTile(BuildContext context, FamilyMemory memory) {
    final createdAt = memory.createdAt;
    final ageLabel = createdAt == null
        ? 'Recently'
        : _timeAgo(createdAt, DateTime.now());
    final title = memory.caption.isNotEmpty ? memory.caption : 'Shared Memory';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
            ),
            child: Image.network(
              memory.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.62),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  ageLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time, DateTime now) {
    final diff = now.difference(time);
    if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months == 1 ? '' : 's'} ago';
    }
    if (diff.inDays >= 7) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks week${weeks == 1 ? '' : 's'} ago';
    }
    if (diff.inDays >= 1)
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    if (diff.inHours >= 1)
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} min ago';
    return 'Just now';
  }

  Future<void> _confirmDeleteMember() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove family member?'),
        content: Text(
          '${widget.member.name} will be removed from the family list. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;
    try {
      await FamilyService.deleteMember(
        familyDocId: widget.familyDocId,
        memberId: widget.member.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.member.name} removed from family.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove family member.')),
      );
    }
  }

  Future<void> _editPersonalNote() async {
    final controller = TextEditingController(text: _personalNote);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Personal Notes'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          minLines: 4,
          decoration: const InputDecoration(
            hintText: 'Write notes about this person...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _savingNote = true);
    try {
      await FamilyService.updateMemberPersonalNote(
        familyDocId: widget.familyDocId,
        memberId: widget.member.id,
        personalNote: result,
      );
      if (!mounted) return;
      setState(() => _personalNote = result);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save note.')));
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: appPadding,
          child: StreamBuilder<List<FamilyMemory>>(
            stream: FamilyService.watchProfileMemories(
              widget.familyDocId,
              widget.member.id,
            ),
            builder: (context, snapshot) {
              final memories = snapshot.data ?? const <FamilyMemory>[];
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            'Family Member',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingRegular),
                    Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: Colors.white,
                              child: CircleAvatar(
                                radius: 45,
                                backgroundColor: AppColorPalette.blueSteel
                                    .withValues(alpha: 0.18),
                                backgroundImage: member.imageUrl.isNotEmpty
                                    ? NetworkImage(member.imageUrl)
                                    : null,
                                child: member.imageUrl.isEmpty
                                    ? const Icon(
                                        Icons.person_rounded,
                                        size: 38,
                                        color: AppColorPalette.blueSteel,
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              right: -2,
                              bottom: 2,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: Dimensions.verticalSpacingRegular,
                        ),
                        Text(
                          member.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '❤  ${member.relation}',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: const Color(0xFFE85A5A),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingMedium),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Dimensions.horizontalSpacingMedium,
                        vertical: Dimensions.verticalSpacingMedium,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Primary Contact',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: AppColorPalette.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            member.phone,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: AppColorPalette.blueSteel,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingRegular),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.call_rounded, size: 18),
                            label: const Text('Call'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColorPalette.blueSteel,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        if (widget.allowAddMemory) ...[
                          const SizedBox(
                            width: Dimensions.horizontalSpacingRegular,
                          ),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {},
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('Message'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.92,
                                ),
                                foregroundColor: AppColorPalette.blueSteel,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Dimensions.verticalSpacingMedium),
                    Row(
                      children: [
                        Text(
                          'Shared Memories',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const Spacer(),
                        if (widget.allowAddMemory)
                          IconButton(
                            onPressed: _uploadingMemory ? null : _addMemory,
                            icon: _uploadingMemory
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add, color: Colors.white),
                          ),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FamilyMemoriesGalleryPage(
                                  familyDocId: widget.familyDocId,
                                  memberId: widget.member.id,
                                  memberName: widget.member.name,
                                  title: 'Shared Memories',
                                  forPatient: !widget.allowAddMemory,
                                  canAdd: widget.allowAddMemory,
                                  doctorUid: widget.doctorUid,
                                  patientUid: widget.patientUid,
                                  createdByUid: widget.currentUserUid,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            'View All',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: const Color(0xFFE85A5A),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      itemCount: memories.length > 4 ? 4 : memories.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.2,
                          ),
                      itemBuilder: (_, index) =>
                          _memoryTile(context, memories[index]),
                    ),
                    if (memories.isEmpty)
                      Container(
                        height: 100,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'No memories yet.',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    const SizedBox(height: Dimensions.verticalSpacingMedium),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(
                        Dimensions.verticalSpacingMedium,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.sticky_note_2_outlined,
                                color: AppColorPalette.blueSteel,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Personal Notes',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: AppColorPalette.blueSteel,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: _savingNote
                                    ? null
                                    : _editPersonalNote,
                                icon: _savingNote
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add,
                                        color: AppColorPalette.blueSteel,
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _personalNote.isNotEmpty
                                ? _personalNote
                                : 'No personal notes yet. Tap + to add.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.black87, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                    if (widget.allowAddMemory) ...[
                      const SizedBox(height: Dimensions.verticalSpacingMedium),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _confirmDeleteMember,
                          icon: Icon(
                            Icons.person_remove_outlined,
                            color: Colors.red.shade700,
                          ),
                          label: Text(
                            'Remove Family Member',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.red.shade700),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: Dimensions.verticalSpacingLarge),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
