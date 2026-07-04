import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../app_state.dart';
import '../../main.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// PROFILE — v2 prototype lines 610-639 (plus account actions the prototype
/// omits because it had no real auth: email + log out).
class ProfileScreenV2 extends ConsumerStatefulWidget {
  const ProfileScreenV2({super.key});

  @override
  ConsumerState<ProfileScreenV2> createState() => _ProfileScreenV2State();
}

class _ProfileScreenV2State extends ConsumerState<ProfileScreenV2> {
  TextEditingController? nameController;

  static const _avatarColors = [
    RtwV2Colors.blue,
    RtwV2Colors.clay,
    RtwV2Colors.green,
    RtwV2Colors.inkColorOption,
  ];

  @override
  void dispose() {
    nameController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(rtwControllerProvider);
    final authUser = profile.firebaseReady
        ? FirebaseAuth.instance.currentUser
        : null;
    final authSummary = _authSummary(authUser, profile);
    final authEmail = authUser?.email ?? profile.email;
    final authEmailVerified = authUser?.emailVerified ?? profile.emailVerified;
    nameController ??= TextEditingController(text: profile.displayName);
    final initial = profile.displayName.isEmpty
        ? '?'
        : profile.displayName.substring(0, 1).toUpperCase();

    return V2Scaffold(
      location: '/profile',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/rooms');
                    }
                  },
                  child: Text(
                    '← Back',
                    style: v2Sans(
                      15,
                      color: RtwV2Colors.subText,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const V2Eyebrow('Profile', size: 11, letterSpacing: 1.6),
              ],
            ),
            const SizedBox(height: 22),
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => ref.read(rtwControllerProvider).cycleAvatar(),
                    child: Container(
                      width: 84,
                      height: 84,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            _avatarColors[profile.avatarIndex %
                                _avatarColors.length],
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initial,
                        style: v2Serif(36, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(profile.displayName, style: v2Serif(25)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => ref.read(rtwControllerProvider).cycleAvatar(),
                    child: Text(
                      'Change colour',
                      style: v2Sans(
                        12,
                        color: RtwV2Colors.blue,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const V2Eyebrow('Display name'),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              style: v2Sans(16, color: RtwV2Colors.inkSoft),
              onChanged: (value) {
                if (value.trim().isNotEmpty) {
                  ref.read(rtwControllerProvider).setDisplayName(value);
                }
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: RtwV2Colors.card,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: RtwV2Colors.borderStrong),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: RtwV2Colors.blue),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _AuthSummaryCard(summary: authSummary),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: RtwV2Colors.card,
                border: Border.all(color: RtwV2Colors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily reminder',
                          style: v2Sans(
                            15,
                            color: RtwV2Colors.inkSoft,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ping me when rooms have new questions',
                          style: v2Sans(12, color: RtwV2Colors.faint),
                        ),
                      ],
                    ),
                  ),
                  V2Toggle(
                    value: profile.dailyReminder,
                    onChanged: (_) =>
                        ref.read(rtwControllerProvider).toggleReminder(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: RtwV2Colors.card,
                border: Border.all(color: RtwV2Colors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  if (authEmail.isNotEmpty && !authEmailVerified) ...[
                    _ProfileRow(
                      label: 'Verify email',
                      onTap: () => ref
                          .read(rtwControllerProvider)
                          .sendVerificationEmail(),
                    ),
                    const V2Hairline(),
                  ],
                  _ProfileRow(
                    label: 'Replay the intro',
                    onTap: () => context.go('/onboarding'),
                  ),
                  const V2Hairline(),
                  _ProfileRow(
                    label: 'Log out',
                    onTap: () async {
                      await ref.read(rtwControllerProvider).signOut();
                      if (context.mounted) context.go('/auth');
                    },
                  ),
                  const V2Hairline(),
                  _ProfileRow(
                    label: 'Clear all data',
                    color: RtwV2Colors.danger,
                    onTap: () => _confirmClear(context),
                  ),
                ],
              ),
            ),
            _ProfileStatusMessage(message: profile.lastError),
          ],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showV2Sheet(context, (sheetContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const V2Eyebrow('Clear all data', color: RtwV2Colors.danger),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Start over completely?',
              style: v2Serif(26, letterSpacing: -0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'This erases your answers, scores, streaks, and room history. '
              'There is no undo.',
              style: v2Sans(14, color: RtwV2Colors.subText, height: 1.55),
            ),
          ),
          const SizedBox(height: 18),
          V2Button(
            'Clear everything',
            background: RtwV2Colors.danger,
            padding: const EdgeInsets.symmetric(vertical: 16),
            radius: 16,
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              await ref.read(rtwControllerProvider).clearAllData();
            },
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(
                'Keep my data',
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
}

class _AuthSummary {
  const _AuthSummary({required this.method, required this.identifier});

  final String method;
  final String identifier;
}

_AuthSummary _authSummary(User? user, RtwController profile) {
  final providers =
      user?.providerData.map((info) => info.providerId).toSet() ??
      const <String>{};
  final authPhone = user?.phoneNumber;
  final authEmail = user?.email;
  final phone = authPhone != null && authPhone.isNotEmpty
      ? authPhone
      : profile.phoneNumber;
  final email = authEmail != null && authEmail.isNotEmpty
      ? authEmail
      : profile.email;
  if (phone.isNotEmpty && providers.contains('phone')) {
    return _AuthSummary(method: 'Phone', identifier: phone);
  }
  if (providers.contains('google.com')) {
    return _AuthSummary(method: 'Google', identifier: email);
  }
  if (providers.contains('apple.com')) {
    return _AuthSummary(method: 'Apple', identifier: email);
  }
  if (email.isNotEmpty) {
    return _AuthSummary(method: 'Email', identifier: email);
  }
  if (phone.isNotEmpty) {
    return _AuthSummary(method: 'Phone', identifier: phone);
  }
  return const _AuthSummary(method: 'Account', identifier: 'Signed in');
}

class _AuthSummaryCard extends StatelessWidget {
  const _AuthSummaryCard({required this.summary});

  final _AuthSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: RtwV2Colors.blue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline,
              size: 19,
              color: RtwV2Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Signed in with ${summary.method}',
                  style: v2Sans(
                    14,
                    color: RtwV2Colors.inkSoft,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  summary.identifier,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: v2Sans(12.5, color: RtwV2Colors.faint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStatusMessage extends StatelessWidget {
  const _ProfileStatusMessage({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final value = message?.trim();
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final positive =
        value.contains('sent') || value.contains('already verified');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: v2Sans(
          13,
          color: positive ? RtwV2Colors.green : RtwV2Colors.danger,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.label,
    required this.onTap,
    this.color = RtwV2Colors.inkSoft,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

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
            Text('›', style: v2Sans(16, color: RtwV2Colors.faint)),
          ],
        ),
      ),
    );
  }
}
