import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/dimensions.dart';
import '../../../core/models/family_memory.dart';
import '../../../core/services/family_service.dart';
import '../../../core/theme/app_color_palette.dart';
import 'family_memory_viewer_page.dart';

class FamilyMemoriesGalleryPage extends StatefulWidget {
  const FamilyMemoriesGalleryPage({
    super.key,
    required this.familyDocId,
    required this.title,
    this.memberId,
    this.memberName,
    this.forPatient = false,
    this.canManage = false,
    this.canAdd = false,
    this.doctorUid,
    this.patientUid,
    this.createdByUid,
  });

  final String familyDocId;
  final String title;
  final String? memberId;
  final String? memberName;
  final bool forPatient;
  final bool canManage;
  final bool canAdd;
  final String? doctorUid;
  final String? patientUid;
  final String? createdByUid;

  @override
  State<FamilyMemoriesGalleryPage> createState() =>
      _FamilyMemoriesGalleryPageState();
}

class _FamilyMemoriesGalleryPageState extends State<FamilyMemoriesGalleryPage> {
  bool _uploadingMemory = false;

  Stream<List<FamilyMemory>> _stream() {
    if (widget.memberId != null && widget.memberId!.trim().isNotEmpty) {
      return FamilyService.watchProfileMemories(
        widget.familyDocId,
        widget.memberId!,
        forPatient: widget.forPatient,
      );
    }
    return FamilyService.watchFamilyMemories(
      widget.familyDocId,
      limit: 300,
      forPatient: widget.forPatient,
    );
  }

  Future<void> _addMemory() async {
    if (_uploadingMemory || !widget.canAdd) return;

    final doctorUid = widget.doctorUid?.trim() ?? '';
    final patientUid = widget.patientUid?.trim() ?? '';
    final createdByUid = widget.createdByUid?.trim() ?? '';
    if (doctorUid.isEmpty || patientUid.isEmpty || createdByUid.isEmpty) {
      return;
    }

    setState(() => _uploadingMemory = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final memberId = widget.memberId?.trim() ?? '';
      final path = memberId.isNotEmpty
          ? 'familyMemories/${widget.familyDocId}/$memberId/${DateTime.now().microsecondsSinceEpoch}.jpg'
          : 'familyMemories/${widget.familyDocId}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      final snap = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final imageUrl = await snap.ref.getDownloadURL();

      if (memberId.isNotEmpty) {
        await FamilyService.addMemoryToProfile(
          familyDocId: widget.familyDocId,
          doctorUid: doctorUid,
          patientUid: patientUid,
          memberId: memberId,
          memberName: widget.memberName?.trim() ?? '',
          imageUrl: imageUrl,
          createdByUid: createdByUid,
        );
      } else {
        await FamilyService.addMemory(
          familyDocId: widget.familyDocId,
          doctorUid: doctorUid,
          patientUid: patientUid,
          imageUrl: imageUrl,
          createdByUid: createdByUid,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memory added.')),
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

  Future<void> _onDelete(BuildContext context, FamilyMemory memory) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete memory?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    await FamilyService.deleteFamilyMemory(
      familyDocId: widget.familyDocId,
      memoryId: memory.id,
    );
  }

  Future<void> _toggleHidden(FamilyMemory memory) async {
    await FamilyService.setFamilyMemoryHiddenForPatient(
      familyDocId: widget.familyDocId,
      memoryId: memory.id,
      hiddenForPatient: !memory.hiddenForPatient,
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'No memories yet.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (widget.canAdd) ...[
            const SizedBox(height: Dimensions.verticalSpacingRegular),
            FilledButton.icon(
              onPressed: _uploadingMemory ? null : _addMemory,
              icon: _uploadingMemory
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add Memory'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.canAdd)
            IconButton(
              onPressed: _uploadingMemory ? null : _addMemory,
              icon: _uploadingMemory
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: appPadding,
          child: StreamBuilder<List<FamilyMemory>>(
            stream: _stream(),
            builder: (context, snapshot) {
              final memories = snapshot.data ?? const <FamilyMemory>[];
              if (snapshot.connectionState == ConnectionState.waiting &&
                  memories.isEmpty) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              if (memories.isEmpty) {
                return _emptyState();
              }
              return GridView.builder(
                itemCount: memories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final memory = memories[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FamilyMemoryViewerPage(
                                  imageUrl: memory.imageUrl,
                                  title: memory.memberName.isNotEmpty
                                      ? memory.memberName
                                      : 'Memory',
                                ),
                              ),
                            );
                          },
                          child: Image.network(
                            memory.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const DecoratedBox(
                              decoration: BoxDecoration(color: Colors.black12),
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        if (widget.canManage && widget.memberId == null)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'toggle') {
                                  await _toggleHidden(memory);
                                } else if (value == 'delete') {
                                  if (!context.mounted) return;
                                  await _onDelete(context, memory);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(
                                    memory.hiddenForPatient
                                        ? 'Show to patient'
                                        : 'Hide from patient',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                              color: Colors.white.withValues(alpha: 0.95),
                              icon: const Icon(
                                Icons.more_vert,
                                color: AppColorPalette.white,
                              ),
                            ),
                          ),
                        if (memory.hiddenForPatient)
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Hidden from patient',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
