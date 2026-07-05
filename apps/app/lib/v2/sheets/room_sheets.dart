import 'dart:async';

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
    RoomTier.workSafe: 'Lightest topics, safe for a company or team.',
    RoomTier.normal: 'Everyday questions. Includes work-safe topics.',
    RoomTier.mature: 'Edgier, words-only. Skips the tame stuff.',
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
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final navigatorContext = navigator.context;
    Navigator.of(context).pop();
    router.go('/rooms/$roomId');
    await Future<void>.delayed(Duration.zero);
    if (!navigatorContext.mounted) return;
    await showInviteSheet(navigatorContext, rooms, roomId);
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
        _sheetEyebrow('Spice level'),
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

class _CategoryChips extends StatefulWidget {
  const _CategoryChips({required this.selected, required this.onToggle});

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  State<_CategoryChips> createState() => _CategoryChipsState();
}

class _CategoryChipsState extends State<_CategoryChips> {
  // Most rooms keep 'All' — the full grid only unfolds on request, or when
  // a room already has a narrowed selection to show.
  late bool _expanded = !widget.selected.contains('All');

  Widget _chip(String label, {required bool on, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
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
          label,
          style: v2Sans(
            13,
            color: on ? RtwV2Colors.blueTextDeep : RtwV2Colors.subText,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allOn = widget.selected.contains('All');
    if (!_expanded) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip('All', on: allOn, onTap: () => widget.onToggle('All')),
          _chip(
            'Choose topics →',
            on: false,
            onTap: () => setState(() => _expanded = true),
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final cat in ['All', ...roomCategoryOptions])
          _chip(
            cat,
            on: cat == 'All' ? allOn : (!allOn && widget.selected.contains(cat)),
            onTap: () => widget.onToggle(cat),
          ),
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
        // Persist consent so party mode can serve After Dark too.
        unawaited(widget.ref.read(roomsControllerProvider).markMatureConsent());
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

Future<bool?> showMatureConfirmSheet(BuildContext context, {bool party = false}) {
  return showV2Sheet<bool>(context, (context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetEyebrow('After Dark', color: RtwV2Colors.clay),
        _sheetTitle(party ? 'Turn on After Dark?' : 'This room runs After Dark.'),
        _sheetBody(
          party
              ? 'Still words-only, just edgier than the usual. You can switch back anytime.'
              : 'Still words-only, just edgier than the usual. You can leave the room anytime.',
        ),
        const SizedBox(height: 18),
        V2Button(
          party ? 'Turn it on' : 'Join anyway',
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
                'shuffled into the room. Your name only shows once a '
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
          // "Show my answers" governs whether the room sees your picks on the
          // reveal — meaningless for The World (its reveal is the global split).
          if (room?.isWorld != true) ...[
            _SettingToggleRow(
              title: 'Show my answers',
              subtitle: 'Let the room see your picks on the reveal',
              value: revealMine,
              onChanged: (next) => rooms.setAnswerVisibility(roomId, next),
            ),
            const SizedBox(height: 14),
          ],
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
                      final confirmed = await _confirmLeaveRoom(
                        context,
                        roomName: room?.name ?? 'this room',
                        isCreator: isCreator,
                        isLastMember: (room?.memberCount ?? 0) <= 1,
                      );
                      if (confirmed != true || !context.mounted) return;
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

Future<bool?> _confirmLeaveRoom(
  BuildContext context, {
  required String roomName,
  required bool isCreator,
  required bool isLastMember,
}) {
  final body = isLastMember
      ? 'You are the last member. Leaving will delete this room, its history, and its leaderboard. There is no undo.'
      : isCreator
          ? 'You are the room creator. If you leave, creator status will move to the longest-standing remaining member.'
          : 'You will lose access to this room, its questions, and its leaderboard.';
  return showV2Sheet<bool>(context, (context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetEyebrow('Leave room', color: RtwV2Colors.danger),
        _sheetTitle('Leave $roomName?'),
        _sheetBody(body),
        const SizedBox(height: 18),
        V2Button(
          'Leave room',
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
              'Stay in room',
              style: v2Sans(
                14,
                color: RtwV2Colors.subText,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
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
        _sheetEyebrow('Spice level'),
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

// ── QUESTION DETAIL (per-question leaderboard; prototype qdetail) ───────

Future<void> showQuestionDetailSheet(
  BuildContext context,
  RoomsController rooms, {
  required String roomId,
  required String dailyKey,
  required RoomDayQuestion question,
  required RoomDay day,
}) async {
  final rows = await rooms.loadDayDetail(roomId, dailyKey);
  if (!context.mounted) return;
  final result = day.resultFor(question.qid);
  final sorted = [...rows]..sort(
    (a, b) => (b.accuracies[question.qid] ?? -1).compareTo(a.accuracies[question.qid] ?? -1),
  );
  await showV2Sheet(context, (context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetEyebrow(question.tag, color: RtwV2Colors.clay),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            question.prompt,
            style: v2Serif(24, height: 1.2, letterSpacing: -0.3),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 48,
              child: Stack(
                children: [
                  Container(color: const Color(0xFFE6E0D3)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (result.aPct / 100).clamp(0.0, 1.0),
                      child: Container(color: RtwV2Colors.blue),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Center(
                          child: Text(
                            '${question.optA.toUpperCase()} ${result.aPct}%',
                            style: v2Mono(11, color: RtwV2Colors.card, letterSpacing: 1),
                          ),
                        ),
                        Center(
                          child: Text(
                            question.optB.toUpperCase(),
                            style: v2Mono(11, color: const Color(0xFF7A7466), letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _sheetEyebrow('Who read it best · ${sorted.length} played'),
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
              for (final (index, row) in sorted.indexed) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  color: row.isMe ? RtwV2Colors.meterBlue.withValues(alpha: 0.08) : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text('#${index + 1}', style: v2Mono(13, letterSpacing: 0)),
                      ),
                      Expanded(
                        child: Text(
                          row.isMe ? 'You' : row.displayName,
                          style: v2Sans(15, color: RtwV2Colors.inkSoft, weight: FontWeight.w600),
                        ),
                      ),
                      if (row.reveals &&
                          row.picks.any((pick) => pick.qid == question.qid)) ...[
                        Builder(builder: (context) {
                          final pick =
                              row.picks.firstWhere((pick) => pick.qid == question.qid);
                          final isA = pick.side == 'a';
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isA ? RtwV2Colors.meterBlue : RtwV2Colors.meterClay)
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              isA ? question.optA : question.optB,
                              style: v2Sans(
                                12,
                                color: isA
                                    ? RtwV2Colors.blueTextDeep
                                    : RtwV2Colors.clayTextDeep,
                                weight: FontWeight.w600,
                              ),
                            ),
                          );
                        }),
                        const SizedBox(width: 10),
                      ],
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${row.accuracies[question.qid] ?? '—'}',
                          textAlign: TextAlign.right,
                          style: v2Serif(18),
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < sorted.length - 1) const V2Hairline(),
              ],
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No answers to show.', style: v2Sans(13, color: RtwV2Colors.muted)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Answers show only for members who share them.',
          style: v2Sans(11.5, color: RtwV2Colors.faint, height: 1.45),
        ),
        _ghostDoneButton(context),
      ],
    );
  });
}

// ── ROOM HISTORY (calendar + per-question cards) ────────────────────────

Future<void> showRoomHistorySheet(
  BuildContext context,
  RoomsController rooms,
  RtwRoom room,
) {
  return showV2Sheet(
    context,
    (context) => _RoomHistorySheet(rooms: rooms, room: room),
  );
}

class _RoomHistorySheet extends StatefulWidget {
  const _RoomHistorySheet({required this.rooms, required this.room});

  final RoomsController rooms;
  final RtwRoom room;

  @override
  State<_RoomHistorySheet> createState() => _RoomHistorySheetState();
}

class _RoomHistorySheetState extends State<_RoomHistorySheet> {
  List<RoomHistoryDay>? history;
  String catFilter = 'All';
  DateTime? viewMonth;

  @override
  void initState() {
    super.initState();
    widget.rooms
        .loadRoomHistory(widget.room.id, includeLive: widget.room.isWorld)
        .then((days) {
      if (mounted) setState(() => history = days);
    });
  }

  DateTime _dateOf(RoomHistoryDay entry) =>
      DateTime.tryParse(entry.day.dailyKey) ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final days = history ?? const <RoomHistoryDay>[];
    final tags = <String>{
      for (final entry in days)
        for (final question in entry.day.activeQuestions) question.tag,
    };
    final activeMonth = viewMonth ??
        (days.isEmpty
            ? DateTime.now()
            : DateTime(_dateOf(days.first).year, _dateOf(days.first).month));
    final monthDays = days.where((entry) {
      final date = _dateOf(entry);
      return date.year == activeMonth.year && date.month == activeMonth.month;
    }).toList();
    final entriesByDay = <int, RoomHistoryDay>{
      for (final entry in monthDays) _dateOf(entry).day: entry,
    };
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final firstDow = DateTime(activeMonth.year, activeMonth.month, 1).weekday % 7;
    final daysInMonth = DateTime(activeMonth.year, activeMonth.month + 1, 0).day;

    final cards = <({RoomHistoryDay entry, RoomDayQuestion question})>[
      for (final entry in monthDays)
        for (final question in entry.day.activeQuestions)
          if (catFilter == 'All' || question.tag == catFilter)
            (entry: entry, question: question),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${widget.room.name} history', style: v2Serif(24, letterSpacing: -0.4)),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tag in ['All', ...tags]) ...[
                GestureDetector(
                  onTap: () => setState(() => catFilter = tag),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: catFilter == tag ? RtwV2Colors.blue : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: catFilter == tag ? RtwV2Colors.blue : RtwV2Colors.borderStrong,
                      ),
                    ),
                    child: Text(
                      tag,
                      style: v2Sans(
                        13,
                        color: catFilter == tag ? Colors.white : RtwV2Colors.subText,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: RtwV2Colors.card,
            border: Border.all(color: RtwV2Colors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MonthArrow(
                    label: '‹',
                    onTap: () => setState(() => viewMonth =
                        DateTime(activeMonth.year, activeMonth.month - 1)),
                  ),
                  Text(
                    '${monthNames[activeMonth.month - 1]} ${activeMonth.year}',
                    style: v2Serif(19),
                  ),
                  _MonthArrow(
                    label: '›',
                    onTap: () => setState(() => viewMonth =
                        DateTime(activeMonth.year, activeMonth.month + 1)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                children: [
                  for (final dow in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                    Center(
                      child: Text(
                        dow,
                        style: v2Mono(10, color: const Color(0xFFBCB6A8), letterSpacing: 0),
                      ),
                    ),
                  for (var i = 0; i < firstDow; i++) const SizedBox.shrink(),
                  for (var dayNumber = 1; dayNumber <= daysInMonth; dayNumber++)
                    Builder(builder: (context) {
                      final dayEntry = entriesByDay[dayNumber];
                      final has = dayEntry != null;
                      // Open ring = still has questions you can answer (World);
                      // filled dot = a day you've engaged with.
                      var hasOpen = false;
                      if (has && widget.room.isWorld) {
                        for (final q in dayEntry.day.answerableQuestions) {
                          if (dayEntry.myAnswer?.pickFor(q.qid) == null) {
                            hasOpen = true;
                            break;
                          }
                        }
                      }
                      return Container(
                        decoration: BoxDecoration(
                          color: has
                              ? RtwV2Colors.meterBlue.withValues(alpha: 0.07)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: v2Sans(
                                13,
                                color: has ? RtwV2Colors.inkSoft : const Color(0xFFC3BDAF),
                                weight: has ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: hasOpen
                                    ? Colors.transparent
                                    : (has ? RtwV2Colors.blue : Colors.transparent),
                                border: hasOpen
                                    ? Border.all(color: RtwV2Colors.blue, width: 1.5)
                                    : null,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (history == null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Loading history…', style: v2Sans(14, color: RtwV2Colors.faint)),
            ),
          )
        else if (cards.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 24, 10, 24),
              child: Text('No questions this month.', style: v2Sans(14, color: RtwV2Colors.faint)),
            ),
          )
        else
          for (final card in cards) ...[
            _HistoryQuestionCard(
              entry: card.entry,
              question: card.question,
              isWorld: widget.room.isWorld,
              onReview: () => showQuestionDetailSheet(
                context,
                widget.rooms,
                roomId: widget.room.id,
                dailyKey: card.entry.day.dailyKey,
                question: card.question,
                day: card.entry.day,
              ),
              onAnswer: () {
                widget.rooms.startWorldDayPlay(
                  card.entry,
                  entryRoute: '/rooms/$worldRoomId',
                );
                if (widget.rooms.play != null) {
                  Navigator.of(context).pop();
                  context.go('/today/play');
                }
              },
            ),
            const SizedBox(height: 11),
          ],
        _ghostDoneButton(context),
      ],
    );
  }
}

class _MonthArrow extends StatelessWidget {
  const _MonthArrow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: RtwV2Colors.hairline,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label, style: v2Sans(16, color: const Color(0xFF5C584F))),
      ),
    );
  }
}

class _HistoryQuestionCard extends StatelessWidget {
  const _HistoryQuestionCard({
    required this.entry,
    required this.question,
    required this.isWorld,
    required this.onReview,
    required this.onAnswer,
  });

  final RoomHistoryDay entry;
  final RoomDayQuestion question;
  final bool isWorld;
  final VoidCallback onReview;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    final pick = entry.myAnswer?.pickFor(question.qid);
    final answered = pick != null;
    final revealed =
        isWorld ? entry.day.isRevealed(question.qid) : entry.day.isClosed;
    final canAnswer = isWorld && !revealed && !answered;
    final result = entry.day.resultFor(question.qid);
    final score = entry.myAnswer?.accuracies[question.qid];
    final threshold = question.threshold ?? 1000;
    final answers = entry.day.answerCounts[question.qid] ?? result?.answers ?? 0;
    final showProgress = isWorld && !revealed;
    final pct = (answers / threshold).clamp(0.0, 1.0);

    final youLabel =
        pick == null ? null : (pick.side == 'a' ? question.optA : question.optB);
    final crowdPct = result == null
        ? null
        : (answered
            ? (pick.side == 'a' ? result.aPct : 100 - result.aPct)
            : result.aPct);

    final date = DateTime.tryParse(entry.day.dailyKey);
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final dateLabel =
        date == null ? entry.day.dailyKey : '${months[date.month - 1]} ${date.day}';

    return GestureDetector(
      onTap: canAnswer ? onAnswer : onReview,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: RtwV2Colors.card,
          border: Border.all(color: RtwV2Colors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateLabel, style: v2Mono(10, letterSpacing: 1.3)),
                if (score != null)
                  Text.rich(
                    TextSpan(
                      text: '$score',
                      style: v2Mono(11, color: RtwV2Colors.clay, letterSpacing: 0),
                      children: [
                        TextSpan(
                          text: '/100',
                          style: v2Mono(11, color: const Color(0xFFBCB6A8), letterSpacing: 0),
                        ),
                      ],
                    ),
                  )
                else if (canAnswer)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: RtwV2Colors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      'UNANSWERED',
                      style: v2Mono(9, color: RtwV2Colors.blue, letterSpacing: 1.2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              question.prompt,
              style: v2Serif(18, color: const Color(0xFF2C2A24), height: 1.28),
            ),
            const SizedBox(height: 11),
            if (answered)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 9,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: RtwV2Colors.meterBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      pick.prediction != null
                          ? 'You said $youLabel @ ${pick.prediction}%'
                          : 'You said $youLabel',
                      style: v2Sans(12, color: RtwV2Colors.blue, weight: FontWeight.w600),
                    ),
                  ),
                  if (revealed && crowdPct != null)
                    Text(
                      'Crowd $crowdPct% agreed',
                      style: v2Mono(11, color: RtwV2Colors.subText, letterSpacing: 0),
                    ),
                ],
              )
            else if (revealed && crowdPct != null)
              Text(
                'Crowd $crowdPct% picked ${question.optA}',
                style: v2Sans(12.5, color: RtwV2Colors.subText),
              )
            else if (canAnswer)
              Text(
                'Tap to make your read',
                style: v2Sans(12.5, color: RtwV2Colors.blue, weight: FontWeight.w600),
              ),
            if (showProgress) ...[
              const SizedBox(height: 11),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  height: 6,
                  color: const Color(0xFFE6E0D3),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: pct,
                    child: Container(color: RtwV2Colors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_thousandsSep(answers)} / ${_thousandsSep(threshold)} world answers',
                style: v2Sans(11.5, color: RtwV2Colors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── WORLD BROWSE (recent world questions beyond today) ─────────────────

Future<void> showWorldBrowseSheet(BuildContext context, RoomsController rooms) async {
  final days = await rooms.loadWorldBrowse();
  if (!context.mounted) return;
  await showV2Sheet(context, (context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetEyebrow('More world questions'),
        _sheetTitle('Waiting on the crowd.'),
        _sheetBody(
          "These are outside today's 3. Reveals open as each question "
          'crosses its answer threshold.',
        ),
        const SizedBox(height: 16),
        if (days.isEmpty)
          Text('Nothing here yet.', style: v2Sans(14, color: RtwV2Colors.faint))
        else
          for (final entry in days) ...[
            if (entry.day.answerableQuestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: V2Button(
                  entry.myAnswer == null
                      ? 'Answer these ${entry.day.answerableQuestions.length} →'
                      : 'Update your answers →',
                  fontSize: 14,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  radius: 13,
                  onPressed: () {
                    rooms.startWorldDayPlay(entry);
                    if (rooms.play != null) {
                      Navigator.of(context).pop();
                      context.go('/today/play');
                    }
                  },
                ),
              ),
            for (final question in entry.day.activeQuestions) ...[
              Builder(builder: (context) {
                final revealed = entry.day.isRevealed(question.qid);
                final result = entry.day.resultFor(question.qid);
                final answers = entry.day.answerCounts[question.qid] ??
                    result?.answers ??
                    0;
                final threshold = question.threshold ?? 1000;
                final pick = entry.myAnswer?.pickFor(question.qid);
                final pct = (answers / threshold).clamp(0.0, 1.0);
                return Container(
                  margin: const EdgeInsets.only(bottom: 11),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: RtwV2Colors.card,
                    border: Border.all(color: RtwV2Colors.border),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          V2Eyebrow(question.tag, letterSpacing: 1.2),
                          if (pick != null)
                            Text(
                              'YOU SAID ${(pick.side == 'a' ? question.optA : question.optB).toUpperCase()}',
                              style: v2Mono(10, color: RtwV2Colors.blue, letterSpacing: 1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        question.prompt,
                        style: v2Serif(17, color: const Color(0xFF2C2A24), height: 1.28),
                      ),
                      const SizedBox(height: 12),
                      if (revealed && result != null) ...[
                        Text(
                          '${result.aPct}% ${question.optA} · '
                          '${100 - result.aPct}% ${question.optB}',
                          style: v2Sans(13, color: RtwV2Colors.blue, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Revealed · ${_thousandsSep(answers)} world answers',
                          style: v2Sans(11.5, color: RtwV2Colors.muted),
                        ),
                      ] else ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Container(
                            height: 6,
                            color: const Color(0xFFE6E0D3),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: pct,
                              child: Container(color: RtwV2Colors.blue),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${_thousandsSep(answers)} / ${_thousandsSep(threshold)} world answers',
                          style: v2Sans(11.5, color: RtwV2Colors.muted),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ],
        _ghostDoneButton(context),
      ],
    );
  });
}

String _thousandsSep(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}
