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
  String? _openingYesterdayQuestionId;
  bool _loadingReveal = false;
  bool _autoEditDone = false;

  /// Once the room and the caller's live answer have streamed in, open the
  /// play surface pre-loaded with their picks so they can revise.
  void _maybeAutoEdit(RoomsController rooms, RtwRoom room) {
    if (!widget.edit || _autoEditDone) return;
    _autoEditDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final started = await rooms.startRoomPlay(room.id);
      if (!mounted) return;
      if (started) {
        context.go('/today/play');
      } else {
        _showPlayRefreshError(context, rooms);
      }
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

  Future<void> _openYesterdayQuestion(
    RoomsController rooms,
    RtwRoom room,
    RoomDayQuestion question,
  ) async {
    if (_openingYesterdayQuestionId != null || reveal == null) return;
    setState(() => _openingYesterdayQuestionId = question.qid);
    try {
      await showQuestionDetailSheet(
        context,
        rooms,
        roomId: room.id,
        dailyKey: reveal!.dailyKey,
        question: question,
        day: reveal!.day,
      );
    } finally {
      if (mounted) setState(() => _openingYesterdayQuestionId = null);
    }
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
                  loading: _openingYesterdayQuestionId == question.qid,
                  onTap: _openingYesterdayQuestionId == null
                      ? () => _openYesterdayQuestion(rooms, room, question)
                      : null,
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
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: RtwV2Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Answered today',
                        style: v2Sans(11.5, color: RtwV2Colors.muted),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 13),
              _Leaderboard(
                rooms: rooms,
                roomId: room.id,
                room: room,
                myUid: me?.uid,
                canRemoveMembers: me?.isCreator ?? false,
                onInvite: () => showInviteSheet(context, rooms, room.id),
              ),
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
            rooms.preparingPlay ? 'Refreshing questions…' : cta,
            background: Colors.white,
            foreground: const Color(0xFF244D82),
            fontWeight: FontWeight.w700,
            fontSize: 16,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onPressed: rooms.preparingPlay
                ? null
                : () async {
                    final started = await rooms.startRoomPlay(room.id);
                    if (!context.mounted) return;
                    if (started) {
                      context.go('/today/play');
                    } else {
                      _showPlayRefreshError(context, rooms);
                    }
                  },
          ),
        ],
      ),
    );
  }
}

void _showPlayRefreshError(BuildContext context, RoomsController rooms) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        rooms.lastError ?? 'Could not verify the latest questions. Try again.',
      ),
    ),
  );
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
    required this.loading,
    required this.onTap,
  });

  final RoomDayQuestion question;
  final RoomDay day;
  final RoomAnswer? answer;
  final bool loading;
  final VoidCallback? onTap;

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
      key: ValueKey('yesterday-question-${question.qid}'),
      behavior: HitTestBehavior.opaque,
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
                if (loading)
                  const SizedBox(
                    key: ValueKey('opening-yesterday-question'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (score != null)
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
    required this.room,
    required this.myUid,
    required this.canRemoveMembers,
    required this.onInvite,
  });

  final RoomsController rooms;
  final String roomId;
  final RtwRoom room;
  final String? myUid;
  final bool canRemoveMembers;
  final VoidCallback onInvite;

  @override
  State<_Leaderboard> createState() => _LeaderboardState();
}

class _LeaderboardState extends State<_Leaderboard> {
  // Cached per roomId: creating a fresh stream on every rebuild tears down
  // and re-creates the Firestore listener (visible flicker + wasted reads).
  late Stream<List<RtwRoomMember>> _membersStream = widget.rooms.membersStream(
    widget.roomId,
  );
  String? _actionError;

