import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../main.dart';
import '../countdown.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// PROFILE — v2 prototype lines 610-639 (plus account actions the prototype
/// omits because it had no real auth: email + log out).
class ProfileScreenV2 extends ConsumerStatefulWidget {
  const ProfileScreenV2({super.key});

  @override
  ConsumerState<ProfileScreenV2> createState() => _ProfileScreenV2State();
}

class _ProfileScreenV2State extends ConsumerState<ProfileScreenV2>
    with WidgetsBindingObserver {
  TextEditingController? nameController;
  final FocusNode nameFocus = FocusNode();
  String? _lastProfileName;
  bool sendingVerification = false;

  static const _avatarColors = [
    RtwV2Colors.blue,
    RtwV2Colors.clay,
    RtwV2Colors.green,
    RtwV2Colors.inkColorOption,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rtwControllerProvider).refreshEmailVerificationStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    nameController?.dispose();
    nameFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(rtwControllerProvider).refreshEmailVerificationStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(rtwControllerProvider);
    final authUser = profile.firebaseReady
        ? FirebaseAuth.instance.currentUser
        : null;
    final authSummary = _authSummary(authUser, profile);
    final authEmail = authUser?.email ?? profile.email;
    final authEmailVerified =
        profile.emailVerified || (authUser?.emailVerified ?? false);
    if (nameController == null) {
      nameController = TextEditingController(text: profile.displayName);
      _lastProfileName = profile.displayName;
    } else if (_lastProfileName != profile.displayName) {
      // The Firestore profile can land after first build; resync the field
      // unless the reader is editing it (focused or already diverged).
      if (!nameFocus.hasFocus && nameController!.text == _lastProfileName) {
        nameController!.text = profile.displayName;
      }
      _lastProfileName = profile.displayName;
    }
    final initial = profile.displayName.isEmpty
        ? '?'
        : profile.displayName.substring(0, 1).toUpperCase();
    final reminderTime = DateTime(
      2000,
      1,
      1,
      profile.dailyReminderMinutes ~/ 60,
      profile.dailyReminderMinutes % 60,
    );
    final nextReset = nextEasternMidnightUtc(DateTime.now().toUtc()).toLocal();
    final reminderTimeLabel = DateFormat.jm().format(reminderTime);
    final resetTimeLabel = '${DateFormat.jm().format(nextReset)} local';

    return V2Scaffold(
      location: '/profile',
      wideWidth: double.infinity,
      child: _ProfileScrollSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                V2BackButton(
                  label: 'Back',
                  onTap: () =>
                      context.canPop() ? context.pop() : context.go('/rooms'),
                ),
                const V2Eyebrow('Profile', size: 11, letterSpacing: 1.6),
              ],
            ),
            const SizedBox(height: 22),
            Center(
              child: Column(
                children: [
                  Semantics(
                    button: true,
                    label: 'Change colour',
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(rtwControllerProvider).cycleAvatar(),
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
                        child: Transform.translate(
                          offset: const Offset(0, 2),
                          child: Text(
                            initial,
                            textAlign: TextAlign.center,
                            style: v2Serif(
                              36,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(profile.displayName, style: v2Serif(25)),
                  const SizedBox(height: 6),
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(rtwControllerProvider).cycleAvatar(),
                      child: Text(
                        'Change colour',
                        style: v2Sans(
                          12,
                          color: RtwV2Colors.blue,
                          weight: FontWeight.w600,
                        ),
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
              focusNode: nameFocus,
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
              decoration: BoxDecoration(
                color: RtwV2Colors.card,
                border: Border.all(color: RtwV2Colors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
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
                                'New questions and results',
                                style: v2Sans(12, color: RtwV2Colors.faint),
                              ),
                              if (profile.notificationsDenied &&
                                  !kIsWeb &&
                                  defaultTargetPlatform ==
                                      TargetPlatform.iOS) ...[
                                const SizedBox(height: 6),
                                Semantics(
                                  button: true,
                                  child: GestureDetector(
                                    onTap: () =>
                                        launchUrl(Uri.parse('app-settings:')),
                                    child: Text(
                                      'Notifications are off. Open iOS Settings',
                                      style: v2Sans(
                                        12,
                                        color: RtwV2Colors.blue,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
                  if (profile.dailyReminder) ...[
                    const V2Hairline(),
                    _CompactSettingRow(
                      label: 'Reminder time',
                      value: reminderTimeLabel,
                      onTap: () => _pickReminderTime(
                        context,
                        profile.dailyReminderMinutes,
                      ),
                    ),
                  ],
                  const V2Hairline(),
                  _CompactSettingRow(
                    label: 'Daily reset',
                    value: resetTimeLabel,
                    caption: 'Answers lock at this time each day',
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
                      label: sendingVerification
                          ? 'Sending verification...'
                          : 'Verify email',
                      leading: const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: RtwV2Colors.clay,
                      ),
                      onTap: sendingVerification ? null : _verifyEmail,
                    ),
                    const V2Hairline(),
                  ],
                  _ProfileRow(
                    label: 'Replay the intro',
                    onTap: () => context.go('/onboarding'),
                  ),
                  const V2Hairline(),
                  _ProfileRow(
                    label: 'Share feedback',
                    onTap: () => _showFeedbackSheet(context),
                  ),
                  const V2Hairline(),
                  _ProfileRow(
                    label: 'Safety & support',
                    onTap: () => _showSafetySheet(context),
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
                  const V2Hairline(),
                  _ProfileRow(
                    label: 'Delete account',
                    color: RtwV2Colors.danger,
                    onTap: () => _confirmDelete(context),
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

  Future<void> _verifyEmail() async {
    setState(() => sendingVerification = true);
    try {
      await ref.read(rtwControllerProvider).sendVerificationEmail();
    } finally {
      // Always release the row, even if sending throws.
      if (mounted) setState(() => sendingVerification = false);
    }
  }

  Future<void> _pickReminderTime(
    BuildContext context,
    int currentMinutes,
  ) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentMinutes ~/ 60,
        minute: currentMinutes % 60,
      ),
      helpText: 'Choose reminder time',
      cancelText: 'Cancel',
      confirmText: 'Save',
      builder: (context, child) {
        final baseTheme = Theme.of(context);
        final selectedFill = WidgetStateColor.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? RtwV2Colors.blue
              : RtwV2Colors.paperAlt;
        });
        final selectedText = WidgetStateColor.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : RtwV2Colors.inkSoft;
        });
        final pickerTheme = baseTheme.copyWith(
          colorScheme: baseTheme.colorScheme.copyWith(
            primary: RtwV2Colors.blue,
            onPrimary: Colors.white,
            surface: RtwV2Colors.card,
            onSurface: RtwV2Colors.ink,
          ),
          timePickerTheme: TimePickerThemeData(
            backgroundColor: RtwV2Colors.card,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: RtwV2Colors.borderStrong),
            ),
            helpTextStyle: v2Sans(15, color: RtwV2Colors.subText),
            hourMinuteColor: selectedFill,
            hourMinuteTextColor: selectedText,
            hourMinuteTextStyle: v2Serif(54, weight: FontWeight.w500),
            hourMinuteShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            dayPeriodColor: selectedFill,
            dayPeriodTextColor: selectedText,
            dayPeriodTextStyle: v2Sans(15, weight: FontWeight.w600),
            dayPeriodBorderSide: const BorderSide(
              color: RtwV2Colors.borderStrong,
            ),
            dayPeriodShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            dialBackgroundColor: RtwV2Colors.paperAlt,
            dialHandColor: RtwV2Colors.blue,
            dialTextColor: WidgetStateColor.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? Colors.white
                  : RtwV2Colors.inkSoft;
            }),
            dialTextStyle: v2Sans(16),
            entryModeIconColor: RtwV2Colors.blue,
            cancelButtonStyle: TextButton.styleFrom(
              foregroundColor: RtwV2Colors.subText,
              textStyle: v2Sans(14, weight: FontWeight.w600),
            ),
            confirmButtonStyle: TextButton.styleFrom(
              foregroundColor: RtwV2Colors.blue,
              textStyle: v2Sans(14, weight: FontWeight.w700),
            ),
          ),
        );
        return Theme(data: pickerTheme, child: child!);
      },
    );
    if (selected == null) return;
    await ref
        .read(rtwControllerProvider)
        .setDailyReminderMinutes((selected.hour * 60) + selected.minute);
  }

  void _showSafetySheet(BuildContext context) {
    showV2Sheet(context, (sheetContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const V2Eyebrow('Safety & support'),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('We respond within 24 hours.', style: v2Serif(26)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Custom questions are shared only inside private rooms and show '
              'the submitter’s name. Use the flag on a custom question to '
              'remove and report it immediately.',
              style: v2Sans(14, color: RtwV2Colors.subText, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'mike@readtheworld.today',
            style: v2Sans(15, weight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          V2Button(
            'Email safety support',
            onPressed: () => launchUrl(
              Uri.parse(
                'mailto:mike@readtheworld.today?subject=Read%20the%20World%20safety%20report',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://readtheworld.today/terms'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Terms & community standards'),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      );
    });
  }

  void _showFeedbackSheet(BuildContext context) {
    final controller = TextEditingController();
    var submitting = false;
    String? error;
    showV2Sheet(context, (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> submit() async {
            setSheetState(() {
              submitting = true;
              error = null;
            });
            final sent = await ref
                .read(rtwControllerProvider)
                .submitFeedback(controller.text);
            if (!sheetContext.mounted) return;
            if (sent) {
              Navigator.of(sheetContext).pop();
              return;
            }
            setSheetState(() {
              submitting = false;
              error = ref.read(rtwControllerProvider).lastError;
            });
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const V2Eyebrow('Feedback'),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tell us what to fix.',
                  style: v2Serif(26, letterSpacing: -0.3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Ideas, bugs, confusing bits, anything.',
                  style: v2Sans(14, color: RtwV2Colors.subText, height: 1.45),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                minLines: 4,
                maxLines: 7,
                maxLength: 4000,
                textInputAction: TextInputAction.newline,
                style: v2Sans(15, color: RtwV2Colors.inkSoft, height: 1.45),
                decoration: InputDecoration(
                  hintText: 'Write feedback...',
                  hintStyle: v2Sans(15, color: RtwV2Colors.faint),
                  counterStyle: v2Sans(11, color: RtwV2Colors.faint),
                  filled: true,
                  fillColor: RtwV2Colors.card,
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: RtwV2Colors.borderStrong,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: RtwV2Colors.blue),
                  ),
                ),
              ),
              if (error != null && error!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(error!, style: v2Sans(13, color: RtwV2Colors.danger)),
              ],
              const SizedBox(height: 12),
              V2Button(
                submitting ? 'Sending...' : 'Send feedback',
                padding: const EdgeInsets.symmetric(vertical: 16),
                radius: 16,
                onPressed: submitting ? null : submit,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(sheetContext).pop(),
                  child: Text(
                    'Cancel',
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
        },
      );
    }).whenComplete(controller.dispose);
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
              'This erases your answers, scores, and room history. There is no undo.',
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

  void _confirmDelete(BuildContext context) {
    var deleting = false;
    String? error;
    showV2Sheet(context, (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> deleteAccount() async {
            setSheetState(() {
              deleting = true;
              error = null;
            });
            final deleted = await ref
                .read(rtwControllerProvider)
                .deleteAccount();
            if (!sheetContext.mounted) return;
            if (!deleted) {
              setSheetState(() {
                deleting = false;
                error = ref.read(rtwControllerProvider).lastError;
              });
              return;
            }
            Navigator.of(sheetContext).pop();
            if (mounted) this.context.go('/auth');
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const V2Eyebrow('Delete account', color: RtwV2Colors.danger),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Permanently delete your account?',
                  style: v2Serif(26, letterSpacing: -0.3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'This permanently deletes your profile, answers, scores, room history, and sign-in details. There is no undo.',
                  style: v2Sans(14, color: RtwV2Colors.subText, height: 1.55),
                ),
              ),
              if (error != null && error!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(error!, style: v2Sans(13, color: RtwV2Colors.danger)),
              ],
              const SizedBox(height: 18),
              V2Button(
                deleting ? 'Deleting account...' : 'Delete my account',
                background: RtwV2Colors.danger,
                padding: const EdgeInsets.symmetric(vertical: 16),
                radius: 16,
                onPressed: deleting ? null : deleteAccount,
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: deleting
                      ? null
                      : () => Navigator.of(sheetContext).pop(),
                  child: Text(
                    'Keep my account',
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
        },
      );
    });
  }
}

class _ProfileScrollSurface extends StatelessWidget {
  const _ProfileScrollSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('profile-scroll-view'),
      child: Center(
        child: ConstrainedBox(
          key: const ValueKey('profile-content'),
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
            child: child,
          ),
        ),
      ),
    );
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

class _CompactSettingRow extends StatelessWidget {
  const _CompactSettingRow({
    required this.label,
    required this.value,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: v2Sans(
                    14,
                    color: RtwV2Colors.inkSoft,
                    weight: FontWeight.w600,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: v2Sans(11.5, color: RtwV2Colors.faint)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: v2Sans(
                13.5,
                color: onTap == null ? RtwV2Colors.subText : RtwV2Colors.blue,
                weight: FontWeight.w600,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 5),
            Text('›', style: v2Sans(16, color: RtwV2Colors.blue)),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
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
        value.contains('sent') ||
        value.contains('saved') ||
        value.contains('already verified');
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
    this.leading,
    this.color = RtwV2Colors.inkSoft,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
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
            Expanded(
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: v2Sans(15, color: color),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('›', style: v2Sans(16, color: RtwV2Colors.faint)),
          ],
        ),
      ),
    );
  }
}
