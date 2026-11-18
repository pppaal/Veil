import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_state.dart';
import '../../../app/system_sheet_grace.dart';
import '../domain/attachment_rules.dart';
import 'attachment_picker.dart';
import 'attachment_storage_paths.dart';
import 'image_preparer.dart';

/// A pick, staged: a plaintext copy under an opaque name in the staging
/// folder, which the flow owns until it is sent or dropped.
sealed class AttachPick {
  const AttachPick(this.stagedPath);

  final String stagedPath;
}

/// A photo, being made ready to send while the preview shows it.
class PhotoPick extends AttachPick {
  const PhotoPick(super.stagedPath, this.prepared);

  /// The photo as it will be sent; null when it cannot be prepared (the
  /// staged copy is gone by then).
  final Future<PreparedImage?> prepared;
}

/// A file, sent as it is.
class FilePick extends AttachPick {
  const FilePick(super.stagedPath, {required this.name, required this.sizeBytes, required this.keepsMetadata});

  /// The picked name, sanitized as the web sanitizes it (D14).
  final String name;
  final int sizeBytes;

  /// A photo or a video picked as a file: it keeps any location in it
  /// (D13), which the confirm dialog says.
  final bool keepsMetadata;
}

/// Why a pick was not staged.
enum AttachRefusal { tooBig, photoFailed, fileFailed }

/// What picking came to: [pick], a [refusal], or neither (closed).
class AttachOutcome {
  const AttachOutcome.closed()
      : pick = null,
        refusal = null;
  const AttachOutcome.picked(AttachPick this.pick) : refusal = null;
  const AttachOutcome.refused(AttachRefusal this.refusal) : pick = null;

  final AttachPick? pick;
  final AttachRefusal? refusal;
}

/// Picking a photo or a file for one chat (D39, D40). Each picker runs
/// inside the system-sheet grace; a lock closes it like a cancel, and a
/// result the plugin still delivers afterwards is staged and held for this
/// chat's composer to show once it is back. The plugin's own copy goes as
/// soon as the pick is staged (only a copy under [PickerCopyRoots], never
/// the user's own file a desktop picker hands over), and the system
/// temporary folder is swept (iOS). A held pick is dropped after [holdFor],
/// or when the chat is left.
class AttachFlow {
  AttachFlow({
    required AttachmentPicker picker,
    required ImagePreparer preparer,
    required SystemSheetGrace grace,
    required AttachmentStoragePaths paths,
    PickerCopyRoots? copyRoots,
    this.holdFor = defaultHoldFor,
  })  : _picker = picker,
        _preparer = preparer,
        _grace = grace,
        _paths = paths,
        _copyRoots = copyRoots ?? PickerCopyRoots.platform();

  static const defaultHoldFor = Duration(minutes: 10);

  final AttachmentPicker _picker;
  final ImagePreparer _preparer;
  final SystemSheetGrace _grace;
  final AttachmentStoragePaths _paths;
  final PickerCopyRoots _copyRoots;
  final Duration holdFor;
  final Random _random = Random.secure();
  // Staged copies dropped while their photo was still being prepared.
  final Set<String> _dropped = {};
  Timer? _holdTimer;

  /// A pick waiting for this chat's composer: one that came back after a
  /// lock closed its picker, or whose preview the lock closed.
  final ValueNotifier<AttachPick?> held = ValueNotifier<AttachPick?>(null);

  /// Whether a pick may be held: not once the session left (signed out,
  /// wiped), so a picker that answers after that leaves nothing staged.
  bool holdsPicks = true;

  /// The system photo picker.
  Future<AttachOutcome> pickPhoto() => _pick(SystemSheet.photoPicker, _picker.pickPhoto, photo: true);

  /// The system file picker.
  Future<AttachOutcome> pickFile() => _pick(SystemSheet.filePicker, _picker.pickFile, photo: false);

  /// Hands over the held pick, if any; it is the caller's from then on.
  AttachPick? takeHeld() {
    final pick = held.value;
    _holdTimer?.cancel();
    held.value = null;
    return pick;
  }

  /// Keeps [pick] for this chat's composer, dropping one held before; once
  /// the session left ([holdsPicks] false), drops [pick] instead.
  void hold(AttachPick pick) {
    if (!holdsPicks) {
      unawaited(discard(pick));
      return;
    }
    final previous = held.value;
    if (previous != null && previous.stagedPath != pick.stagedPath) unawaited(discard(previous));
    held.value = pick;
    _holdTimer?.cancel();
    _holdTimer = Timer(holdFor, () {
      final expired = held.value;
      if (expired == null) return;
      held.value = null;
      unawaited(discard(expired));
    });
  }

  /// The chat was left: a held pick goes.
  void chatLeft() {
    final pick = takeHeld();
    if (pick != null) unawaited(discard(pick));
  }

  /// Deletes [pick]'s staged copy.
  Future<void> discard(AttachPick pick) {
    _dropped.add(pick.stagedPath);
    return _delete(pick.stagedPath);
  }

  void dispose() {
    chatLeft();
    held.dispose();
  }