  Future<void> _showNudge(RtwRoomMember member) async {
    final sent = await showV2Sheet<bool>(
      context,
      (_) => _NudgeMemberSheet(
        rooms: widget.rooms,
        roomId: widget.roomId,
        member: member,
      ),
    );
    if (sent != true || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Nudge sent')));
  }

  Future<void> _leaveRoom() async {
    final confirmed = await confirmLeaveRoom(
      context,
      roomName: widget.room.name,
      isCreator: widget.canRemoveMembers,
      isLastMember: widget.room.memberCount <= 1,
    );
    if (confirmed != true || !mounted) return;
    final left = await widget.rooms.leaveRoom(widget.roomId);
    if (!mounted) return;
    if (left) {
      context.go('/rooms');
      return;
    }
    setState(() {
      _actionError = widget.rooms.lastError ?? 'Could not leave the room.';
    });
  }

  Future<void> _removeMember(RtwRoomMember member) async {
    final confirmed = await showV2Sheet<bool>(context, (sheetContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          V2Eyebrow(
            'Remove member',
            size: 11,
            letterSpacing: 1.6,
            color: RtwV2Colors.danger,
          ),
          const SizedBox(height: 8),
          Text('Remove ${member.displayName}?', style: v2Serif(29)),
          const SizedBox(height: 10),
          Text(
            'They will immediately lose access and will not be able to rejoin '
            'with this room\'s invite code. Their past answers stay in the '
            'room history.',
            style: v2Sans(14, color: RtwV2Colors.subText, height: 1.5),
          ),
          const SizedBox(height: 18),
          V2Button(
            'Remove member',
            key: const ValueKey('confirm-remove-room-member'),
            background: RtwV2Colors.danger,
            onPressed: () => Navigator.of(sheetContext).pop(true),
            padding: const EdgeInsets.symmetric(vertical: 16),
            radius: 16,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: Text(
                'Keep member',
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
    if (confirmed != true || !mounted) return;
    final removed = await widget.rooms.removeRoomMember(
      widget.roomId,
      member.uid,
    );
    if (!mounted || removed) return;
    setState(() {
      _actionError =
          widget.rooms.lastError ?? 'Could not remove ${member.displayName}.';
    });
  }

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
                Builder(
                  builder: (context) {
                    final answeredToday =
                        widget.room.currentDailyKey != null &&
                        member.lastPlayedDailyKey ==
                            widget.room.currentDailyKey;
                    return Container(
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
                          _MemberAnswerDot(
                            member: member,
                            answeredToday: answeredToday,
                            canNudge:
                                !answeredToday && member.uid != widget.myUid,
                            onNudge: () => _showNudge(member),
                          ),
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
                          Text(
                            _thousands(member.roomScore),
                            style: v2Serif(17),
                          ),
                          const SizedBox(width: 4),
                          _MemberAction(
                            member: member,
                            myUid: widget.myUid,
                            canRemoveMembers: widget.canRemoveMembers,
                            onLeave: _leaveRoom,
                            onRemove: () => _removeMember(member),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const V2Hairline(),
              ],
              if (_actionError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Text(
                    _actionError!,
                    style: v2Sans(12.5, color: RtwV2Colors.danger),
                  ),
                ),
              Semantics(
                button: true,
                label: 'Invite someone to this room',
                child: InkWell(
                  key: const ValueKey('room-invite-row'),
                  onTap: widget.onInvite,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: RtwV2Colors.meterBlue.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_add_alt_1,
                            size: 16,
                            color: RtwV2Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Add someone',
                            style: v2Sans(
                              15,
                              color: RtwV2Colors.blue,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.add,
                          size: 20,
                          color: RtwV2Colors.blue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberAnswerDot extends StatelessWidget {
  const _MemberAnswerDot({
    required this.member,
    required this.answeredToday,
    required this.canNudge,
    required this.onNudge,
  });

  final RtwRoomMember member;
  final bool answeredToday;
  final bool canNudge;
  final VoidCallback onNudge;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      key: ValueKey(
        answeredToday
            ? 'member-answered-today-${member.uid}'
            : 'member-not-answered-today-${member.uid}',
      ),
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: answeredToday ? RtwV2Colors.blue : const Color(0xFFD8D2C5),
        shape: BoxShape.circle,
      ),
    );
    return Semantics(
      button: canNudge,
      label: answeredToday
          ? '${member.displayName} answered today'
          : canNudge
          ? 'Nudge ${member.displayName}. They have not answered today.'
          : '${member.displayName} has not answered today',
      child: Tooltip(
        message: answeredToday
            ? 'Answered today'
            : canNudge
            ? 'Nudge ${member.displayName}'
            : 'Not answered yet',
        child: InkResponse(
          onTap: canNudge ? onNudge : null,
          radius: 22,
          child: SizedBox(width: 28, height: 40, child: Center(child: dot)),
        ),
      ),
    );
  }
}

class _NudgeMemberSheet extends StatefulWidget {
  const _NudgeMemberSheet({
    required this.rooms,
    required this.roomId,
    required this.member,
  });

  final RoomsController rooms;
  final String roomId;
  final RtwRoomMember member;

  @override
  State<_NudgeMemberSheet> createState() => _NudgeMemberSheetState();
}

class _NudgeMemberSheetState extends State<_NudgeMemberSheet> {
  RoomNudgeStatus? status;
  bool loading = true;
  bool sending = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final next = await widget.rooms.getRoomNudgeStatus(
      widget.roomId,
      widget.member.uid,
    );
    if (!mounted) return;
    setState(() {
      status = next;
      loading = false;
      error = next == null
          ? widget.rooms.lastError ?? 'Could not check this nudge.'
          : null;
    });
  }

  Future<void> _send() async {
    if (sending || status?.canNudge != true) return;
    setState(() {
      sending = true;
      error = null;
    });
    final sent = await widget.rooms.sendRoomNudge(
      widget.roomId,
      widget.member.uid,
    );
    if (!mounted) return;
    if (sent) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      sending = false;
      error = widget.rooms.lastError ?? 'Could not send this nudge.';
    });
  }

  String? get _blockedMessage {
    final current = status;
    if (current == null) return null;
    if (current.alreadyNudged || current.blockReason == 'already-nudged') {
      return 'You nudged ${current.targetName} today';
    }
    return switch (current.blockReason) {
      'already-answered' => '${current.targetName} already answered today.',
      'daily-limit' => 'You’ve sent five nudges today.',
      'target-opted-out' => '${current.targetName} has turned off room nudges.',
      'target-not-member' => '${current.targetName} is no longer in this room.',
      'sender-not-member' => 'You are no longer in this room.',
      'world' => 'The World does not support nudges.',
      'self' => 'You can’t nudge yourself.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final current = status;
    final name = current?.targetName ?? widget.member.displayName;
    final count = current?.nudgeCount ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const V2Eyebrow('Room nudge', size: 11, letterSpacing: 1.6),
        const SizedBox(height: 8),
        Text('Nudge $name?', style: v2Serif(29)),
        const SizedBox(height: 10),
        Text(
          '$name hasn’t answered today.',
          style: v2Sans(14, color: RtwV2Colors.subText, height: 1.5),
        ),
        if (loading) ...[
          const SizedBox(height: 18),
          const Center(child: CircularProgressIndicator()),
        ] else if (current != null) ...[
          const SizedBox(height: 10),
          Text(
            count == 1
                ? '1 person has nudged $name today'
                : '$count people have nudged $name today',
            style: v2Sans(13, color: RtwV2Colors.muted),
          ),
          if (_blockedMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _blockedMessage!,
              style: v2Sans(
                13,
                color: RtwV2Colors.clay,
                weight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 18),
          V2Button(
            sending ? 'Sending…' : 'Send nudge',
            key: const ValueKey('send-room-nudge'),
            onPressed: current.canNudge && !sending ? _send : null,
            padding: const EdgeInsets.symmetric(vertical: 16),
            radius: 16,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: v2Sans(13, color: RtwV2Colors.danger)),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: sending ? null : () => Navigator.of(context).pop(false),
            child: Text(
              'Not now',
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
  }
}

class _MemberAction extends StatelessWidget {
  const _MemberAction({
    required this.member,
    required this.myUid,
    required this.canRemoveMembers,
    required this.onLeave,
    required this.onRemove,
  });

  final RtwRoomMember member;
  final String? myUid;
  final bool canRemoveMembers;
  final VoidCallback onLeave;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isMe = member.uid == myUid;
    final canRemove = canRemoveMembers && !isMe && !member.isCreator;
    final action = isMe ? onLeave : (canRemove ? onRemove : null);

    return SizedBox(
      width: 40,
      height: 40,
      child: action == null
          ? null
          : IconButton(
              key: ValueKey(
                isMe
                    ? 'leave-room-from-leaderboard'
                    : 'remove-room-member-${member.uid}',
              ),
              tooltip: isMe ? 'Leave room' : 'Remove ${member.displayName}',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.more_vert,
                size: 19,
                color: RtwV2Colors.muted,
              ),
              onPressed: action,
            ),
    );
  }
}
