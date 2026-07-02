import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

const _shortLinkHost = 'rtw.codes';

/// Category chips offered for room filters — the canonical primary tags of
/// the question bank (spec §5).
const roomCategoryOptions = [
  'Food & Drink',
  'Technology',
  'Work & Money',
  'Money',
  'Travel',
  'Social',
  'Psychology',
  'Relationships',
  'Ethics',
  'Entertainment',
  'Lifestyle',
  'Deep',
];

Widget _sheetEyebrow(String text, {Color color = RtwV2Colors.muted}) =>
    V2Eyebrow(text, color: color);

Widget _sheetTitle(String text) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Text(text, style: v2Serif(26, letterSpacing: -0.3)),
);

Widget _sheetBody(String text) => Padding(
  padding: const EdgeInsets.only(top: 10),
  child: Text(text, style: v2Sans(14, color: RtwV2Colors.subText, height: 1.55)),
);

InputDecoration _inputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: v2Sans(15, color: RtwV2Colors.faint),
  filled: true,
  fillColor: RtwV2Colors.card,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: RtwV2Colors.borderStrong),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: RtwV2Colors.blue),
  ),
);

Widget _ghostDoneButton(BuildContext context, {String label = 'Done'}) => Padding(
  padding: const EdgeInsets.only(top: 16),
  child: SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFFDCD6C9), width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        label,
        style: v2Sans(15, color: RtwV2Colors.inkSoft, weight: FontWeight.w600),
      ),
    ),
  ),
);

// ── CREATE ROOM ─────────────────────────────────────────────────────────

Future<void> showCreateRoomSheet(BuildContext context, WidgetRef ref) {
  return showV2Sheet(context, (context) => _CreateRoomSheet(ref: ref));
}

class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  final nameController = TextEditingController();
  RoomTier tier = RoomTier.normal;
  List<String> cats = ['All'];
  bool customEnabled = true;
  bool revealAnswers = true;
  bool submitting = false;
  String? error;

  static const tierDescriptions = {
    RoomTier.workSafe: 'Lightest topics — safe for a company or team.',
    RoomTier.normal: 'Everyday questions. Includes work-safe topics.',
    RoomTier.mature: 'Edgier, words-only. Includes all lighter topics.',
  };

  void _toggleCat(String cat) {
    setState(() {
      if (cat == 'All') {
        cats = ['All'];
        return;
      }
      var next = cats.where((c) => c != 'All').toList();
      next = next.contains(cat)
          ? next.where((c) => c != cat).toList()
          : [...next, cat];
      cats = next.isEmpty ? ['All'] : next;
    });
  }

  Future<void> _submit() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'Give your room a name.');
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    final rooms = widget.ref.read(roomsControllerProvider);
    final roomId = await rooms.createRoom(
      name: name,
      tier: tier,
      colorToken: RtwV2Colors.roomColorByToken.keys.elementAt(2),
      cats: cats,
      customEnabled: customEnabled,
      revealAnswers: revealAnswers,
    );
    if (!mounted) return;
    if (roomId == null) {
      setState(() {
        submitting = false;
        error = rooms.lastError ?? 'Could not create the room.';
      });
      return;
    }
    Navigator.of(context).pop();
    await showInviteSheet(context, rooms, roomId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetEyebrow('New room'),
                _sheetTitle('Start a room.'),
              ],
            ),
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                showJoinRoomSheet(context, widget.ref);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Have a code? ›',
                  style: v2Sans(13, color: RtwV2Colors.blue, weight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _sheetEyebrow('Room name'),
        const SizedBox(height: 8),
        TextField(
          controller: nameController,
          style: v2Sans(16, color: RtwV2Colors.inkSoft),
          decoration: _inputDecoration('The Group Chat'),
        ),
        const SizedBox(height: 18),
        _sheetEyebrow('Safety tier'),
        const SizedBox(height: 10),
        _TierSegment(value: tier, onChanged: (next) => setState(() => tier = next)),
        const SizedBox(height: 9),
        Text(
          tierDescriptions[tier]!,
          style: v2Sans(12.5, color: RtwV2Colors.muted, height: 1.45),
        ),
        const SizedBox(height: 18),
        _sheetEyebrow('Categories'),
        const SizedBox(height: 10),
        _CategoryChips(selected: cats, onToggle: _toggleCat),
        const SizedBox(height: 18),
        _SettingToggleRow(
          title: 'Custom questions',
          subtitle: 'Members can queue their own',
          value: customEnabled,
          onChanged: (next) => setState(() => customEnabled = next),
        ),
        const SizedBox(height: 12),
        _SettingToggleRow(
          title: 'Reveal answers by default',
          subtitle: 'Sets the starting choice; each member can change it later',
          value: revealAnswers,
          onChanged: (next) => setState(() => revealAnswers = next),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: v2Sans(13, color: RtwV2Colors.danger)),
        ],
        const SizedBox(height: 18),
        V2Button(
          submitting ? 'Creating…' : 'Create room & invite',
          onPressed: submitting ? null : _submit,
          padding: const EdgeInsets.symmetric(vertical: 16),
          radius: 16,
        ),
      ],
    );
  }
}

