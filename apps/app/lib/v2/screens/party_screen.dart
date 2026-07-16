import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../party_controller.dart';
import '../rooms_controller.dart';
import '../sheets/room_sheets.dart' show showMatureConfirmSheet;
import '../tokens_v2.dart';
import '../widgets_v2.dart';

final partyControllerProvider = ChangeNotifierProvider<PartyController>((ref) {
  return PartyController();
});

const _settleCurve = Cubic(0.2, 0.8, 0.3, 1);

/// PARTY — pass-the-phone (prototype lines 439-606). Session-local scoring;
/// questions come from the cloud bank pool cached on the rooms controller.
class PartyScreenV2 extends ConsumerStatefulWidget {
  const PartyScreenV2({super.key});

  @override
  ConsumerState<PartyScreenV2> createState() => _PartyScreenV2State();
}

class _PartyScreenV2State extends ConsumerState<PartyScreenV2> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(roomsControllerProvider)
          .refreshPartyPool(tier: ref.read(partyControllerProvider).tier);
    });
  }

  @override
  Widget build(BuildContext context) {
    final party = ref.watch(partyControllerProvider);
    final rooms = ref.watch(roomsControllerProvider);
    return V2Scaffold(
      location: '/party',
      wideWidth: 660,
      showNav: party.stage == PartyStage.setup,
      child: switch (party.stage) {
        PartyStage.setup => _Setup(party: party, pool: rooms.partyPool),
        PartyStage.play => _Play(party: party, rooms: rooms),
        PartyStage.done => _Done(party: party, rooms: rooms),
      },
    );
  }
}

// ── SETUP ───────────────────────────────────────────────────────────────

class _Setup extends ConsumerWidget {
  const _Setup({required this.party, required this.pool});

  final PartyController party;
  final List<PartyQuestion> pool;

  static const _tierDescriptions = {
    RoomTier.workSafe: 'Lightest topics, safe for a work crowd.',
    RoomTier.normal: 'Everyday questions. Includes work-safe topics.',
    RoomTier.mature: 'Edgier, words-only. Skips the tame stuff.',
  };

