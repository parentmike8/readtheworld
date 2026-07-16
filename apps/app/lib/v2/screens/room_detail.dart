import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../sheets/room_sheets.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';
import 'play_surface.dart' show revealLabelFor;

/// ROOM DETAIL — v2 prototype lines 153-264.
class RoomDetailScreen extends ConsumerStatefulWidget {
  const RoomDetailScreen({super.key, required this.roomId, this.edit = false});

  final String roomId;

  /// Deep-linked from the "someone joined, update your predictions?" push
  /// (route `/rooms/:id?edit=1`) — drops the reader straight into editing.
  final bool edit;

  @override
  ConsumerState<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends ConsumerState<RoomDetailScreen> {
  RoomRevealData? reveal;
  String? _attemptedRevealKey;
  bool _loadingReveal = false;
  bool _autoEditDone = false;

  /// Once the room and the caller's live answer have streamed in, open the
  /// play surface pre-loaded with their picks so they can revise.
  void _maybeAutoEdit(RoomsController rooms, RtwRoom room) {
    if (!widget.edit || _autoEditDone) return;
    final day = room.isWorld
        ? rooms.worldToday
        : rooms.bindingFor(room.id)?.today;
    final answer = rooms.bindingFor(room.id)?.myTodayAnswer;
    if (day == null || !day.isLive || answer == null) return;
    _autoEditDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      rooms.startRoomPlay(room.id);
      if (rooms.play != null) context.go('/today/play');
    });
  }

  Future<void> _loadReveal(String dailyKey) async {
    _loadingReveal = true;
    _attemptedRevealKey = dailyKey;
    final rooms = ref.read(roomsControllerProvider);
    final data = await rooms.loadRoomReveal(widget.roomId);
    _loadingReveal = false;
    if (mounted) setState(() => reveal = data);
  }

  /// The room doc streams in after first build — load the reveal once its
  /// lastClosedDailyKey is known, and reload when a rollover changes it.
  void _syncReveal(RtwRoom room) {
    final lastClosed = room.lastClosedDailyKey;
    if (lastClosed == null || _loadingReveal) return;
    if (_attemptedRevealKey == lastClosed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadReveal(lastClosed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsControllerProvider);
    final binding = rooms.bindingFor(widget.roomId);
    final room = binding?.room;
    if (room == null) {
      // Only bounce to /rooms for a genuinely unknown room. A room you're in
      // (binding present) or The World may have room==null for a frame right
      // after navigation while its doc streams — show a spinner, don't bounce.
      // (That brief bounce was why exits/backs kept landing on Rooms.)
      final isWorldRoom = widget.roomId == worldRoomId;
      final known =
          isWorldRoom ||
          binding != null ||
          rooms.roomOrder.contains(widget.roomId);
      if (!rooms.loadingRooms && !known) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/rooms');
        });
      }
      return V2Scaffold(
        location: '/rooms/${widget.roomId}',
        wideWidth: 760,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    _syncReveal(room);
    _maybeAutoEdit(rooms, room);
    final me = binding!.me;
    final played = binding.played;
    final isSolo = room.isSolo;
    final isWorld = room.isWorld;
    final hasBoard = !isSolo && !isWorld;

    return V2Scaffold(
      location: '/rooms/${widget.roomId}',
      wideWidth: 760,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 54, 22, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                V2BackButton(
                  label: 'Rooms',
                  onTap: () =>
                      context.canPop() ? context.pop() : context.go('/rooms'),
                ),
                GestureDetector(
                  onTap: () => showRoomMenuSheet(
                    context,
                    ref,
                    widget.roomId,
                    onHistory: () => _showHistorySheet(context, rooms, room),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: RtwV2Colors.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                RoomIcon(room: room, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: v2Serif(26, letterSpacing: -0.4),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (!isWorld && room.tier != RoomTier.normal) ...[
                            TierChip(tier: room.tier),
                            const SizedBox(width: 9),
                          ],
                          Text(
                            isWorld
                                ? '${_thousands(room.memberCount)} players answering'
                                : isSolo
                                ? 'Just you, for now'
                                : '${room.memberCount} members',
                            style: v2Sans(13, color: RtwV2Colors.muted),
                          ),
                          if (hasBoard) ...[
                            const SizedBox(width: 9),
                            Container(
                              width: 1,
                              height: 11,
                              color: const Color(0xFFD8D2C5),
                            ),
                            const SizedBox(width: 9),
                            Text(
                              'RANK #${me?.rank ?? '—'}',
                              style: v2Mono(
                                11,
                                color: RtwV2Colors.muted,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (!played)
              _PlayCard(room: room, rooms: rooms)
            else
              _PlayedCard(
                room: room,
                rooms: rooms,
                canModify: binding.today?.isLive ?? false,
              ),
            const SizedBox(height: 26),
            if (isSolo)
              _SoloNudge(
                onInvite: () => showInviteSheet(context, rooms, room.id),
              )
            else if (isWorld)
              _WorldProgressCard(room: room, rooms: rooms)
            else
              _ScoreCard(room: room, me: me),
            if (!isWorld && room.customEnabled) ...[
              const SizedBox(height: 16),
              _AddQuestionButton(rooms: rooms, roomId: room.id),
            ],
            if (!isWorld &&
                reveal != null &&
                (reveal!.myAnswer?.picks.isNotEmpty ?? false)) ...[
              const SizedBox(height: 24),
              V2Eyebrow(
                revealLabelFor(reveal!.dailyKey),
                size: 11,
                letterSpacing: 1.6,
              ),
              const SizedBox(height: 11),
              for (final question in reveal!.day.activeQuestions) ...[
                _YesterdayCard(
                  question: question,
                  day: reveal!.day,
                  answer: reveal!.myAnswer,
                  onTap: () => showQuestionDetailSheet(
                    context,
                    rooms,
                    roomId: room.id,
                    dailyKey: reveal!.dailyKey,
                    question: question,
                    day: reveal!.day,
                  ),
                ),
                const SizedBox(height: 11),
              ],
            ],
            if (hasBoard) ...[
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const V2Eyebrow(
                    'Room leaderboard',
                    size: 11,
                    letterSpacing: 1.6,
                  ),
                  GestureDetector(
                    onTap: () => showInviteSheet(context, rooms, room.id),
                    child: Text(
                      'Invite +',
                      style: v2Sans(
                        13,
                        color: RtwV2Colors.blue,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              _Leaderboard(rooms: rooms, roomId: room.id, myUid: rooms.uid),
            ],
          ],
        ),
      ),
    );
  }

  void _showHistorySheet(
    BuildContext context,
    RoomsController rooms,
    RtwRoom room,
  ) {
    // The World answers from history, so it needs a route (push/pop) rather
    // than a sheet; regular rooms are review-only and keep the sheet.
    if (room.isWorld) {
      context.push('/rooms/${room.id}/history');
    } else {
      showRoomHistorySheet(context, rooms, room);
    }
  }
}

String _thousands(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

class _PlayCard extends StatelessWidget {
  const _PlayCard({required this.room, required this.rooms});

  final RtwRoom room;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final playCopy = room.isSolo
        ? null
        : room.isWorld
        ? 'Call each one, then predict the world.'
        : 'Call each one, then predict the room.';
    const cta = 'Play →';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: RtwV2Colors.blue,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V2Eyebrow(
            'Today · 3 questions',
            color: const Color(0xFFB8D3F9),
            letterSpacing: 1.6,
          ),
          const SizedBox(height: 10),
          Text(
            'Can you read the room today?',
            style: v2Serif(
              27,
              color: Colors.white,
              height: 1.1,
              letterSpacing: -0.4,
            ),
          ),
          SizedBox(height: playCopy == null ? 24 : 9),
          if (playCopy != null) ...[
            Text(
              playCopy,
              style: v2Sans(14, color: const Color(0xFFD8E6F9), height: 1.5),
            ),
            const SizedBox(height: 18),
          ],
          V2Button(
            cta,
            background: Colors.white,
            foreground: const Color(0xFF244D82),
            fontWeight: FontWeight.w700,
            fontSize: 16,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onPressed: () {
              rooms.startRoomPlay(room.id);
              if (rooms.play != null) context.go('/today/play');
            },
          ),
        ],
      ),
    );
  }
}

class _PlayedCard extends StatelessWidget {
  const _PlayedCard({
    required this.room,
    required this.rooms,
    required this.canModify,
  });

  final RtwRoom room;
  final RoomsController rooms;
  final bool canModify;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check, size: 14, color: RtwV2Colors.green),
              const SizedBox(width: 8),
              const V2Eyebrow('All 3 answered', letterSpacing: 1.6),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Answers in for today.',
            style: v2Serif(26, height: 1.1, letterSpacing: -0.4),
          ),
          const SizedBox(height: 9),
          Text(
            "Editable until tomorrow's reveal.",
            style: v2Sans(14, color: RtwV2Colors.subText, height: 1.5),
          ),
          if (canModify) ...[
            const SizedBox(height: 18),
            V2Button(
              'Review answers',
              background: RtwV2Colors.card,
              foreground: RtwV2Colors.inkSoft,
              border: const BorderSide(color: RtwV2Colors.borderStrong),
              fontWeight: FontWeight.w700,
              fontSize: 15,
              padding: const EdgeInsets.symmetric(vertical: 15),
              onPressed: () => context.push('/rooms/${room.id}/review'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SoloNudge extends StatelessWidget {
  const _SoloNudge({required this.onInvite});

  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const V2Eyebrow('Solo for now', letterSpacing: 1.6),
          const SizedBox(height: 8),
          Text(
            'Invite at least one person to turn on predicting and your Read Score.',
            style: v2Sans(14, color: const Color(0xFF5C584F), height: 1.5),
          ),
          const SizedBox(height: 14),
          V2Button(
            'Invite someone in →',
            fontSize: 14,
            padding: const EdgeInsets.symmetric(vertical: 13),
            radius: 13,
            onPressed: onInvite,
          ),
        ],
      ),
    );
  }
}