  Future<AttachOutcome> _pick(SystemSheet sheet, Future<PickedFile?> Function() open, {required bool photo}) async {
    final PickedFile? picked;
    try {
      picked = await _grace.run(sheet, open, onLateResult: (late) => unawaited(_holdLate(late, photo: photo)));
    } on SheetClosedByLock {
      return const AttachOutcome.closed();
    } catch (_) {
      return AttachOutcome.refused(photo ? AttachRefusal.photoFailed : AttachRefusal.fileFailed);
    }
    if (picked == null) return const AttachOutcome.closed();
    return _stage(picked, photo: photo);
  }

  // A pick the plugin delivered after a lock closed its picker: staged and
  // held like any other, never left where the plugin put it.
  Future<void> _holdLate(PickedFile? late, {required bool photo}) async {
    if (late == null) return;
    final outcome = await _stage(late, photo: photo);
    if (outcome.pick case final pick?) hold(pick);
  }

  Future<AttachOutcome> _stage(PickedFile picked, {required bool photo}) async {
    File? staged;
    try {
      if (!photo && picked.sizeBytes > kMaxFileBytes) return const AttachOutcome.refused(AttachRefusal.tooBig);
      final staging = await _paths.stagingDir();
      staged = await File(picked.path).copy(p.join(staging.path, _opaqueName()));
      if (photo) return AttachOutcome.picked(PhotoPick(staged.path, _prepare(staged.path)));
      final name = sanitizeFileName(picked.name ?? p.basename(picked.path));
      final head = await _head(staged);
      return AttachOutcome.picked(FilePick(
        staged.path,
        name: name,
        sizeBytes: await staged.length(),
        keepsMetadata: looksLikePhotoOrVideo(head, name),
      ));
    } catch (_) {
      // Copied but not read: the copy goes too.
      if (staged != null) await _delete(staged.path);
      return AttachOutcome.refused(photo ? AttachRefusal.photoFailed : AttachRefusal.fileFailed);
    } finally {
      await _deletePickerCopy(_copyRoots, picked.path);
      await _paths.purgeSystemTemp().catchError((Object _) {});
    }
  }

  // The prepared photo takes the place of the picked one in staging, so
  // the original, with whatever metadata it holds, is gone as soon as it
  // can be.
  Future<PreparedImage?> _prepare(String stagedPath) async {
    try {
      final prepared = await _preparer.prepare(stagedPath);
      if (_dropped.contains(stagedPath)) return null;
      await File(stagedPath).writeAsBytes(prepared.bytes, flush: true);
      if (_dropped.contains(stagedPath)) throw StateError('dropped while it was written');
      return prepared;
    } catch (_) {
      await _delete(stagedPath);
      return null;
    }
  }

  static Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Gone already.
    }
  }

  static Future<List<int>> _head(File file) async {
    final reader = await file.open();
    try {
      return await reader.read(64);
    } finally {
      await reader.close();
    }
  }

  String _opaqueName() => List<String>.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// The plugin's copy at [path], and the folder of its own it made for it
/// (Android: `cache/<uuid>/` for photos, `cache/file_dialog-<uuid>/` for
/// files) once empty. Nothing outside [roots] is touched: a desktop picker hands
/// over the user's own file, and it stays where it is.
Future<void> _deletePickerCopy(PickerCopyRoots roots, String path) async {
  final copy = await roots.copyAt(path);
  if (copy == null) return;
  await AttachFlow._delete(copy);
  final folder = p.dirname(copy);
  if (!_pluginFolder.hasMatch(p.basename(folder)) || await roots.copyAt(folder) == null) return;
  try {
    await Directory(folder).delete();
  } on FileSystemException {
    // Not empty, or gone already: left alone.
  }
}

final RegExp _pluginFolder = RegExp(
  r'^(file_dialog-)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Once per process, the first time a chat's attach flow is read: Android's
/// lost picks (photos picked while the activity was killed) and whatever
/// the pickers left in the system temporary folder (iOS) are deleted.
final attachStartupCleanupProvider = FutureProvider<void>((ref) async {
  final paths = ref.read(attachmentStoragePathsProvider);
  final roots = ref.read(pickerCopyRootsProvider);
  try {
    for (final path in await ref.read(attachmentPickerProvider).recoverLostPicks()) {
      await _deletePickerCopy(roots, path);
    }
  } catch (_) {
    // Nothing to recover on this platform.
  }
  await paths.purgeSystemTemp().catchError((Object _) {});
});

/// The attach flow of one chat. It lives as long as the session does, so a
/// pick held for a chat survives the chat's screen being rebuilt after a
/// lock; leaving the session drops it.
final attachFlowProvider = Provider.family<AttachFlow, String>((ref, conversationId) {
  ref.read(attachStartupCleanupProvider);
  final flow = AttachFlow(
    picker: ref.read(attachmentPickerProvider),
    preparer: ref.read(imagePreparerProvider),
    grace: ref.read(systemSheetGraceProvider),
    paths: ref.read(attachmentStoragePathsProvider),
    copyRoots: ref.read(pickerCopyRootsProvider),
  );
  flow.holdsPicks = ref.read(appSessionProvider).isAuthenticated;
  ref.listen<bool>(appSessionProvider.select((session) => session.isAuthenticated), (_, authenticated) {
    flow.holdsPicks = authenticated;
    if (!authenticated) flow.chatLeft();
  });
  ref.onDispose(flow.dispose);
  return flow;
});