  /// After Dark needs one-time consent; the pool re-fetches per tier so the
  /// deck is drawn from the full bank at that spice level.
  Future<void> _selectTier(
    BuildContext context,
    WidgetRef ref,
    RoomTier next,
  ) async {
    if (party.tier == next) return;
    final rooms = ref.read(roomsControllerProvider);
    if (next == RoomTier.mature && !rooms.hasMatureConsent) {
      final confirmed = await showMatureConfirmSheet(context, party: true);
      if (confirmed != true) return;
      await rooms.markMatureConsent();
    }
    party.setTier(next);
    unawaited(rooms.refreshPartyPool(tier: next));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    final rooms = ref.watch(roomsControllerProvider);
    final tierPool = pool
        .where((question) => party.tier.allowsQuestionTier(question.tier))
        .toList();
    final waitingForInitialPool =
        pool.isEmpty &&
        (!rooms.partyPoolLoadAttempted || rooms.partyPoolLoading);
    final shouldOfferPoolReload =
        pool.isEmpty && rooms.partyPoolLoadAttempted && !rooms.partyPoolLoading;
    final topics = [
      'All',
      ...{for (final question in tierPool) question.tag},
    ];
    final filtered = party.poolFor(pool);
    final summary =
        '${party.players} ${party.players == 1 ? 'player' : 'players'} · '
        '${party.rounds} ${party.rounds == 1 ? 'round' : 'rounds'} · '
        '${party.rounds * party.players} questions';

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, isWide ? 60 : 78, 24, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const V2Eyebrow(
            'Party mode',
            size: 11,
            color: RtwV2Colors.clay,
            letterSpacing: 1.6,
          ),
          const SizedBox(height: 10),
          Text(
            'Pass the phone.',
            style: v2Serif(36, height: 1.06, letterSpacing: -0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'Play with everyone in the room, right from your phone.',
            style: v2Sans(14, color: RtwV2Colors.subText, height: 1.55),
          ),
          const SizedBox(height: 26),
          const V2Eyebrow('Players'),
          const SizedBox(height: 12),
          Row(
            children: [
              _StepButton(
                label: '−',
                disabled: party.players <= 1,
                onTap: () => party.setPlayers(party.players - 1),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text('${party.players}', style: v2Serif(30, height: 1)),
                    const SizedBox(height: 3),
                    Text(
                      party.players == 1 ? 'PLAYER' : 'PLAYERS',
                      style: v2Mono(10, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
              _StepButton(
                label: '+',
                disabled: party.players >= 20,
                onTap: () => party.setPlayers(party.players + 1),
              ),
            ],
          ),
          if (party.solo) ...[
            const SizedBox(height: 10),
            Text(
              'Solo play is just the questions. Swipe through at your own pace, no predictions.',
              style: v2Sans(12.5, color: RtwV2Colors.muted, height: 1.45),
            ),
          ],
          const SizedBox(height: 24),
          const V2Eyebrow('Spice level'),
          const SizedBox(height: 12),
          _SpiceSegment(
            value: party.tier,
            onChanged: (next) => _selectTier(context, ref, next),
          ),
          const SizedBox(height: 9),
          Text(
            _tierDescriptions[party.tier]!,
            style: v2Sans(12.5, color: RtwV2Colors.muted, height: 1.45),
          ),
          const SizedBox(height: 24),
          const V2Eyebrow('Topics'),
          const SizedBox(height: 12),
          _TopicChips(party: party, topics: topics),
          const SizedBox(height: 24),
          const V2Eyebrow('Rounds'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: RtwV2Colors.hairline,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                for (var n = 1; n <= 5; n++) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => party.setRounds(n),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: party.rounds == n
                              ? RtwV2Colors.inkSoft
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          '$n',
                          style: v2Sans(
                            14,
                            color: party.rounds == n
                                ? Colors.white
                                : RtwV2Colors.subText,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (n < 5) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'Each player makes one prediction per round. Every round has one question per player.',
            style: v2Sans(12.5, color: RtwV2Colors.muted, height: 1.45),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: RtwV2Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                summary,
                style: v2Mono(
                  11,
                  color: RtwV2Colors.subText,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            if (waitingForInitialPool)
              Container(
                padding: const EdgeInsets.all(18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RtwV2Colors.hairline,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Loading questions…',
                  style: v2Sans(
                    15,
                    color: RtwV2Colors.faint,
                    weight: FontWeight.w600,
                  ),
                ),
              )
            else if (shouldOfferPoolReload)
              V2Button(
                'Load more questions →',
                onPressed: () => rooms.refreshPartyPool(tier: party.tier),
                padding: const EdgeInsets.symmetric(vertical: 18),
                radius: 16,
                fontSize: 16,
              )
            else
              Container(
                padding: const EdgeInsets.all(18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RtwV2Colors.hairline,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Nothing to play with this mix, try other topics',
                  style: v2Sans(
                    15,
                    color: RtwV2Colors.faint,
                    weight: FontWeight.w600,
                  ),
                ),
              )
          else
            V2Button(
              'Start the round →',
              onPressed: () => party.start(pool),
              padding: const EdgeInsets.symmetric(vertical: 18),
              radius: 16,
              fontSize: 16,
            ),
        ],
      ),
    );
  }
}

/// Topic picker: collapsed to "All topics" + an expander by default — the
/// full tag grid is a lot of chrome for a default most players keep.
class _TopicChips extends StatefulWidget {
  const _TopicChips({required this.party, required this.topics});

  final PartyController party;
  final List<String> topics;

  @override
  State<_TopicChips> createState() => _TopicChipsState();
}

/// Same look as the room segment; local copy because that one is sheet-private.
class _SpiceSegment extends StatelessWidget {
  const _SpiceSegment({required this.value, required this.onChanged});

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
                  padding: const EdgeInsets.symmetric(
                    vertical: 11,
                    horizontal: 6,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == tier
                        ? RtwV2Colors.inkSoft
                        : Colors.transparent,
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

class _TopicChipsState extends State<_TopicChips> {
  late bool _expanded = !widget.party.topics.contains('All');

  Widget _chip(String label, {required bool on, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: on
              ? RtwV2Colors.blue.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: on ? RtwV2Colors.blue : RtwV2Colors.borderStrong,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: v2Sans(
            14,
            color: on ? RtwV2Colors.blueTextDeep : RtwV2Colors.subText,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip(
            'All topics',
            on: widget.party.topics.contains('All'),
            onTap: () => widget.party.toggleTopic('All'),
          ),
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
        for (final tag in widget.topics)
          _chip(
            tag == 'All' ? 'All topics' : tag,
            on: widget.party.topics.contains(tag),
            onTap: () => widget.party.toggleTopic(tag),
          ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: RtwV2Colors.card,
          border: Border.all(color: RtwV2Colors.borderStrong, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: v2Sans(
            24,
            color: disabled ? const Color(0xFFCFC8B7) : RtwV2Colors.inkSoft,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ── PLAY ────────────────────────────────────────────────────────────────

class _Play extends StatelessWidget {
  const _Play({required this.party, required this.rooms});

  final PartyController party;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final card = party.card;
    if (card == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 54, 24, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: party.again,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: RtwV2Colors.card,
                    border: Border.all(color: const Color(0xFFDCD6C9)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '× Exit',
                    style: v2Sans(
                      14,
                      color: const Color(0xFF5C584F),
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  if (party.canUndo) ...[
                    GestureDetector(
                      onTap: party.undo,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(11, 9, 14, 9),
                        decoration: BoxDecoration(
                          color: RtwV2Colors.card,
                          border: Border.all(color: const Color(0xFFDCD6C9)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.undo_rounded,
                              size: 16,
                              color: Color(0xFF5C584F),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Undo',
                              style: v2Sans(
                                14,
                                color: const Color(0xFF5C584F),
                                weight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    '${party.idx + 1} / ${party.deck.length}',
                    style: v2Mono(12, letterSpacing: 1.4),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: KeyedSubtree(
                key: ValueKey(
                  '${party.idx}-${party.sub}-${party.turn}-${card.qid}-${party.swapPulse}',
                ),
                child: switch (party.sub) {
                  PartySub.pass => _PassScreen(party: party),
                  PartySub.revealPass => _PassScreen(party: party),
                  PartySub.pick => _PickPanel(
                    party: party,
                    rooms: rooms,
                    card: card,
                  ),
                  PartySub.predict => _PredictPanel(party: party, card: card),
                  PartySub.reveal => _RevealPanel(party: party, card: card),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showPartyMenuSheet(BuildContext context, PartyController party) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _PartyMenuSheet(party: party),
  );
}

class _PartyMenuSheet extends StatefulWidget {
  const _PartyMenuSheet({required this.party});

  final PartyController party;

  @override
  State<_PartyMenuSheet> createState() => _PartyMenuSheetState();
}

class _PartyMenuSheetState extends State<_PartyMenuSheet> {
  late final List<TextEditingController> _nameControllers;

  @override
  void initState() {
    super.initState();
    _nameControllers = [
      for (var index = 0; index < widget.party.players; index++)
        TextEditingController(text: widget.party.playerName(index)),
    ];
  }

  @override
  void dispose() {
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _ensureControllerCount(PartyController party) {
    while (_nameControllers.length < party.players) {
      final index = _nameControllers.length;
      _nameControllers.add(
        TextEditingController(text: party.playerName(index)),
      );
    }
    while (_nameControllers.length > party.players) {
      _nameControllers.removeLast().dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.84;

    return AnimatedBuilder(
      animation: widget.party,
      builder: (context, _) {
        final party = widget.party;
        _ensureControllerCount(party);
        final ranked = [
          for (var playerIndex = 0; playerIndex < party.players; playerIndex++)
            (playerIndex, party.scores[playerIndex]),
        ]..sort((a, b) => b.$2.compareTo(a.$2));

        return SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: viewInsets),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxHeight,
                  maxWidth: 660,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: RtwV2Colors.card,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 12, 24, 26 + bottomSafe),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: RtwV2Colors.borderStrong,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Icon(
                              Icons.menu_rounded,
                              size: 21,
                              color: RtwV2Colors.inkSoft,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Game menu',
                              style: v2Sans(
                                20,
                                color: RtwV2Colors.inkSoft,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${party.idx + 1}/${party.deck.length}',
                              style: v2Mono(
                                11,
                                color: RtwV2Colors.muted,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const _SheetSectionTitle(
                          icon: Icons.leaderboard_rounded,
                          label: 'Leaderboard',
                        ),
                        const SizedBox(height: 10),
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: RtwV2Colors.paper,
                            border: Border.all(color: RtwV2Colors.border),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              for (final (rank, entry) in ranked.indexed) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          '#${rank + 1}',
                                          style: v2Mono(
                                            12,
                                            color: RtwV2Colors.muted,
                                            letterSpacing: 0,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 9,
                                        height: 9,
                                        decoration: BoxDecoration(
                                          color: _playerColor(entry.$1),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          party.playerName(entry.$1),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: v2Sans(
                                            14.5,
                                            color: RtwV2Colors.inkSoft,
                                            weight: rank == 0
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${entry.$2.round()}',
                                        style: v2Serif(19),
                                      ),
                                    ],
                                  ),
                                ),
                                if (rank < ranked.length - 1)
                                  const V2Hairline(),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _SheetSectionTitle(
                          icon: Icons.badge_outlined,
                          label: 'Edit player names',
                        ),
                        const SizedBox(height: 10),
                        for (var index = 0; index < party.players; index++) ...[
                          TextField(
                            controller: _nameControllers[index],
                            onChanged: (value) =>
                                party.setPlayerName(index, value),
                            textCapitalization: TextCapitalization.words,
                            textInputAction: index == party.players - 1
                                ? TextInputAction.done
                                : TextInputAction.next,
                            cursorColor: _playerColor(index),
                            style: v2Sans(
                              15,
                              color: RtwV2Colors.inkSoft,
                              weight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Player ${index + 1}',
                              labelStyle: v2Sans(12, color: RtwV2Colors.muted),
                              prefixIcon: Padding(
                                padding: const EdgeInsets.only(
                                  left: 14,
                                  right: 10,
                                ),
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _playerColor(index),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 34,
                                minHeight: 20,
                              ),
                              filled: true,
                              fillColor: RtwV2Colors.paper,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: RtwV2Colors.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: _playerColor(index),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          if (index < party.players - 1)
                            const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 24),
                        V2Button(
                          'Restart game',
                          background: RtwV2Colors.inkSoft,
                          onPressed: () => _confirmRestartPartyGame(
                            context,
                            party,
                            closeMenu: true,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          radius: 14,
                          fontSize: 15,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Keeps player names, resets scores, and draws a fresh question set.',
                          textAlign: TextAlign.center,
                          style: v2Sans(
                            12,
                            color: RtwV2Colors.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _confirmRestartPartyGame(
  BuildContext context,
  PartyController party, {
  bool closeMenu = false,
}) async {
  final confirmed = await showV2Sheet<bool>(
    context,
    (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const V2Eyebrow(
          'Restart game',
          size: 11,
          color: RtwV2Colors.clay,
          letterSpacing: 1.6,
        ),
        const SizedBox(height: 10),
        Text('Start over?', style: v2Serif(28, height: 1.05)),
        const SizedBox(height: 12),
        Text(
          'This resets scores and draws a fresh question set. Player names stay the same.',
          style: v2Sans(14, color: RtwV2Colors.subText, height: 1.45),
        ),
        const SizedBox(height: 20),
        V2Button(
          'Restart now',
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
              'Keep playing',
              style: v2Sans(
                14,
                color: RtwV2Colors.subText,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  party.restartGame();
  if (closeMenu && context.mounted) Navigator.of(context).pop();
}

class _SheetSectionTitle extends StatelessWidget {
  const _SheetSectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: RtwV2Colors.clay),
        const SizedBox(width: 8),
        V2Eyebrow(label, letterSpacing: 1.2),
      ],
    );
  }
}

Color _playerColor(int index) =>
    RtwV2Colors.playerColors[index % RtwV2Colors.playerColors.length];

class _PlayerBanner extends StatelessWidget {
  const _PlayerBanner({required this.party, this.onTap});

  final PartyController party;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final playerNumber = party.currentPlayerIndex + 1;
    final playerName = party.currentPlayerName;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: RtwV2Colors.card,
          border: Border.all(
            color: _playerColor(party.currentPlayerIndex),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _playerColor(party.currentPlayerIndex),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$playerNumber',
                style: v2Sans(15, color: Colors.white, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$playerName's turn",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: v2Sans(
                      16,
                      color: RtwV2Colors.inkSoft,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'of ${party.players}',
                    style: v2Mono(10, letterSpacing: 1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Tooltip(
              message: 'Game menu',
              child: Icon(
                Icons.menu_rounded,
                size: 20,
                color: Color(0xFF7A7466),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapQuestionButton extends StatelessWidget {
  const _SwapQuestionButton({required this.party});

  final PartyController party;

  @override
  Widget build(BuildContext context) {
    if (!party.swapControlVisible) return const SizedBox.shrink();
    final enabled = party.canSwapQuestion;
    final label = enabled
        ? 'Swap question · ${party.swapsUsed}/${PartyController.maxSwaps} swaps used'
        : party.swapsLeft == 0
        ? '${party.swapsUsed}/${PartyController.maxSwaps} swaps used'
        : 'No alternate questions';

    return TextButton.icon(
      onPressed: enabled ? party.swapQuestion : null,
      icon: Icon(
        Icons.shuffle_rounded,
        size: 16,
        color: enabled ? RtwV2Colors.blueTextDeep : RtwV2Colors.faint,
      ),
      label: Text(
        label,
        style: v2Sans(
          13,
          color: enabled ? RtwV2Colors.blueTextDeep : RtwV2Colors.faint,
          weight: FontWeight.w600,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: RtwV2Colors.blueTextDeep,
      ),
    );
  }
}

bool _tapHitsReactionButtons(
  Offset position,
  BoxConstraints constraints, {
  required double cardHeight,
}) {
  final cardWidth = math.min(320.0, constraints.maxWidth);
  final cardLeft = (constraints.maxWidth - cardWidth) / 2;
  final cardTop = (constraints.maxHeight - cardHeight) / 2;
  return Rect.fromLTWH(
    cardLeft + cardWidth - 96,
    cardTop + 12,
    84,
    48,
  ).contains(position);
}

class _PickPanel extends StatelessWidget {
  const _PickPanel({
    required this.party,
    required this.rooms,
    required this.card,
  });

  final PartyController party;
  final RoomsController rooms;
  final PartyQuestion card;

  @override
  Widget build(BuildContext context) {
    final dx = party.dragX;
    final yesOn = (dx / RtwV2Motion.zoneOpacityRamp).clamp(0.0, 1.0);
    final noOn = (-dx / RtwV2Motion.zoneOpacityRamp).clamp(0.0, 1.0);
    final reaction = rooms.reactionForQuestion(card.qid);
    final borderColor = dx > RtwV2Motion.borderTintThreshold
        ? RtwV2Colors.blue
        : dx < -RtwV2Motion.borderTintThreshold
        ? RtwV2Colors.clay
        : RtwV2Colors.border;

    return Column(
      children: [
        if (!party.solo)
          _PlayerBanner(
            party: party,
            onTap: () => _showPartyMenuSheet(context, party),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                key: const ValueKey('party-pick-zone'),
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) {
                  if (_tapHitsReactionButtons(
                    details.localPosition,
                    constraints,
                    cardHeight: 300,
                  )) {
                    return;
                  }
                  party.tapSide(
                    details.localPosition.dx < constraints.maxWidth / 2
                        ? 'b'
                        : 'a',
                  );
                },
                child: SizedBox.expand(
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: -38,
                        top: 0,
                        bottom: 0,
                        width: 72,
                        child: IgnorePointer(
                          child: Center(
                            child: RotatedBox(
                              quarterTurns: 1,
                              child: Text(
                                card.optB,
                                maxLines: 1,
                                style: v2Serif(
                                  32,
                                  color: RtwV2Colors.clay.withValues(
                                    alpha: 0.22 + noOn * 0.58,
                                  ),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -38,
                        top: 0,
                        bottom: 0,
                        width: 72,
                        child: IgnorePointer(
                          child: Center(
                            child: RotatedBox(
                              quarterTurns: -1,
                              child: Text(
                                card.optA,
                                maxLines: 1,
                                style: v2Serif(
                                  32,
                                  color: RtwV2Colors.blue.withValues(
                                    alpha: 0.22 + yesOn * 0.58,
                                  ),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onHorizontalDragStart: (_) => party.cardDragStart(),
                        onHorizontalDragUpdate: (details) =>
                            party.cardDragUpdate(details.delta.dx),
                        onHorizontalDragEnd: (details) => party.cardDragEnd(
                          details.velocity.pixelsPerSecond.dx,
                        ),
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey('question-swap-${party.swapPulse}'),
                          tween: Tween<double>(
                            begin: party.swapPulse == 0 ? 0 : 1,
                            end: 0,
                          ),
                          duration: const Duration(milliseconds: 360),
                          curve: Curves.easeOutCubic,
                          builder: (context, pulse, child) {
                            final shake =
                                math.sin(pulse * math.pi * 4) * 7 * pulse;
                            return Opacity(
                              opacity: 1 - pulse * 0.14,
                              child: Transform.translate(
                                offset: Offset(shake, 0),
                                child: child,
                              ),
                            );
                          },
                          child: AnimatedContainer(
                            duration: party.dragging
                                ? Duration.zero
                                : RtwV2Motion.cardSettle,
                            curve: _settleCurve,
                            transform: Matrix4.identity()
                              ..translateByDouble(dx, 0, 0, 1)
                              ..rotateZ(
                                dx * RtwV2Motion.tiltFactor * 3.14159 / 180,
                              ),
                            transformAlignment: Alignment.center,
                            constraints: const BoxConstraints(maxWidth: 320),
                            height: 300,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: RtwV2Colors.card,
                              border: Border.all(
                                color: borderColor,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Color.fromRGBO(
                                    40,
                                    40,
                                    40,
                                    0.08 + dx.abs() / 800,
                                  ),
                                  offset: const Offset(0, 12),
                                  blurRadius: 38,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        card.tag.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: v2Mono(
                                          10,
                                          color: RtwV2Colors.clay,
                                          letterSpacing: 1.8,
                                        ),
                                      ),
                                    ),
                                    V2QuestionReactionButtons(
                                      reaction: reaction,
                                      onToggle: (next) => unawaited(
                                        rooms.toggleQuestionReaction(
                                          card.qid,
                                          next,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: SingleChildScrollView(
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Text(
                                        card.prompt,
                                        style: v2Serif(
                                          25,
                                          height: 1.2,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => party.tapSide('b'),
                                        child: Text(
                                          '← ${card.optB}',
                                          style: v2Sans(
                                            16,
                                            color:
                                                dx <
                                                    -RtwV2Motion
                                                        .borderTintThreshold
                                                ? RtwV2Colors.clay
                                                : const Color(0xFF4A463E),
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 56,
                                      child: Icon(
                                        Icons.sync_alt,
                                        size: 18,
                                        color: Color(0xFFCFC8B7),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => party.tapSide('a'),
                                        child: Text(
                                          '${card.optA} →',
                                          textAlign: TextAlign.right,
                                          style: v2Sans(
                                            16,
                                            color:
                                                dx >
                                                    RtwV2Motion
                                                        .borderTintThreshold
                                                ? RtwV2Colors.blue
                                                : const Color(0xFF4A463E),
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
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
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text.rich(
            TextSpan(
              text: 'Swipe left for ',
              style: v2Sans(13, color: RtwV2Colors.faint),
              children: [
                TextSpan(
                  text: card.optB,
                  style: v2Sans(
                    13,
                    color: RtwV2Colors.subText,
                    weight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ', right for '),
                TextSpan(
                  text: card.optA,
                  style: v2Sans(
                    13,
                    color: RtwV2Colors.subText,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        if (party.swapControlVisible) ...[
          const SizedBox(height: 6),
          _SwapQuestionButton(party: party),
        ],
      ],
    );
  }
}

class _PredictPanel extends StatelessWidget {
  const _PredictPanel({required this.party, required this.card});

  final PartyController party;
  final PartyQuestion card;

  @override
  Widget build(BuildContext context) {
    final sideA = party.side == 'a';
    final sideLabel = sideA ? card.optA : card.optB;
    final sideColor = sideA ? RtwV2Colors.blue : RtwV2Colors.clay;
    final isLastTurn = party.turn + 1 >= party.players;
    final others = math.max(0, party.players - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlayerBanner(
          party: party,
          onTap: () => _showPartyMenuSheet(context, party),
        ),
        Text(
          card.tag.toUpperCase(),
          style: v2Mono(11, color: RtwV2Colors.clay, letterSpacing: 1.6),
        ),
        const SizedBox(height: 12),
        Text(
          card.prompt,
          style: v2Serif(29, height: 1.18, letterSpacing: -0.5),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PredictionReadout(
                percent: party.pred,
                people: others,
                sideLabel: sideLabel,
                sideColor: sideColor,
                promptSize: 20,
                primarySize: 72,
              ),
              const SizedBox(height: 24),
              PredictionAgreementMeter(
                percent: party.pred,
                people: others,
                height: 68,
                radius: 16,
                onUpdate: party.meterUpdate,
              ),
            ],
          ),
        ),
        if (party.swapControlVisible) ...[
          _SwapQuestionButton(party: party),
          const SizedBox(height: 8),
        ],
        V2Button(
          isLastTurn ? 'Submit · reveal the room ↓' : 'Submit · pass along →',
          onPressed: party.lockTurn,
          padding: const EdgeInsets.symmetric(vertical: 18),
          radius: 16,
          fontSize: 16,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: party.changePick,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const V2LeadingArrowLabel(
              'Change my answer',
              color: RtwV2Colors.subText,
              fontSize: 13,
              weight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _PassScreen extends StatelessWidget {
  const _PassScreen({required this.party});

  final PartyController party;

  @override
  Widget build(BuildContext context) {
    final playerNumber = party.currentPlayerIndex + 1;
    final playerName = party.currentPlayerName;
    final revealHandoff = party.sub == PartySub.revealPass;
    // turn 0 means this hand-off opens a fresh question with a new reader,
    // rather than passing between voters mid-question.
    final newQuestion = !revealHandoff && party.turn == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (newQuestion)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    '${party.idx + 1} / ${party.deck.length}',
                    style: v2Mono(12, letterSpacing: 1.4),
                  ),
                ),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _playerColor(party.currentPlayerIndex),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$playerNumber',
                  style: v2Serif(32, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                revealHandoff
                    ? 'Pass back for the reveal.'
                    : newQuestion
                    ? 'Next question, new reader.'
                    : 'Pass it along.',
                textAlign: TextAlign.center,
                style: v2Serif(32, letterSpacing: -0.5),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 270),
                child: Text.rich(
                  TextSpan(
                    text: 'Hand the phone to ',
                    style: v2Sans(15, color: RtwV2Colors.subText, height: 1.55),
                    children: [
                      TextSpan(
                        text: playerName,
                        style: v2Sans(
                          15,
                          color: RtwV2Colors.inkSoft,
                          weight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: revealHandoff
                            ? '. Their prediction and score are ready.'
                            : newQuestion
                            ? '. They answer first this round, then predict '
                                  'the table.'
                            : ", or set it down for them. Peeking's fine now, only "
                                  "the first player's prediction was hidden.",
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        V2Button(
          "I'm $playerName →",
          onPressed: party.passContinue,
          padding: const EdgeInsets.symmetric(vertical: 18),
          radius: 16,
          fontSize: 16,
        ),
      ],
    );
  }
}

class _RevealPanel extends StatelessWidget {
  const _RevealPanel({required this.party, required this.card});

  final PartyController party;
  final PartyQuestion card;

  @override
  Widget build(BuildContext context) {
    final t = party.revealT;
    final yesPct = party.othersYesPct;
    final yesCount = party.othersYesCount;
    final reader = party.turnPicks.isEmpty ? null : party.turnPicks.first;
    final isLast = party.idx + 1 >= party.deck.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          card.tag.toUpperCase(),
          style: v2Mono(11, color: RtwV2Colors.clay, letterSpacing: 1.6),
        ),
        const SizedBox(height: 12),
        Text(
          card.prompt,
          style: v2Serif(29, height: 1.18, letterSpacing: -0.5),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _RevealSplitMeter(
                    leftLabel: card.optB,
                    rightLabel: card.optA,
                    rightPct: yesPct.toDouble(),
                    t: t,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'OTHER PLAYERS · $yesCount of ${party.otherPlayerCount} said ${card.optA}',
                  style: v2Mono(10, letterSpacing: 1),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: RtwV2Colors.card,
                    border: Border.all(color: RtwV2Colors.border),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          V2Eyebrow(
                            "${party.readerName}'s read",
                            letterSpacing: 1.2,
                          ),
                          const SizedBox(height: 5),
                          Text.rich(
                            TextSpan(
                              text: '${(party.readerRevealScore * t).round()}',
                              style: v2Serif(32, height: 1),
                              children: [
                                TextSpan(
                                  text: ' / 100',
                                  style: v2Serif(15, color: RtwV2Colors.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'guessed\n${reader?.prediction ?? 0}%',
                        textAlign: TextAlign.right,
                        style: v2Sans(
                          12,
                          color: RtwV2Colors.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const V2Eyebrow(
                  'Scores · Reading the room',
                  letterSpacing: 1.2,
                ),
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
                      for (
                        var playerIndex = 0;
                        playerIndex < party.players;
                        playerIndex++
                      ) ...[
                        _VoteRow(
                          party: party,
                          playerIndex: playerIndex,
                          card: card,
                        ),
                        if (playerIndex < party.players - 1) const V2Hairline(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        V2Button(
          isLast ? 'See summary →' : 'Next question →',
          background: RtwV2Colors.inkSoft,
          onPressed: party.next,
          padding: const EdgeInsets.symmetric(vertical: 18),
          radius: 16,
          fontSize: 16,
        ),
      ],
    );
  }
}

class _RevealSplitMeter extends StatelessWidget {
  const _RevealSplitMeter({
    required this.leftLabel,
    required this.rightLabel,
    required this.rightPct,
    required this.t,
  });

  final String leftLabel;
  final String rightLabel;
  final double rightPct;
  final double t;

  @override
  Widget build(BuildContext context) {
    final boundedRight = rightPct.clamp(0.0, 100.0);
    final leftPct = 100 - boundedRight;
    final animatedLeft = ((leftPct * t) / 100).clamp(0.0, 1.0);
    final animatedRight = ((boundedRight * t) / 100).clamp(0.0, 1.0);
    final split = (leftPct / 100).clamp(0.0, 1.0);

    return SizedBox(
      height: 68,
      child: Stack(
        children: [
          Container(color: const Color(0xFFE6E0D3)),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: animatedLeft,
              child: Container(
                height: 68,
                color: RtwV2Colors.meterClay.withValues(alpha: 0.9),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: animatedRight,
              child: Container(
                height: 68,
                color: RtwV2Colors.meterBlue.withValues(alpha: 0.85),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${leftLabel.toUpperCase()} ${(leftPct * t).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: v2Mono(
                      12,
                      color: animatedLeft > 0.18
                          ? Colors.white
                          : const Color(0xFF7A7466),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    '${rightLabel.toUpperCase()} ${(boundedRight * t).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: v2Mono(
                      12,
                      color: animatedRight > 0.18
                          ? Colors.white
                          : const Color(0xFF7A7466),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (t > 0.92)
            Align(
              alignment: Alignment(split * 2 - 1, 0),
              child: Container(
                width: 6,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      offset: Offset(0, 1),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoteRow extends StatelessWidget {
  const _VoteRow({
    required this.party,
    required this.playerIndex,
    required this.card,
  });

  final PartyController party;
  final int playerIndex;
  final PartyQuestion card;

  @override
  Widget build(BuildContext context) {
    // Votes map back to players: pick t belongs to (reader + t) % players.
    String? vote;
    for (final (turnIndex, pick) in party.turnPicks.indexed) {
      if ((party.readerIndex + turnIndex) % party.players == playerIndex) {
        vote = pick.side == 'a' ? card.optA : card.optB;
      }
    }
    final isReader = playerIndex == party.readerIndex;
    final isA = vote == card.optA;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      color: isReader ? RtwV2Colors.meterBlue.withValues(alpha: 0.08) : null,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: _playerColor(playerIndex),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              party.playerName(playerIndex),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: v2Sans(
                14,
                color: RtwV2Colors.inkSoft,
                weight: FontWeight.w600,
              ),
            ),
          ),
          if (vote != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: (isA ? RtwV2Colors.meterBlue : RtwV2Colors.meterClay)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                vote,
                style: v2Sans(
                  12,
                  color: isA
                      ? RtwV2Colors.blueTextDeep
                      : RtwV2Colors.clayTextDeep,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              '${party.scores[playerIndex].round()}',
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: v2Serif(19),
            ),
          ),
        ],
      ),
    );
  }
}

// ── DONE ────────────────────────────────────────────────────────────────

class _Done extends StatefulWidget {
  const _Done({required this.party, required this.rooms});

  final PartyController party;
  final RoomsController rooms;

  @override
  State<_Done> createState() => _DoneState();
}

class _DoneState extends State<_Done> {
  PartyController get party => widget.party;

  @override
  void initState() {
    super.initState();
    // Rotate played questions out of future pools (cloud-refresh rule).
    widget.rooms.markPartyPlayed(party.playedQids);
  }

  @override
  Widget build(BuildContext context) {
    final ranked = [
      for (var playerIndex = 0; playerIndex < party.players; playerIndex++)
        (playerIndex, party.scores[playerIndex]),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: V2Eyebrow(
              'Round complete',
              size: 11,
              color: RtwV2Colors.clay,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              "That's the room read.",
              style: v2Serif(34, height: 1.1, letterSpacing: -0.5),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                'You ran through ${party.deck.length} questions. Go again or head back.',
                textAlign: TextAlign.center,
                style: v2Sans(15, color: RtwV2Colors.subText, height: 1.55),
              ),
            ),
          ),
          if (!party.solo) ...[
            const SizedBox(height: 24),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: RtwV2Colors.card,
                border: Border.all(color: RtwV2Colors.border),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  for (final (rank, entry) in ranked.indexed) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      color: rank == 0
                          ? RtwV2Colors.meterBlue.withValues(alpha: 0.08)
                          : null,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text(
                              '#${rank + 1}',
                              style: v2Mono(13, letterSpacing: 0),
                            ),
                          ),
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: _playerColor(entry.$1),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              party.playerName(entry.$1),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: v2Sans(
                                15,
                                color: RtwV2Colors.inkSoft,
                                weight: rank == 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          Text('${entry.$2.round()}', style: v2Serif(19)),
                        ],
                      ),
                    ),
                    if (rank < ranked.length - 1) const V2Hairline(),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 30),
          V2Button(
            'Restart game',
            onPressed: () => _confirmRestartPartyGame(context, party),
            padding: const EdgeInsets.symmetric(vertical: 17),
            radius: 16,
            fontSize: 16,
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: party.again,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Change setup',
                textAlign: TextAlign.center,
                style: v2Sans(
                  13,
                  color: RtwV2Colors.subText,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