class _WorldProgressCard extends StatelessWidget {
  const _WorldProgressCard({required this.room, required this.rooms});

  final RtwRoom room;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final pct = room.worldGoal > 0
        ? ((room.memberCount / room.worldGoal) * 100).round()
        : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  text: _thousands(room.memberCount),
                  style: v2Serif(22),
                  children: [
                    TextSpan(
                      text: ' / ${_thousands(room.worldGoal)} players',
                      style: v2Serif(13, color: RtwV2Colors.muted),
                    ),
                  ],
                ),
              ),
              Text(
                '$pct%',
                style: v2Mono(11, color: RtwV2Colors.blue, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 7,
              color: const Color(0xFFE6E0D3),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (pct / 100).clamp(0.0, 1.0),
                child: Container(color: RtwV2Colors.blue),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Predicting turns on once the game hits ${_thousands(room.worldGoal)} '
            'players and a question crosses 1,000 answers.',
            style: v2Sans(13, color: RtwV2Colors.subText, height: 1.5),
          ),
          const SizedBox(height: 6),
          _WorldLink(
            label: 'Browse other world questions',
            onTap: () => context.push('/rooms/${room.id}/history'),
          ),
        ],
      ),
    );
  }
}

/// Full-width tappable text link — the bare text alone was too small a target.
class _WorldLink extends StatelessWidget {
  const _WorldLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: V2ArrowLabel(
          label,
          color: RtwV2Colors.blue,
          fontSize: 13.5,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.room, required this.me});

  final RtwRoom room;
  final RtwRoomMember? me;

  @override
  Widget build(BuildContext context) {
    final delta = me?.lastDelta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: RtwV2Colors.ink,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const V2Eyebrow(
                'Your read score',
                color: Color(0xFF8E887C),
                letterSpacing: 1.6,
              ),
              const SizedBox(height: 6),
              Text(
                _thousands(me?.roomScore ?? 1500),
                style: v2Serif(36, color: RtwV2Colors.onDarkPaper, height: 1),
              ),
            ],
          ),
          if (delta != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${delta >= 0 ? '+' : ''}$delta',
                  style: v2Mono(
                    15,
                    color: delta >= 0
                        ? RtwV2Colors.deltaUp
                        : RtwV2Colors.deltaDown,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'FROM ${_whenLabel(me?.lastScoredDailyKey)}',
                  style: v2Mono(
                    9,
                    color: const Color(0xFF8E887C),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _whenLabel(String? dailyKey) {
    final label = revealLabelFor(dailyKey);
    return label.replaceAll("'S REVEAL", '').replaceAll(' REVEAL', '');
  }
}

class _AddQuestionButton extends StatefulWidget {
  const _AddQuestionButton({required this.rooms, required this.roomId});

  final RoomsController rooms;
  final String roomId;

  @override
  State<_AddQuestionButton> createState() => _AddQuestionButtonState();
}

class _AddQuestionButtonState extends State<_AddQuestionButton> {
  // Cached per roomId: creating a fresh stream on every rebuild tears down
  // and re-creates the Firestore listener (visible flicker + wasted reads).
  late Stream<List<QueueItem>> _queueStream = widget.rooms.queueStream(
    widget.roomId,
  );

  @override
  void didUpdateWidget(_AddQuestionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roomId != oldWidget.roomId) {
      _queueStream = widget.rooms.queueStream(widget.roomId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueueItem>>(
      stream: _queueStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        return GestureDetector(
          onTap: () => showCustomQSheet(context, widget.rooms, widget.roomId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: RtwV2Colors.knobTrackOff, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '+',
                      style: v2Sans(17, color: RtwV2Colors.blue, height: 1),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'Add your own question',
                      style: v2Sans(
                        14,
                        color: const Color(0xFF5C584F),
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$count in the pool',
                  style: v2Mono(11, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _YesterdayCard extends StatelessWidget {
  const _YesterdayCard({
    required this.question,
    required this.day,
    required this.answer,
    required this.onTap,
  });

  final RoomDayQuestion question;
  final RoomDay day;
  final RoomAnswer? answer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final result = day.resultFor(question.qid);
    final pick = answer?.pickFor(question.qid);
    if (result == null || pick == null) return const SizedBox.shrink();
    final youLabel = pick.side == 'a' ? question.optA : question.optB;
    // "Room X%" = share of the room on YOUR side (matches the prototype rows).
    final roomPct = pick.side == 'a' ? result.aPct : 100 - result.aPct;
    final guess = pick.prediction;
    final score = answer?.accuracies[question.qid];

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                if (score != null)
                  Text.rich(
                    TextSpan(
                      text: '$score',
                      style: v2Mono(
                        11,
                        color: RtwV2Colors.clay,
                        letterSpacing: 0,
                      ),
                      children: [
                        TextSpan(
                          text: '/100',
                          style: v2Mono(
                            11,
                            color: const Color(0xFFBCB6A8),
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              question.prompt,
              style: v2Serif(18, color: const Color(0xFF2C2A24), height: 1.28),
            ),
            if (question.custom) ...[
              const SizedBox(height: 6),
              Text(
                'SUBMITTED BY ${(question.authorName ?? 'A ROOM MEMBER').toUpperCase()}',
                style: v2Mono(9, color: RtwV2Colors.muted, letterSpacing: 1),
              ),
            ],
            const SizedBox(height: 13),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: const Color(0xFFE6E0D3)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (roomPct / 100).clamp(0.0, 1.0),
                        child: Container(color: RtwV2Colors.clay),
                      ),
                    ),
                    if (guess != null)
                      Align(
                        alignment: Alignment(
                          (guess / 100).clamp(0.0, 1.0) * 2 - 1,
                          0,
                        ),
                        child: Container(width: 2, color: RtwV2Colors.blue),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text.rich(
                  TextSpan(
                    text: 'You said ',
                    style: v2Sans(12, color: RtwV2Colors.subText),
                    children: [
                      TextSpan(
                        text: youLabel,
                        style: v2Sans(
                          12,
                          color: RtwV2Colors.blue,
                          weight: FontWeight.w700,
                        ),
                      ),
                      if (guess != null) TextSpan(text: ' · guessed $guess%'),
                    ],
                  ),
                ),
                Text(
                  'Room $roomPct%',
                  style: v2Sans(12, color: RtwV2Colors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Leaderboard extends StatefulWidget {
  const _Leaderboard({
    required this.rooms,
    required this.roomId,
    required this.myUid,
  });

  final RoomsController rooms;
  final String roomId;
  final String? myUid;

  @override
  State<_Leaderboard> createState() => _LeaderboardState();
}

class _LeaderboardState extends State<_Leaderboard> {
  // Cached per roomId: creating a fresh stream on every rebuild tears down
  // and re-creates the Firestore listener (visible flicker + wasted reads).
  late Stream<List<RtwRoomMember>> _membersStream = widget.rooms.membersStream(
    widget.roomId,
  );

  @override
  void didUpdateWidget(_Leaderboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roomId != oldWidget.roomId) {
      _membersStream = widget.rooms.membersStream(widget.roomId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RtwRoomMember>>(
      stream: _membersStream,
      builder: (context, snapshot) {
        final members = snapshot.data ?? const <RtwRoomMember>[];
        if (members.isEmpty) return const SizedBox.shrink();
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RtwV2Colors.card,
            border: Border.all(color: RtwV2Colors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              for (final (index, member) in members.indexed) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  color: member.uid == widget.myUid
                      ? RtwV2Colors.meterBlue.withValues(alpha: 0.08)
                      : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '#${index + 1}',
                          style: v2Mono(13, letterSpacing: 0),
                        ),
                      ),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: member.uid == widget.myUid
                              ? RtwV2Colors.blue
                              : const Color(0xFFD8D2C5),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          member.uid == widget.myUid
                              ? 'You'
                              : member.displayName,
                          style: v2Sans(
                            15,
                            color: RtwV2Colors.inkSoft,
                            weight: member.uid == widget.myUid
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(_thousands(member.roomScore), style: v2Serif(17)),
                    ],
                  ),
                ),
                if (index < members.length - 1) const V2Hairline(),
              ],
            ],
          ),
        );
      },
    );
  }
}
