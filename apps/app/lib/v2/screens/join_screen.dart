import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../sheets/room_sheets.dart' show showMatureConfirmSheet;
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// Landing for shared room links (`rtw.codes/CODE` → `/join/CODE`): shows
/// the room preview, runs the After Dark consent when needed, and joins.
class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  Map<String, dynamic>? preview;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
  }

  Future<void> _loadPreview() async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('joinRoom')
          .call({'code': widget.code.toUpperCase(), 'previewOnly': true});
      if (!mounted) return;
      setState(() => preview = Map<String, dynamic>.from(result.data as Map));
    } on FirebaseFunctionsException catch (functionsError) {
      if (!mounted) return;
      setState(() => error = functionsError.message ?? functionsError.code);
    } catch (genericError) {
      if (!mounted) return;
      setState(() => error = genericError.toString());
    }
  }

  Future<void> _join() async {
    final tier = RoomTierWire.parse(preview?['tier']?.toString());
    if (tier == RoomTier.mature) {
      final confirmed = await showMatureConfirmSheet(context);
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final rooms = ref.read(roomsControllerProvider);
    final roomId = await rooms.joinRoom(widget.code);
    if (!mounted) return;
    if (roomId == null) {
      setState(() {
        busy = false;
        error = rooms.lastError ?? 'Could not join that room.';
      });
      return;
    }
    context.go('/rooms/$roomId');
  }

  @override
  Widget build(BuildContext context) {
    final tier = RoomTierWire.parse(preview?['tier']?.toString());
    final alreadyMember = preview?['alreadyMember'] == true;
    return V2Scaffold(
      location: '/join/${widget.code}',
      showNav: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 72, 26, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                text: 'read the world',
                style: v2Serif(21, letterSpacing: -0.5),
                children: [
                  TextSpan(text: '.', style: v2Serif(21, color: RtwV2Colors.clay)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            const V2Eyebrow('Room invite', color: RtwV2Colors.clay, letterSpacing: 1.6),
            const SizedBox(height: 10),
            Text(
              error != null
                  ? 'This invite is unavailable.'
                  : preview == null
                      ? 'Opening your invite…'
                      : "You're invited in.",
              style: v2Serif(34, height: 1.08, letterSpacing: -0.6),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: v2Sans(14, color: RtwV2Colors.subText, height: 1.5)),
            ],
            if (preview != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: RtwV2Colors.card,
                  border: Border.all(color: RtwV2Colors.border),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: RtwV2Colors.roomColor(preview!['color']?.toString()),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        (preview!['name']?.toString() ?? '?').substring(0, 1),
                        style: v2Serif(19, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(preview!['name']?.toString() ?? 'Room', style: v2Serif(19)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (tier != RoomTier.normal) ...[
                                TierChip(tier: tier),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                '${preview!['memberCount'] ?? 0} members',
                                style: v2Sans(12.5, color: RtwV2Colors.muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              V2Button(
                busy
                    ? 'Joining…'
                    : alreadyMember
                        ? 'Open room →'
                        : 'Join room →',
                onPressed: busy
                    ? null
                    : alreadyMember
                        ? () => context.go('/rooms/${preview!['roomId']}')
                        : _join,
                padding: const EdgeInsets.symmetric(vertical: 17),
                radius: 16,
                fontSize: 16,
              ),
            ],
            const Spacer(),
            Center(
              child: TextButton(
                onPressed: () => context.go('/rooms'),
                child: Text(
                  error != null ? 'Back to your rooms' : 'Not now',
                  style: v2Sans(14, color: RtwV2Colors.subText, weight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