class _TierSegment extends StatelessWidget {
  const _TierSegment({required this.value, required this.onChanged});

  final RoomTier value;
  final ValueChanged<RoomTier> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: RtwV2Colors.hairline,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final tier in RoomTier.values) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tier),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == tier ? RtwV2Colors.inkSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    tier.label,
                    style: v2Sans(
                      14,
                      color: value == tier ? Colors.white : RtwV2Colors.subText,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            if (tier != RoomTier.values.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onToggle});

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final allOn = selected.contains('All');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final cat in ['All', ...roomCategoryOptions])
          Builder(builder: (context) {
            final on = cat == 'All' ? allOn : (!allOn && selected.contains(cat));
            return GestureDetector(
              onTap: () => onToggle(cat),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? RtwV2Colors.blue.withValues(alpha: 0.10) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: on ? RtwV2Colors.blue : RtwV2Colors.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  cat,
                  style: v2Sans(
                    13,
                    color: on ? RtwV2Colors.blueTextDeep : RtwV2Colors.subText,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _SettingToggleRow extends StatelessWidget {
  const _SettingToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: v2Sans(15, color: RtwV2Colors.inkSoft, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: v2Sans(12, color: RtwV2Colors.faint)),
              ],
            ),
          ),
          V2Toggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ── JOIN ROOM (with pre-join preview + After Dark consent) ─────────────

Future<void> showJoinRoomSheet(BuildContext context, WidgetRef ref) {
  return showV2Sheet(context, (context) => _JoinRoomSheet(ref: ref));
}

class _JoinRoomSheet extends StatefulWidget {
  const _JoinRoomSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends State<_JoinRoomSheet> {
  final codeController = TextEditingController();
  Map<String, dynamic>? preview;
  bool busy = false;
  String? error;

  Future<void> _lookupOrJoin() async {
    final code = codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (preview == null) {
        final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('joinRoom')
            .call({'code': code, 'previewOnly': true});
        if (!mounted) return;
        setState(() {
          preview = Map<String, dynamic>.from(result.data as Map);
          busy = false;
        });
        return;
      }
      final tier = preview!['tier']?.toString() ?? 'normal';
      if (tier == 'mature') {
        final confirmed = await showMatureConfirmSheet(context);
        if (confirmed != true || !mounted) {
          setState(() => busy = false);
          return;
        }
      }
      final rooms = widget.ref.read(roomsControllerProvider);
      final roomId = await rooms.joinRoom(code);
      if (!mounted) return;
      if (roomId == null) {
        setState(() {
          busy = false;
          error = rooms.lastError ?? 'Could not join that room.';
        });
        return;
      }
      Navigator.of(context).pop();
      context.go('/rooms/$roomId');
    } on FirebaseFunctionsException catch (functionsError) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = functionsError.message ?? functionsError.code;
      });
    } catch (genericError) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = genericError.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewTier = RoomTierWire.parse(preview?['tier']?.toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetEyebrow('Join a room'),
        _sheetTitle('Got an invite code?'),
        _sheetBody('Enter the code a friend shared, or open their link to join instantly.'),
        const SizedBox(height: 18),
        TextField(
          controller: codeController,
          textCapitalization: TextCapitalization.characters,
          style: v2Mono(16, color: RtwV2Colors.inkSoft, letterSpacing: 1),
          decoration: _inputDecoration('e.g. STUDIO-7F2'),
          onChanged: (_) {
            if (preview != null) setState(() => preview = null);
          },
        ),
        if (preview != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: RtwV2Colors.card,
              border: Border.all(color: RtwV2Colors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: RtwV2Colors.roomColor(preview!['color']?.toString()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    (preview!['name']?.toString() ?? '?').substring(0, 1),
                    style: v2Serif(18, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(preview!['name']?.toString() ?? 'Room', style: v2Serif(17)),
                      const SizedBox(height: 1),
                      Text.rich(
                        TextSpan(
                          text: '${preview!['memberCount'] ?? 0} members',
                          style: v2Sans(12, color: RtwV2Colors.muted),
                          children: [
                            if (previewTier != RoomTier.normal)
                              TextSpan(
                                text: ' · ${previewTier.label}',
                                style: v2Sans(
                                  12,
                                  color: previewTier == RoomTier.mature
                                      ? RtwV2Colors.clay
                                      : RtwV2Colors.green,
                                  weight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: v2Sans(13, color: RtwV2Colors.danger)),
        ],
        const SizedBox(height: 14),
        V2Button(
          busy
              ? 'One moment…'
              : preview == null
                  ? 'Find room'
                  : preview!['alreadyMember'] == true
                      ? 'Open room'
                      : 'Join room',
          onPressed: busy
              ? null
              : preview?['alreadyMember'] == true
                  ? () {
                      final roomId = preview!['roomId']?.toString() ?? '';
                      Navigator.of(context).pop();
                      context.go('/rooms/$roomId');
                    }
                  : _lookupOrJoin,
          padding: const EdgeInsets.symmetric(vertical: 16),
          radius: 16,
        ),
      ],
    );
  }
}

// ── INVITE ──────────────────────────────────────────────────────────────

Future<void> showInviteSheet(
  BuildContext context,
  RoomsController rooms,
  String roomId,
) {
  final room = rooms.bindingFor(roomId)?.room;
  final code = room?.inviteCode;
  return showV2Sheet(context, (context) => _InviteSheet(code: code));
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.code});

  final String? code;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  bool copied = false;

  String get _link => 'https://$_shortLinkHost/${widget.code ?? ''}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetEyebrow('Invite friends'),
        _sheetTitle('Bring your people in.'),
        _sheetBody(
          'They join your room and your leaderboard, and every new player gets '
          'the World Room closer to unlocking for everyone.',
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          decoration: BoxDecoration(
            color: RtwV2Colors.card,
            border: Border.all(color: RtwV2Colors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$_shortLinkHost/${widget.code ?? '…'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: v2Mono(14, color: const Color(0xFF5C584F), letterSpacing: 0.5),
                ),
              ),
              GestureDetector(
                onTap: widget.code == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: _link));
                        if (mounted) setState(() => copied = true);
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: RtwV2Colors.inkSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    copied ? 'Copied ✓' : 'Copy',
                    style: v2Sans(13, color: Colors.white, weight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        V2Button(
          'Share invite link',
          onPressed: widget.code == null
              ? null
              : () => SharePlus.instance.share(
                    ShareParams(text: 'Join my room on Read the World: $_link'),
                  ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          radius: 16,
        ),
      ],
    );
  }
}

// ── AFTER DARK CONSENT ─────────────────────────────────────────────────

Future<bool?> showMatureConfirmSheet(BuildContext context) {
  return showV2Sheet<bool>(context, (context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetEyebrow('After Dark', color: RtwV2Colors.clay),
        _sheetTitle('This room runs After Dark.'),
        _sheetBody('Still words-only, just edgier than the usual. You can leave the room anytime.'),
        const SizedBox(height: 18),
        V2Button(
          'Join anyway',
          onPressed: () => Navigator.of(context).pop(true),
          padding: const EdgeInsets.symmetric(vertical: 16),
          radius: 16,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Not now',
              style: v2Sans(14, color: RtwV2Colors.subText, weight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  });
}

// ── FLAG QUESTION ──────────────────────────────────────────────────────

Future<void> showFlagSheet(
  BuildContext context,
  RoomsController rooms,
  String roomId,
  String qid,
) {
  return showV2Sheet(context, (context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetEyebrow('Flag question', color: RtwV2Colors.danger),
        _sheetTitle('Remove this for today?'),
        _sheetBody(
          'One flag pulls a custom question for the whole room today, no '
          'questions asked. The author is notified.',
        ),
        const SizedBox(height: 18),
        V2Button(
          'Flag & remove for everyone',
          background: RtwV2Colors.danger,
          onPressed: () async {
            Navigator.of(context).pop();
            await rooms.flagQuestion(roomId, qid);
          },
          padding: const EdgeInsets.symmetric(vertical: 16),
          radius: 16,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: v2Sans(14, color: RtwV2Colors.subText, weight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  });
}

// ── CUSTOM QUESTION QUEUE ──────────────────────────────────────────────

Future<void> showCustomQSheet(
  BuildContext context,
  RoomsController rooms,
  String roomId,
) {
  return showV2Sheet(context, (context) => _CustomQSheet(rooms: rooms, roomId: roomId));
}

class _CustomQSheet extends StatefulWidget {
  const _CustomQSheet({required this.rooms, required this.roomId});

  final RoomsController rooms;
  final String roomId;

  @override
  State<_CustomQSheet> createState() => _CustomQSheetState();
}

class _CustomQSheetState extends State<_CustomQSheet> {
  final draftController = TextEditingController();
  final optAController = TextEditingController();
  final optBController = TextEditingController();
  bool busy = false;

  Future<void> _add() async {
    final text = draftController.text.trim();
    if (text.isEmpty) return;
    setState(() => busy = true);
    final ok = await widget.rooms.queueCustomQuestion(
      widget.roomId,
      text,
      optAController.text.trim().isEmpty ? 'Yes' : optAController.text.trim(),
      optBController.text.trim().isEmpty ? 'No' : optBController.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      draftController.clear();
      optAController.clear();
      optBController.clear();
    }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final roomName = widget.rooms.bindingFor(widget.roomId)?.room?.name ?? 'Room';
    final myUid = widget.rooms.uid;
    return StreamBuilder<List<QueueItem>>(
      stream: widget.rooms.queueStream(widget.roomId),
      builder: (context, snapshot) {
        final queue = snapshot.data ?? const <QueueItem>[];
        final mine = queue.where((item) => item.authorUid == myUid).toList();
        final full = queue.length >= 10;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetEyebrow('Custom questions'),
            _sheetTitle(roomName),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Adding your own is completely optional. Anything you queue is '
                'shuffled in anonymously, so your name only shows once a '
                'question goes live.',
                style: v2Sans(13.5, color: RtwV2Colors.subText, height: 1.55),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _sheetEyebrow('In the queue'),
                Text(
                  '${queue.length} of 10',
                  style: v2Sans(13, color: const Color(0xFF3F3C35), weight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < 10; i++) ...[
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i < queue.length
                            ? RtwV2Colors.blue
                            : const Color(0xFFE6E0D3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (i < 9) const SizedBox(width: 4),
                ],
              ],
            ),
            if (mine.isNotEmpty) ...[
              const SizedBox(height: 22),
              _sheetEyebrow('Your submissions'),
              const SizedBox(height: 10),
              for (final item in mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: RtwV2Colors.card,
                                border: Border.all(color: RtwV2Colors.borderStrong),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(item.text, style: v2Sans(14, color: RtwV2Colors.inkSoft)),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 5, left: 2),
                              child: Text(
                                '${item.optA} / ${item.optB}',
                                style: v2Mono(10, color: RtwV2Colors.faint, letterSpacing: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => widget.rooms.deleteCustomQuestion(widget.roomId, item.id),
                        child: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: RtwV2Colors.card,
                            border: Border.all(color: RtwV2Colors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('×', style: v2Sans(17, color: RtwV2Colors.danger)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 18),
            if (full)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: RtwV2Colors.hairline,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  "The queue's full. Space opens up as today's questions get used.",
                  style: v2Sans(13, color: RtwV2Colors.muted, height: 1.5),
                ),
              )
            else ...[
              _sheetEyebrow('Add a question'),
              const SizedBox(height: 10),
              TextField(
                controller: draftController,
                style: v2Sans(15, color: RtwV2Colors.inkSoft),
                decoration: _inputDecoration('Write your question…'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: optAController,
                      style: v2Sans(14, color: RtwV2Colors.inkSoft),
                      decoration: _inputDecoration('Option A'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: optBController,
                      style: v2Sans(14, color: RtwV2Colors.inkSoft),
                      decoration: _inputDecoration('Option B'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Two answers, like Yes / No or Good / Bad. Photos and GIFs coming soon.',
                style: v2Sans(11.5, color: RtwV2Colors.faint, height: 1.45),
              ),
              const SizedBox(height: 12),
              V2Button(
                busy ? 'Adding…' : 'Add to queue',
                onPressed: busy ? null : _add,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ],
            _ghostDoneButton(context),
          ],
        );
      },
    );
  }
}

// ── ROOM MENU ──────────────────────────────────────────────────────────

Future<void> showRoomMenuSheet(
  BuildContext context,
  WidgetRef ref,
  String roomId, {
  required VoidCallback onHistory,
}) {
  return showV2Sheet(context, (context) {
    return Consumer(builder: (context, ref, _) {
      final rooms = ref.watch(roomsControllerProvider);
      final binding = rooms.bindingFor(roomId);
      final room = binding?.room;
      final isCreator = binding?.me?.isCreator ?? false;
      final revealMine = binding?.me?.revealMine ?? false;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetEyebrow('Room'),
          _sheetTitle(room?.name ?? 'Room'),
          const SizedBox(height: 18),
          _SettingToggleRow(
            title: 'Show my answers',
            subtitle: 'Let the room see your picks on the reveal',
            value: revealMine,
            onChanged: (next) => rooms.setAnswerVisibility(roomId, next),
          ),
          const SizedBox(height: 14),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: RtwV2Colors.card,
              border: Border.all(color: RtwV2Colors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _MenuRow(
                  label: 'Room history',
                  onTap: () {
                    Navigator.of(context).pop();
                    onHistory();
                  },
                ),
                if (isCreator && room?.isWorld != true) ...[
                  const V2Hairline(),
                  _MenuRow(
                    label: 'Room settings',
                    onTap: () {
                      Navigator.of(context).pop();
                      showRoomSettingsSheet(context, ref, roomId);
                    },
                  ),
                ],
                if (room?.isWorld != true) ...[
                  const V2Hairline(),
                  _MenuRow(
                    label: 'Leave room',
                    color: RtwV2Colors.danger,
                    onTap: () async {
                      final rooms = ref.read(roomsControllerProvider);
                      final ok = await rooms.leaveRoom(roomId);
                      if (ok && context.mounted) {
                        Navigator.of(context).pop();
                        context.go('/rooms');
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          _ghostDoneButton(context),
        ],
      );
    });
  });
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.onTap,
    this.color = RtwV2Colors.inkSoft,
    this.trailing,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: v2Sans(15, color: color)),
            Text(
              trailing ?? '›',
              style: trailing != null
                  ? v2Mono(13, color: RtwV2Colors.muted)
                  : v2Sans(16, color: RtwV2Colors.faint),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ROOM SETTINGS (creator only) ───────────────────────────────────────

Future<void> showRoomSettingsSheet(BuildContext context, WidgetRef ref, String roomId) {
  return showV2Sheet(context, (context) => _RoomSettingsSheet(ref: ref, roomId: roomId));
}

class _RoomSettingsSheet extends StatefulWidget {
  const _RoomSettingsSheet({required this.ref, required this.roomId});

  final WidgetRef ref;
  final String roomId;

  @override
  State<_RoomSettingsSheet> createState() => _RoomSettingsSheetState();
}

class _RoomSettingsSheetState extends State<_RoomSettingsSheet> {
  late final RoomsController rooms = widget.ref.read(roomsControllerProvider);
  late final TextEditingController nameController;
  late RoomTier tier;
  late String colorToken;
  late List<String> cats;

  RtwRoom? get room => rooms.bindingFor(widget.roomId)?.room;

  @override
  void initState() {
    super.initState();
    final current = room;
    nameController = TextEditingController(text: current?.name ?? '');
    tier = current?.tier ?? RoomTier.normal;
    colorToken = current?.colorToken ?? RtwV2Colors.roomColorByToken.keys.elementAt(2);
    cats = [...(current?.cats ?? const ['All'])];
  }

  void _toggleCat(String cat) {
    setState(() {
      if (cat == 'All') {
        cats = ['All'];
        return;
      }
      var next = cats.where((c) => c != 'All').toList();
      next = next.contains(cat)
          ? next.where((c) => c != cat).toList()
          : [...next, cat];
      cats = next.isEmpty ? ['All'] : next;
    });
  }

  Future<void> _save() async {
    await rooms.updateRoomSettings(
      widget.roomId,
      name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
      tier: tier,
      colorToken: colorToken,
      cats: cats,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final binding = rooms.bindingFor(widget.roomId);
    final today = binding?.today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetEyebrow('Room settings'),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            "Changes to topics and tier apply to tomorrow's questions.",
            style: v2Sans(12.5, color: RtwV2Colors.faint, height: 1.45),
          ),
        ),
        const SizedBox(height: 18),
        _sheetEyebrow('Room name'),
        const SizedBox(height: 8),
        TextField(
          controller: nameController,
          style: v2Sans(16, color: RtwV2Colors.inkSoft),
          decoration: _inputDecoration('Room name'),
        ),
        const SizedBox(height: 18),
        _sheetEyebrow('Icon colour'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final entry in RtwV2Colors.roomColorByToken.entries) ...[
              GestureDetector(
                onTap: () => setState(() => colorToken = entry.key),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: entry.value,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: colorToken == entry.key ? RtwV2Colors.card : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: colorToken == entry.key
                        ? [BoxShadow(color: entry.value, spreadRadius: 2)]
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 18),
        _sheetEyebrow('Safety tier'),
        const SizedBox(height: 10),
        _TierSegment(value: tier, onChanged: (next) => setState(() => tier = next)),
        const SizedBox(height: 18),
        _sheetEyebrow('Categories'),
        const SizedBox(height: 10),
        _CategoryChips(selected: cats, onToggle: _toggleCat),
        if (today != null && today.questions.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sheetEyebrow("Today's questions"),
          const SizedBox(height: 10),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: RtwV2Colors.card,
              border: Border.all(color: RtwV2Colors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final question in today.questions) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            question.prompt,
                            style: v2Sans(
                              13.5,
                              color: question.pulled ? RtwV2Colors.faint : RtwV2Colors.inkSoft,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        V2Toggle(
                          value: !question.pulled,
                          trackWidth: 44,
                          trackHeight: 26,
                          onChanged: (enabled) => rooms.setRoomQuestionEnabled(
                            widget.roomId,
                            question.qid,
                            enabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (question != today.questions.last) const V2Hairline(),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RtwV2Colors.card,
            border: Border.all(color: RtwV2Colors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              StreamBuilder<List<QueueItem>>(
                stream: rooms.queueStream(widget.roomId),
                builder: (context, snapshot) => _MenuRow(
                  label: 'Custom questions',
                  trailing: '${snapshot.data?.length ?? 0} in queue ›',
                  onTap: () => showCustomQSheet(context, rooms, widget.roomId),
                ),
              ),
              const V2Hairline(),
              _MenuRow(
                label: 'Invite members',
                onTap: () => showInviteSheet(context, rooms, widget.roomId),
              ),
              const V2Hairline(),
              _MenuRow(
                label: 'Delete room',
                color: RtwV2Colors.danger,
                onTap: () async {
                  final confirmed = await showV2Sheet<bool>(context, (context) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sheetEyebrow('Delete room', color: RtwV2Colors.danger),
                        _sheetTitle('Delete ${room?.name ?? 'this room'}?'),
                        _sheetBody(
                          'This removes the room, its history, and its '
                          'leaderboard for every member. There is no undo.',
                        ),
                        const SizedBox(height: 18),
                        V2Button(
                          'Delete for everyone',
                          background: RtwV2Colors.danger,
                          onPressed: () => Navigator.of(context).pop(true),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          radius: 16,
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(
                              'Keep the room',
                              style: v2Sans(14, color: RtwV2Colors.subText, weight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    );
                  });
                  if (confirmed == true) {
                    final ok = await rooms.deleteRoom(widget.roomId);
                    if (ok && context.mounted) {
                      Navigator.of(context).pop();
                      context.go('/rooms');
                    }
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        V2Button(
          'Save & close',
          onPressed: _save,
          padding: const EdgeInsets.symmetric(vertical: 15),
          radius: 16,
        ),
      ],
    );
  }
}
