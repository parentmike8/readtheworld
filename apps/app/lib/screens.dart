import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'firestore_mappers.dart';
import 'main.dart';
import 'models.dart';
import 'scoring.dart';
import 'theme/tokens.dart';
import 'widgets.dart';

final Uri _marketingSiteUri = Uri.parse('https://readtheworld.today');

double _screenTopPadding(BuildContext context, double designTop) {
  if (kIsWeb) return designTop;
  final safeTop = MediaQuery.paddingOf(context).top;
  return math.max(20.0, designTop - safeTop);
}

Future<void> _openMarketingSite() async {
  await launchUrl(
    _marketingSiteUri,
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    webOnlyWindowName: '_self',
  );
}

Future<void> _showInviteSheet(BuildContext context, String url) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RtwShareSheet(
      eyebrow: 'Invite a friend',
      title: 'Compare your reads.',
      body:
          'They join your leaderboard and you compare Read Scores. Your answers stay private unless you choose to share them.',
      url: url,
      primaryLabel: 'Share invite link',
      shareText: 'Join my Read the World leaderboard: $url',
    ),
  );
}

Future<void> _showResultShareSheet(
  BuildContext context, {
  required HistoryEntry entry,
  required int score,
  required int worldShare,
  required int guess,
  required String url,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RtwShareSheet(
      eyebrow: 'Share your result',
      title: null,
      body: null,
      url: url,
      primaryLabel: 'Share',
      secondaryLabel: 'Copy link',
      shareText: 'I scored $score/100 on Read the World. $url',
      preview: _ResultSharePreview(
        entry: entry,
        score: score,
        worldShare: worldShare,
        guess: guess,
      ),
    ),
  );
}

class _RtwShareSheet extends StatefulWidget {
  const _RtwShareSheet({
    required this.eyebrow,
    required this.url,
    required this.primaryLabel,
    required this.shareText,
    this.title,
    this.body,
    this.secondaryLabel = 'Copy',
    this.preview,
  });

  final String eyebrow;
  final String? title;
  final String? body;
  final String url;
  final String primaryLabel;
  final String secondaryLabel;
  final String shareText;
  final Widget? preview;

  @override
  State<_RtwShareSheet> createState() => _RtwShareSheetState();
}

class _RtwShareSheetState extends State<_RtwShareSheet> {
  bool copied = false;

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => copied = true);
  }

  Future<void> _share() async {
    Navigator.of(context).pop();
    await SharePlus.instance.share(ShareParams(text: widget.shareText));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
        decoration: const BoxDecoration(
          color: RtwColors.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 50,
              offset: Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8D2C5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Eyebrow(widget.eyebrow),
            if (widget.title != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.title!,
                style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                  fontSize: 26,
                  height: 1.12,
                ),
              ),
            ],
            if (widget.body != null) ...[
              const SizedBox(height: 10),
              Text(
                widget.body!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(fontSize: 14, height: 1.55),
              ),
            ],
            if (widget.preview != null) ...[
              const SizedBox(height: 14),
              widget.preview!,
            ],
            const SizedBox(height: 16),
            if (widget.preview == null)
              _ShareLinkRow(
                url: widget.url,
                copyLabel: copied ? 'Copied' : widget.secondaryLabel,
                onCopy: _copyLink,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: RtwButton(
                      label: copied ? 'Copied' : widget.secondaryLabel,
                      secondary: true,
                      onPressed: _copyLink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RtwButton(
                      label: widget.primaryLabel,
                      onPressed: _share,
                    ),
                  ),
                ],
              ),
            if (widget.preview == null) ...[
              const SizedBox(height: 14),
              RtwButton(label: widget.primaryLabel, onPressed: _share),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShareLinkRow extends StatelessWidget {
  const _ShareLinkRow({
    required this.url,
    required this.copyLabel,
    required this.onCopy,
  });

  final String url;
  final String copyLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final displayUrl = url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: RtwColors.card,
        border: Border.all(color: RtwColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                fontSize: 14,
                letterSpacing: 0,
                color: const Color(0xFF5C584F),
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onCopy,
            style: TextButton.styleFrom(
              backgroundColor: RtwColors.ink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(copyLabel),
          ),
        ],
      ),
    );
  }
}

class _ResultSharePreview extends StatelessWidget {
  const _ResultSharePreview({
    required this.entry,
    required this.score,
    required this.worldShare,
    required this.guess,
  });

  final HistoryEntry entry;
  final int score;
  final int worldShare;
  final int guess;

  @override
  Widget build(BuildContext context) {
    final fill = worldShare.clamp(0, 100) / 100;
    final guessPosition = guess.clamp(0, 100) / 100;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: RtwColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'DAILY READ',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: RtwColors.clay,
                  fontSize: 10,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              Text(
                entry.question.dateLabel,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: const Color(0xFF8E887C),
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            entry.question.prompt,
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
              color: RtwColors.paper,
              fontSize: 19,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$score',
                style: Theme.of(context).textTheme.displayLarge!.copyWith(
                  color: RtwColors.paper,
                  fontSize: 52,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '/ 100',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: const Color(0xFF8E887C),
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'read accuracy',
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: RtwColors.clay,
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final pinLeft = (constraints.maxWidth * guessPosition - 1).clamp(
                0.0,
                constraints.maxWidth - 2,
              );
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: fill,
                      minHeight: 10,
                      color: RtwColors.clay,
                      backgroundColor: const Color(0xFF3A372F),
                    ),
                  ),
                  Positioned(
                    left: pinLeft,
                    top: -4,
                    child: Container(
                      width: 2,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9AB0E0),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Text(
                'YOU $guess%',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: const Color(0xFF8E887C),
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                'WORLD $worldShare%',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: const Color(0xFF8E887C),
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool creating = false;
  bool obscure = true;
  bool authBusy = false;
  bool handoffStarted = false;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final mode = Uri.base.queryParameters['mode']?.trim().toLowerCase();
    if (mode == 'create' || mode == 'signup') {
      creating = true;
      obscure = false;
    }
    final email = Uri.base.queryParameters['email'];
    if (email != null && email.isNotEmpty) {
      emailController.text = email;
    }
    final handoffCode = Uri.base.queryParameters['handoff'];
    if (handoffCode != null && handoffCode.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _redeemHandoff(handoffCode.trim());
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _runAuth(Future<bool> Function() action) async {
    if (authBusy) return;
    setState(() => authBusy = true);
    final ok = await action();
    final route = ok
        ? await ref.read(rtwControllerProvider).postAuthRoute()
        : null;
    if (!mounted) return;
    setState(() => authBusy = false);
    if (route != null) context.go(route);
  }

  Future<void> _redeemHandoff(String code) async {
    if (handoffStarted || authBusy) return;
    setState(() {
      handoffStarted = true;
      authBusy = true;
    });
    final route = await ref
        .read(rtwControllerProvider)
        .redeemAuthHandoff(
          code,
          fallbackRoute: Uri.base.queryParameters['next'],
        );
    if (!mounted) return;
    setState(() => authBusy = false);
    if (route != null) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(rtwControllerProvider);
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final isWide = width >= 820;
    final useWebPhoneSurface = kIsWeb && !isWide;
    final mobileWidth = rtwMobileSurfaceWidth(size);

    Widget authForm({bool mobile = false}) {
      return _AuthForm(
        creating: creating,
        obscure: obscure,
        busy: authBusy,
        errorText: controller.lastError,
        emailController: emailController,
        passwordController: passwordController,
        mobile: mobile,
        onToggleMode: () => setState(() {
          creating = !creating;
          obscure = !creating;
        }),
        onToggleObscure: () => setState(() => obscure = !obscure),
        onSubmitEmail: () => _runAuth(
          () => ref
              .read(rtwControllerProvider)
              .authenticateWithEmail(
                email: emailController.text,
                password: passwordController.text,
                creating: creating,
              ),
        ),
        onGoogle: () =>
            _runAuth(ref.read(rtwControllerProvider).authenticateWithGoogle),
        onApple: () =>
            _runAuth(ref.read(rtwControllerProvider).authenticateWithApple),
        onForgotPassword: () => ref
            .read(rtwControllerProvider)
            .sendPasswordReset(emailController.text),
      );
    }

    if (isWide) {
      return Scaffold(
        backgroundColor: RtwColors.paper,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelWidth = math.min(1000.0, constraints.maxWidth - 48);
              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: Scrollbar(
                  thumbVisibility: true,
                  interactive: true,
                  notificationPredicate: (notification) =>
                      notification.depth == 0 &&
                      notification.metrics.axis == Axis.vertical,
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Container(
                          width: panelWidth,
                          height: 640,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x2928241C),
                                blurRadius: 60,
                                offset: Offset(0, 24),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              _AuthBrandPanel(creating: creating),
                              Expanded(
                                child: ColoredBox(
                                  color: RtwColors.paper,
                                  child: Center(
                                    child: SizedBox(
                                      width: 380,
                                      child: authForm(),
                                    ),
                                  ),
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
          ),
        ),
      );
    }

    Widget mobileAuthContent(double availableHeight) {
      final formHeight = (availableHeight - 72).clamp(720.0, 780.0).toDouble();
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: mobileWidth,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              38,
              _screenTopPadding(context, 84),
              38,
              36,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: formHeight),
              child: authForm(mobile: true),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: useWebPhoneSurface
          ? RtwColors.deviceBackdrop
          : RtwColors.paper,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = ColoredBox(
              color: RtwColors.paper,
              child: mobileAuthContent(constraints.maxHeight),
            );
            return Align(
              alignment: useWebPhoneSurface
                  ? Alignment.topCenter
                  : Alignment.topLeft,
              child: SizedBox(
                width: mobileWidth,
                height: constraints.maxHeight,
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AuthBrandPanel extends StatelessWidget {
  const _AuthBrandPanel({required this.creating});

  final bool creating;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 440,
      color: RtwColors.ink,
      padding: const EdgeInsets.fromLTRB(44, 46, 44, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Read the World marketing site',
            child: Tooltip(
              message: 'Back to readtheworld.today',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openMarketingSite,
                  child: const RtwLogo(onDark: true),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (creating)
            UnconstrainedBox(
              alignment: Alignment.centerLeft,
              constrainedAxis: Axis.vertical,
              child: SizedBox(
                width: 380,
                child: Text(
                  'Start reading the world.',
                  maxLines: 1,
                  softWrap: false,
                  style: Theme.of(context).textTheme.headlineLarge!.copyWith(
                    color: RtwColors.paper,
                    fontSize: 36,
                    height: 1.1,
                  ),
                ),
              ),
            )
          else
            Text(
              'Welcome back to the daily read.',
              style: Theme.of(context).textTheme.headlineLarge!.copyWith(
                color: RtwColors.paper,
                fontSize: 36,
                height: 1.1,
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: creating ? 330 : null,
            child: Text(
              creating
                  ? 'One shared question a day. Predict how the world answers and build your Read Score.'
                  : "Your streak, your Read Score, and today's question are waiting.",
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: const Color(0xFFB7B1A4),
                height: 1.55,
              ),
            ),
          ),
          if (!creating) ...[
            const SizedBox(height: 30),
            const _AuthMiniSpectrum(),
            SizedBox(
              width: 300,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'YOUR READ',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: const Color(0xFF8E887C),
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'THE WORLD',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: const Color(0xFF8E887C),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthMiniSpectrum extends StatelessWidget {
  const _AuthMiniSpectrum();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 18,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF3A372F),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          FractionallySizedBox(
            widthFactor: 0.64,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFFC58A5E),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Positioned(
            left: 190,
            top: 0,
            bottom: 0,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF8FA6D6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    required this.creating,
    required this.obscure,
    required this.busy,
    required this.errorText,
    required this.emailController,
    required this.passwordController,
    required this.onToggleMode,
    required this.onToggleObscure,
    required this.onSubmitEmail,
    required this.onGoogle,
    required this.onApple,
    required this.onForgotPassword,
    this.mobile = false,
  });

  final bool creating;
  final bool obscure;
  final bool busy;
  final String? errorText;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onToggleMode;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmitEmail;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onForgotPassword;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final title = creating ? 'Create your account.' : 'Welcome back.';
    final subtitle = creating
        ? 'Free, forever. One question a day.'
        : 'Sign in to keep your streak going.';
    return Column(
      mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: mobile
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mobile) ...[const RtwLogo(), const SizedBox(height: 40)],
        Text(
          title,
          style: Theme.of(context).textTheme.headlineLarge!.copyWith(
            fontSize: mobile ? 34 : 32,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 10),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 30),
        const Eyebrow('Email'),
        const SizedBox(height: 8),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          enabled: !busy,
          decoration: InputDecoration(hintText: 'you@email.com'),
        ),
        const SizedBox(height: 18),
        if (!mobile || creating)
          Row(
            children: [
              Eyebrow(creating ? 'Choose a password' : 'Password'),
              const Spacer(),
              if (!creating)
                TextButton(
                  onPressed: busy ? null : onForgotPassword,
                  style: _authTextButtonStyle(),
                  child: const Text('Forgot?'),
                ),
            ],
          )
        else
          const Eyebrow('Password'),
        const SizedBox(height: 8),
        TextField(
          controller: passwordController,
          obscureText: obscure,
          enabled: !busy,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitEmail(),
          decoration: InputDecoration(
            hintText: creating ? 'at least 8 characters' : '••••••••',
            suffixIcon: TextButton(
              onPressed: onToggleObscure,
              child: Text(obscure ? 'Show' : 'Hide'),
            ),
          ),
        ),
        if (mobile && !creating) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: busy ? null : onForgotPassword,
              style: _authTextButtonStyle(),
              child: const Text('Forgot password?'),
            ),
          ),
        ],
        SizedBox(height: mobile ? 22 : 24),
        RtwButton(
          label: busy
              ? 'Working...'
              : creating
              ? 'Create account'
              : 'Sign in',
          onPressed: busy ? null : onSubmitEmail,
        ),
        if (errorText != null && errorText!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            errorText!,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: errorText!.contains('sent')
                  ? RtwColors.blue
                  : RtwColors.clay,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (creating) ...[
          const SizedBox(height: 12),
          Center(
            child: Text(
              'By continuing you agree to our Terms & Privacy Policy.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: 12,
                color: RtwColors.faint,
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: Divider(color: RtwColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  fontSize: 10,
                  color: RtwColors.faint,
                ),
              ),
            ),
            const Expanded(child: Divider(color: RtwColors.border)),
          ],
        ),
        const SizedBox(height: 12),
        mobile
            ? Column(
                children: [
                  _SocialButton(
                    label: 'Continue with Google',
                    mark: 'G',
                    compact: false,
                    onTap: busy ? null : onGoogle,
                  ),
                  const SizedBox(height: 10),
                  _SocialButton(
                    label: 'Continue with Apple',
                    mark: 'Apple',
                    compact: false,
                    onTap: busy ? null : onApple,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: _SocialButton(
                      label: 'Google',
                      mark: 'G',
                      compact: true,
                      onTap: busy ? null : onGoogle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SocialButton(
                      label: 'Apple',
                      mark: 'Apple',
                      compact: true,
                      onTap: busy ? null : onApple,
                    ),
                  ),
                ],
              ),
        SizedBox(height: mobile ? 196 : 28),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              Text(
                creating
                    ? 'Already have an account? '
                    : 'New to Read the World? ',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              InkWell(
                onTap: onToggleMode,
                child: Text(
                  creating ? 'Sign in' : 'Create an account',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: RtwColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.mark,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final String mark;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(compact ? 47 : 50),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 13 : 14,
        ),
        backgroundColor: RtwColors.card,
        foregroundColor: RtwColors.ink,
        side: const BorderSide(color: RtwColors.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 13 : 14),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (mark == 'Apple')
            Icon(Icons.apple, size: compact ? 18 : 19)
          else if (mark == 'G')
            Image.asset(
              'assets/icons/google.png',
              width: compact ? 18 : 19,
              height: compact ? 18 : 19,
              filterQuality: FilterQuality.high,
            )
          else
            Text(
              mark,
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontSize: compact ? 17 : 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          SizedBox(width: compact ? 8 : 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: compact ? 14 : 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

ButtonStyle _authTextButtonStyle() {
  return TextButton.styleFrom(
    foregroundColor: RtwColors.subText,
    padding: EdgeInsets.zero,
    minimumSize: const Size(0, 0),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  );
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.initialStep = 0});

  final int initialStep;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late int step;
  DateTime? birthdate;
  String? gender;
  String? country;

  bool get _editingAbout => widget.initialStep == 1;
  bool get _canFinishAbout =>
      birthdate != null && gender != null && country != null;

  static final _countries = [
    'Canada',
    'United States',
    'United Kingdom',
    'Australia',
    'Germany',
    'France',
    'India',
    'Brazil',
    'Japan',
    'Nigeria',
    'Mexico',
    'Other',
    'Prefer not to say',
  ];

  @override
  void initState() {
    super.initState();
    final controller = ref.read(rtwControllerProvider);
    step = widget.initialStep;
    birthdate = controller.birthdate;
    gender = controller.gender;
    country = controller.country;
  }

  String get _birthdateLabel {
    final value = birthdate;
    if (value == null) return 'Select your date of birth';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  Future<void> _showBirthdatePicker() async {
    var pending = birthdate ?? DateTime(1989);
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: RtwColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            final media = MediaQuery.of(context);
            final availableSheetHeight =
                media.size.height - media.viewInsets.bottom - 16;
            final maxSheetHeight = availableSheetHeight > 0
                ? availableSheetHeight
                : media.size.height;
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxSheetHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: RtwColors.borderStrong,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Eyebrow('Date of birth'),
                              const SizedBox(height: 8),
                              Text(
                                'Choose a date',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge!
                                    .copyWith(fontSize: 28),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Used only for private comparison insights.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: RtwColors.card,
                                    border: Border.all(color: RtwColors.border),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: CalendarDatePicker(
                                    initialDate: pending,
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime.now(),
                                    onDateChanged: (value) {
                                      sheetSetState(() => pending = value);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      RtwButton(
                        label: 'Use this date',
                        onPressed: () => Navigator.pop(sheetContext, pending),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (picked != null) {
      setState(() => birthdate = picked);
    }
  }

  Future<void> _showCountryPicker() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RtwColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: RtwColors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Eyebrow('Country'),
                const SizedBox(height: 8),
                Text(
                  'Where are you reading from?',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineLarge!.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: RtwColors.card,
                      border: Border.all(color: RtwColors.border),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _countries.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFFEFEAE0)),
                        itemBuilder: (context, index) {
                          final value = _countries[index];
                          final selected = value == country;
                          return ListTile(
                            title: Text(
                              value,
                              style: Theme.of(context).textTheme.bodyLarge!
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            trailing: selected
                                ? const Icon(
                                    Icons.check,
                                    size: 18,
                                    color: RtwColors.blue,
                                  )
                                : null,
                            onTap: () => Navigator.pop(sheetContext, value),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => country = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return AppScaffold(
      location: '/onboarding',
      showBottomNav: false,
      navigationLocked: true,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          isWide ? 76 : _screenTopPadding(context, 96),
          24,
          40,
        ),
        children: [
          if (step == 0) ...[
            const RtwLogo(),
            const SizedBox(height: 20),
            Text(
              'How well do you know what everyone else thinks?',
              style: Theme.of(context).textTheme.headlineLarge!.copyWith(
                fontSize: isWide ? 44 : 40,
                height: 1.04,
              ),
            ),
            const SizedBox(height: 30),
            const _OnboardingPoint(
              number: '01',
              text: 'One shared question, every day.',
            ),
            const SizedBox(height: 16),
            const _OnboardingPoint(
              number: '02',
              text: 'Answer it yourself, then predict how the world answered.',
            ),
            const SizedBox(height: 16),
            const _OnboardingPoint(
              number: '03',
              text: 'Points are for the read, not the opinion.',
            ),
            const SizedBox(height: 48),
            RtwButton(
              label: 'Get started',
              icon: Icons.arrow_forward,
              onPressed: () {
                if (settings.onboardingDemographics) {
                  setState(() => step = 1);
                } else {
                  context.go('/today');
                }
              },
            ),
          ] else ...[
            const Eyebrow('About you'),
            const SizedBox(height: 11),
            Text(
              'A little about you.',
              style: Theme.of(
                context,
              ).textTheme.headlineLarge!.copyWith(fontSize: 30, height: 1.1),
            ),
            const SizedBox(height: 11),
            Text(
              'Powers your "how you compare to people like you" insights. Always private; change it anytime.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            const Eyebrow('Date of birth'),
            const SizedBox(height: 12),
            _SelectField(
              label: _birthdateLabel,
              selected: birthdate != null,
              icon: Icons.calendar_today_outlined,
              onTap: _showBirthdatePicker,
            ),
            const SizedBox(height: 24),
            const Eyebrow('Gender'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in [
                  'Woman',
                  'Man',
                  'Non-binary',
                  'Prefer not to say',
                ])
                  _ChipButton(
                    label: value,
                    selected: gender == value,
                    onTap: () => setState(() => gender = value),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Eyebrow('Country'),
            const SizedBox(height: 12),
            _SelectField(
              label: country ?? 'Select your country',
              selected: country != null,
              onTap: _showCountryPicker,
            ),
            const SizedBox(height: 32),
            if (_canFinishAbout)
              RtwButton(
                label: _editingAbout ? 'Save changes' : 'Finish setup',
                icon: Icons.arrow_forward,
                onPressed: () async {
                  final controller = ref.read(rtwControllerProvider);
                  await controller.saveDemographics(
                    birthdate: birthdate,
                    gender: gender,
                    country: country,
                  );
                  if (!context.mounted) return;
                  context.go(
                    _editingAbout
                        ? '/account'
                        : controller.consumePostOnboardingRoute(),
                  );
                },
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFEAE0),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Fill in each to continue',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: RtwColors.faint,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _OnboardingPoint extends StatelessWidget {
  const _OnboardingPoint({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: Theme.of(
            context,
          ).textTheme.labelSmall!.copyWith(color: RtwColors.blue, fontSize: 13),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
              color: const Color(0xFF3F3C35),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? RtwColors.blueTint : RtwColors.card,
        foregroundColor: selected ? RtwColors.blue : const Color(0xFF5C584F),
        side: BorderSide(
          color: selected ? RtwColors.blue : RtwColors.borderStrong,
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon = Icons.expand_more,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: RtwColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RtwColors.borderStrong),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: selected ? RtwColors.ink : RtwColors.faint,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Icon(icon, size: 18, color: RtwColors.muted),
          ],
        ),
      ),
    );
  }
}

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(rtwControllerProvider);
    if (!controller.hasTodayQuestion) {
      return _LiveDataEmptyState(
        location: '/today',
        title: "Loading today's question.",
        body:
            controller.lastError ??
            'Read the World is fetching the live question.',
      );
    }
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return AppScaffold(
      location: '/today',
      maxWidth: 600,
      child: isWide
          ? ListView(
              padding: const EdgeInsets.fromLTRB(0, 52, 0, 48),
              children: [
                _TodayQuestionContent(
                  question: controller.today,
                  selectedOptionId: controller.selectedOptionId,
                  desktop: true,
                  onSelect: (optionId) =>
                      ref.read(rtwControllerProvider).selectOption(optionId),
                ),
                const SizedBox(height: 24),
                if (controller.selectedOptionId != null)
                  _TodayCtaButton(
                    desktop: true,
                    onPressed: () => context.go('/today/predict'),
                  ),
              ],
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    _screenTopPadding(context, 78),
                    24,
                    30,
                  ),
                  sliver: SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TodayQuestionContent(
                          question: controller.today,
                          selectedOptionId: controller.selectedOptionId,
                          desktop: false,
                          onSelect: (optionId) => ref
                              .read(rtwControllerProvider)
                              .selectOption(optionId),
                        ),
                        const Spacer(),
                        if (controller.selectedOptionId != null)
                          _TodayCtaButton(
                            desktop: false,
                            onPressed: () => context.go('/today/predict'),
                          ),
                        if (controller.selectedOptionId != null)
                          const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _LiveDataEmptyState extends StatelessWidget {
  const _LiveDataEmptyState({
    required this.location,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.showBottomNav = true,
  });

  final String location;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showBottomNav;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return AppScaffold(
      location: location,
      maxWidth: 560,
      showBottomNav: showBottomNav,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          isWide ? 92 : _screenTopPadding(context, 92),
          24,
          34,
        ),
        children: [
          const Eyebrow('Live data'),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineLarge!.copyWith(fontSize: 34, height: 1.1),
          ),
          const SizedBox(height: 12),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: RtwButton(
                label: actionLabel!,
                fullWidth: false,
                compact: true,
                onPressed: onAction,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayQuestionContent extends StatelessWidget {
  const _TodayQuestionContent({
    required this.question,
    required this.selectedOptionId,
    required this.desktop,
    required this.onSelect,
  });

  final RtwQuestion question;
  final String? selectedOptionId;
  final bool desktop;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Eyebrow('${question.category} · ${question.dateLabel}'),
        SizedBox(height: desktop ? 16 : 18),
        Text(
          'Can you read the world today?',
          style: Theme.of(context).textTheme.headlineLarge!.copyWith(
            fontSize: desktop ? 42 : 34,
            height: desktop ? 1.05 : 1.12,
          ),
        ),
        SectionRule(top: desktop ? 34 : 58, bottom: desktop ? 30 : 38),
        Eyebrow('The question', fontSize: desktop ? 10 : null),
        SizedBox(height: desktop ? 12 : 13),
        Text(
          question.prompt,
          style: Theme.of(context).textTheme.headlineMedium!.copyWith(
            fontSize: desktop ? 31 : 26,
            height: desktop ? 1.2 : 1.26,
          ),
        ),
        SizedBox(height: desktop ? 30 : 26),
        for (final option in question.options)
          AnswerTile(
            option: option,
            selected: selectedOptionId == option.id,
            onTap: () => onSelect(option.id),
          ),
      ],
    );
  }
}

class _TodayCtaButton extends StatelessWidget {
  const _TodayCtaButton({required this.desktop, required this.onPressed});

  final bool desktop;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: RtwColors.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: RtwColors.borderStrong,
        disabledForegroundColor: RtwColors.muted,
        minimumSize: Size.zero,
        padding: EdgeInsets.symmetric(
          horizontal: desktop ? 40 : 18,
          vertical: desktop ? 20 : 18,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(desktop ? 15 : 16),
        ),
        textStyle: TextStyle(
          fontSize: desktop ? 18 : 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      child: const Text('Now read the world \u2192'),
    );
    if (desktop) {
      return Align(alignment: Alignment.centerLeft, child: button);
    }
    return SizedBox(width: double.infinity, child: button);
  }
}

class PredictScreen extends ConsumerWidget {
  const PredictScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(rtwControllerProvider);
    if (!controller.hasTodayQuestion || controller.selectedOptionId == null) {
      return _LiveDataEmptyState(
        location: '/today/predict',
        title: 'Choose an answer first.',
        body: 'The prediction step unlocks after a live answer is selected.',
        actionLabel: "Back to today's question",
        onAction: () => context.go('/today'),
        showBottomNav: false,
      );
    }
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return AppScaffold(
      location: '/today/predict',
      maxWidth: 600,
      showBottomNav: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isWide ? 0 : 24,
              isWide ? 52 : _screenTopPadding(context, 78),
              isWide ? 0 : 24,
              30,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - (isWide ? 82 : 108),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isWide)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => context.go('/today'),
                        style: TextButton.styleFrom(
                          foregroundColor: RtwColors.subText,
                          padding: const EdgeInsets.only(bottom: 18),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('← Change my answer'),
                      ),
                    ),
                  const Eyebrow('Read the world'),
                  const SizedBox(height: 12),
                  _PredictionQuestionReference(
                    question: controller.today.prompt,
                    isWide: isWide,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'What share of people also said “${controller.selectedLabel}”?',
                    style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                      fontSize: isWide ? 30 : 25,
                      height: isWide ? 1.22 : 1.25,
                    ),
                  ),
                  SizedBox(height: isWide ? 72 : 72),
                  Center(
                    child: Text.rich(
                      TextSpan(
                        text: '${controller.prediction}',
                        children: const [
                          TextSpan(text: '%', style: TextStyle(fontSize: 38)),
                        ],
                      ),
                      style: Theme.of(context).textTheme.displayLarge!.copyWith(
                        color: RtwColors.blue,
                        fontSize: 92,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      controller.predictionPhrase,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.copyWith(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 40),
                  PredictionSlider(
                    value: controller.prediction,
                    onChanged: ref.read(rtwControllerProvider).setPrediction,
                  ),
                  SizedBox(height: isWide ? 48 : 92),
                  if (controller.lastError != null) ...[
                    Text(
                      controller.lastError!,
                      style: const TextStyle(color: RtwColors.danger),
                    ),
                    const SizedBox(height: 12),
                  ],
                  RtwButton(
                    label: controller.submitting
                        ? 'Locking...'
                        : 'Lock in my prediction',
                    onPressed:
                        controller.selectedOptionId == null ||
                            controller.submitting
                        ? null
                        : () {
                            unawaited(
                              ref.read(rtwControllerProvider).lockPrediction(),
                            );
                            if (context.mounted) {
                              context.go('/today/locked');
                            }
                          },
                  ),
                  if (!isWide) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go('/today'),
                      style: TextButton.styleFrom(
                        foregroundColor: RtwColors.subText,
                        padding: const EdgeInsets.all(8),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: const Text('← Change my answer'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PredictionQuestionReference extends StatelessWidget {
  const _PredictionQuestionReference({
    required this.question,
    required this.isWide,
  });

  final String question;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 18 : 16,
        vertical: isWide ? 14 : 13,
      ),
      decoration: BoxDecoration(
        color: RtwColors.card,
        border: Border.all(color: RtwColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('The question', fontSize: 10),
          const SizedBox(height: 7),
          Text(
            question,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: RtwColors.subText,
              fontSize: isWide ? 15 : 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class LockedScreen extends ConsumerWidget {
  const LockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(rtwControllerProvider);
    if (!controller.hasTodayQuestion || controller.selectedOptionId == null) {
      return _LiveDataEmptyState(
        location: '/today/locked',
        title: 'No locked answer yet.',
        body: 'Lock a prediction on the live question to see this state.',
        actionLabel: "Back to today's question",
        onAction: () => context.go('/today'),
      );
    }
    if (!controller.lockedToday) {
      return _LiveDataEmptyState(
        location: '/today/locked',
        title: 'Lock did not save.',
        body:
            controller.lastError ??
            'Your answer is still saved. Try locking it in again.',
        actionLabel: 'Try again',
        onAction: () => context.go('/today/predict'),
      );
    }
    final selectedLabel = controller.selectedLabel.isEmpty
        ? 'No'
        : controller.selectedLabel;
    final count = controller.liveCount.toString().replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"),
      (m) => "${m[1]},",
    );
    final countdown = controller.nextRevealCountdownText;
    final countdownSuffix = countdown == 'Ready'
        ? ' for the next question & reveal'
        : ' until the next question & reveal';
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return AppScaffold(
      location: '/today/locked',
      maxWidth: isWide ? 732 : 600,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isWide ? 0 : 24,
              isWide ? 78 : _screenTopPadding(context, 78),
              isWide ? 0 : 24,
              30,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - (isWide ? 108 : 108),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: RtwColors.blueTint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: RtwColors.blue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Locked in\nfor today.',
                    style: Theme.of(context).textTheme.headlineLarge!.copyWith(
                      fontSize: 32,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'See how the world answered tomorrow.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 30),
                  RtwCard(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.today.prompt,
                          style: Theme.of(context).textTheme.titleLarge!
                              .copyWith(
                                fontSize: 16,
                                color: const Color(0xFF5C584F),
                                height: 1.4,
                              ),
                        ),
                        const SectionRule(top: 16, bottom: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Eyebrow('Your answer'),
                                  const SizedBox(height: 3),
                                  Text(
                                    selectedLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge!
                                        .copyWith(
                                          color: RtwColors.blue,
                                          fontSize: 22,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Eyebrow('Your prediction'),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${controller.prediction}% say $selectedLabel',
                                    textAlign: TextAlign.right,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge!
                                        .copyWith(fontSize: 22),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: RtwColors.clay,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        '$count answered today',
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          fontSize: 13,
                          color: const Color(0xFF5C584F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      text: countdown,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: RtwColors.clay,
                        fontSize: 13,
                      ),
                      children: [
                        TextSpan(
                          text: countdownSuffix,
                          style: Theme.of(context).textTheme.bodyMedium!
                              .copyWith(color: const Color(0xFF5C584F)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isWide ? 26 : 92),
                  if (isWide)
                    Row(
                      children: [
                        RtwButton(
                          label: "See yesterday's result",
                          fullWidth: false,
                          compact: true,
                          onPressed: () => context.go('/reveal'),
                        ),
                        const SizedBox(width: 12),
                        RtwButton(
                          label: 'View history',
                          secondary: true,
                          fullWidth: false,
                          compact: true,
                          onPressed: () => context.go('/history'),
                        ),
                      ],
                    )
                  else ...[
                    RtwButton(
                      label: "See yesterday's result",
                      onPressed: () => context.go('/reveal'),
                    ),
                    const SizedBox(height: 10),
                    RtwButton(
                      label: 'View history',
                      secondary: true,
                      onPressed: () => context.go('/history'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class RevealScreen extends ConsumerStatefulWidget {
  const RevealScreen({super.key, this.questionId});

  final String? questionId;

  @override
  ConsumerState<RevealScreen> createState() => _RevealScreenState();
}

class _RevealScreenState extends ConsumerState<RevealScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  late final Animation<double> progress;

  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    progress = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    animation.forward();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(rtwControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    if (!controller.hasHistory) {
      return _LiveDataEmptyState(
        location: '/reveal',
        title: 'No revealed results yet.',
        body: 'Closed live questions will appear here after the daily reveal.',
        actionLabel: 'View history',
        onAction: () => context.go('/history'),
        showBottomNav: false,
      );
    }
    final entry = controller.revealEntryFor(widget.questionId);
    final hasGuess = entry.hasAnswer;
    final selected = hasGuess
        ? entry.selectedOptionId!
        : _majorityOptionId(entry.question);
    final selectedLabel = entry.question.option(selected).label;
    final world = entry.question.worldShareFor(selected);
    final guess = entry.prediction ?? 0;
    final score = hasGuess
        ? entry.readAccuracy ??
              calculateReadAccuracy(predictedShare: guess, actualShare: world)
        : null;
    final scoreGap = hasGuess ? (world - guess).abs() : null;
    final hasFriendRows =
        settings.friends && controller.friends.any((friend) => !friend.me);
    final friendComparisons =
        controller.friendAnswerComparisonQuestionId == entry.question.id
        ? controller.friendAnswerComparisons
        : const <FriendAnswerComparison>[];
    if (hasFriendRows &&
        controller.friendAnswerComparisonQuestionId != entry.question.id &&
        !controller.loadingFriendAnswerComparisons) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(rtwControllerProvider)
            .loadFriendAnswerComparisons(entry.question.id);
      });
    }
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return AppScaffold(
      location: '/reveal',
      showBottomNav: false,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          return ListView(
            padding: EdgeInsets.fromLTRB(
              24,
              isWide ? 70 : _screenTopPadding(context, 78),
              24,
              34,
            ),
            children: [
              Eyebrow('Yesterday · ${entry.question.category}'),
              const SizedBox(height: 13),
              Text(
                entry.question.prompt,
                style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                  fontSize: isWide ? 34 : 27,
                  height: 1.2,
                ),
              ),
              SizedBox(height: isWide ? 56 : 46),
              SpectrumBar(
                worldShare: world,
                guess: guess,
                progress: progress.value,
                showGuess: hasGuess,
              ),
              const SizedBox(height: 14),
              Text(
                '${compactCount(entry.question.totalAnswers)} answered',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: RtwColors.faint,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 30),
              if (hasGuess)
                Text.rich(
                  TextSpan(
                    text:
                        '${(world * progress.value).round()}% also said $selectedLabel.',
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: RtwColors.clay,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    children: [
                      TextSpan(
                        text: '\nYou guessed ',
                        style: Theme.of(context).textTheme.titleLarge!.copyWith(
                          fontSize: 22,
                          height: 1.35,
                        ),
                      ),
                      TextSpan(
                        text: '$guess%.',
                        style: Theme.of(context).textTheme.titleLarge!.copyWith(
                          color: RtwColors.blue,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text.rich(
                  TextSpan(
                    text:
                        '${(world * progress.value).round()}% of the world said $selectedLabel.',
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: RtwColors.clay,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    children: [
                      TextSpan(
                        text: "\nYou didn't answer this one.",
                        style: Theme.of(context).textTheme.titleLarge!.copyWith(
                          fontSize: 22,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              if (hasGuess && score != null && scoreGap != null) ...[
                const SizedBox(height: 24),
                RtwCard(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Eyebrow('Read Accuracy'),
                                const SizedBox(height: 6),
                                Text.rich(
                                  TextSpan(
                                    text: '${(score * progress.value).round()}',
                                    children: [
                                      TextSpan(
                                        text: ' / 100',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge!
                                            .copyWith(
                                              fontSize: 19,
                                              color: RtwColors.muted,
                                            ),
                                      ),
                                    ],
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge!
                                      .copyWith(fontSize: 44, height: 1),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Text(
                              _readVerdict(scoreGap),
                              style: Theme.of(context).textTheme.titleLarge!
                                  .copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: RtwColors.clay,
                                    fontSize: 18,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SectionRule(top: 18, bottom: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Eyebrow('Read Score'),
                                const SizedBox(height: 3),
                                Text.rich(
                                  TextSpan(
                                    text: formattedReadScore(
                                      controller.readScore +
                                          (((entry.readScoreDelta ?? 0) *
                                                  progress.value)
                                              .round()),
                                    ),
                                    children: [
                                      if (entry.readScoreDelta != null)
                                        TextSpan(
                                          text:
                                              ' ${entry.readScoreDelta! >= 0 ? '+' : ''}${entry.readScoreDelta}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall!
                                              .copyWith(
                                                color: RtwColors.clay,
                                                fontSize: 12,
                                              ),
                                        ),
                                    ],
                                  ),
                                  style: Theme.of(context).textTheme.titleLarge!
                                      .copyWith(fontSize: 24),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Eyebrow('Streak'),
                              const SizedBox(height: 3),
                              Text(
                                '${controller.currentStreak} ${controller.currentStreak == 1 ? 'day' : 'days'}',
                                style: Theme.of(
                                  context,
                                ).textTheme.titleLarge!.copyWith(fontSize: 24),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasFriendRows) ...[
                  const SizedBox(height: 24),
                  const Eyebrow('Among your friends'),
                  const SizedBox(height: 10),
                  if (controller.loadingFriendAnswerComparisons)
                    Text(
                      'Loading shared friend reads...',
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontSize: 12,
                        color: RtwColors.faint,
                      ),
                    )
                  else if (friendComparisons.isEmpty)
                    Text(
                      'No shared friend reads for this question yet.',
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontSize: 12,
                        color: RtwColors.faint,
                      ),
                    )
                  else
                    RtwCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var i = 0;
                            i < friendComparisons.length;
                            i++
                          ) ...[
                            _FriendAnswerComparisonRow(
                              comparison: friendComparisons[i],
                              question: entry.question,
                            ),
                            if (i != friendComparisons.length - 1)
                              const SectionRule(top: 0, bottom: 0),
                          ],
                        ],
                      ),
                    ),
                ],
              ],
              const SizedBox(height: 30),
              if (hasGuess && settings.resultSharing && score != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: RtwColors.muted,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () async {
                    final url = await ref
                        .read(rtwControllerProvider)
                        .createResultShareUrl(entry.question.id);
                    if (!context.mounted) return;
                    if (url.isEmpty) return;
                    await _showResultShareSheet(
                      context,
                      entry: entry,
                      score: score,
                      worldShare: world,
                      guess: guess,
                      url: url,
                    );
                  },
                  icon: const Icon(Icons.north_east, size: 16),
                  label: const Text('Share this result'),
                ),
              const SizedBox(height: 8),
              RtwButton(
                label: "Take today's challenge →",
                onPressed: () => context.go('/today'),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _majorityOptionId(RtwQuestion question) {
  if (question.options.isEmpty) return '';
  var majority = question.options.first;
  for (final option in question.options.skip(1)) {
    if (question.worldShareFor(option.id) >
        question.worldShareFor(majority.id)) {
      majority = option;
    }
  }
  return majority.id;
}

String _readVerdict(int gap) {
  if (gap <= 4) return 'Nailed it.';
  if (gap <= 9) return 'Sharp read.';
  if (gap <= 18) return 'A good read.';
  if (gap <= 30) return 'A little off.';
  return 'Way off.';
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  DateTime? viewMonth;

  DateTime _entryDate(HistoryEntry entry) => DateTime.parse(
    entry.question.dailyKey.length == 10
        ? entry.question.dailyKey
        : '${entry.question.dailyKey}-01',
  );

  DateTime _defaultViewMonth(List<HistoryEntry> entries) {
    if (entries.isNotEmpty) {
      final date = _entryDate(entries.first);
      return DateTime(date.year, date.month);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      final base =
          viewMonth ??
          _defaultViewMonth(ref.read(rtwControllerProvider).filteredHistory);
      viewMonth = DateTime(base.year, base.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(rtwControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    final categories = controller.categories;
    final activeMonth =
        viewMonth ?? _defaultViewMonth(controller.filteredHistory);
    final visibleEntries = controller.filteredHistory.where((entry) {
      final date = _entryDate(entry);
      return date.year == activeMonth.year && date.month == activeMonth.month;
    }).toList();
    return AppScaffold(
      location: '/history',
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          isWide ? 52 : _screenTopPadding(context, 78),
          24,
          30,
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Your history'),
                    const SizedBox(height: 10),
                    Text(
                      "Every call you've made.",
                      style: Theme.of(context).textTheme.headlineLarge!
                          .copyWith(fontSize: 30, height: 1.1),
                    ),
                  ],
                ),
              ),
              if (settings.partyMode)
                FilledButton.icon(
                  onPressed: () {
                    ref.read(rtwControllerProvider).resetParty();
                    context.go('/party');
                  },
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Party'),
                  style: FilledButton.styleFrom(
                    backgroundColor: RtwColors.ink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final category in categories) ...[
                  _HistoryFilterChip(
                    label: category == 'All'
                        ? 'All'
                        : '${category[0]}${category.substring(1).toLowerCase()}',
                    selected: controller.historyCategory == category,
                    onTap: () => ref
                        .read(rtwControllerProvider)
                        .setHistoryCategory(category),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _HistoryCalendar(
            viewMonth: activeMonth,
            entries: controller.filteredHistory,
            entryDate: _entryDate,
            onPrevious: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
            onSelectEntry: (entry) {
              ref.read(rtwControllerProvider).selectRevealEntry(entry);
              if (entry.hasAnswer) {
                context.go('/reveal/${entry.question.id}');
              } else {
                ref.read(rtwControllerProvider).revealSkipped(entry);
                context.go('/reveal/${entry.question.id}');
              }
            },
          ),
          const SizedBox(height: 22),
          if (visibleEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 10),
              child: Text(
                'No questions this month in this category.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: 14,
                  color: RtwColors.faint,
                ),
              ),
            ),
          for (final entry in visibleEntries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HistoryCard(
                entry: entry,
                onReview: () {
                  ref.read(rtwControllerProvider).selectRevealEntry(entry);
                  context.go('/reveal/${entry.question.id}');
                },
                onAnswer: () => context.go('/today'),
                onQuickReveal: () {
                  ref.read(rtwControllerProvider).revealSkipped(entry);
                  context.go('/reveal/${entry.question.id}');
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryFilterChip extends StatelessWidget {
  const _HistoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? RtwColors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? RtwColors.blue : RtwColors.borderStrong,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : RtwColors.subText,
          ),
        ),
      ),
    );
  }
}

class _HistoryCalendar extends StatelessWidget {
  const _HistoryCalendar({
    required this.viewMonth,
    required this.entries,
    required this.entryDate,
    required this.onPrevious,
    required this.onNext,
    required this.onSelectEntry,
  });

  final DateTime viewMonth;
  final List<HistoryEntry> entries;
  final DateTime Function(HistoryEntry entry) entryDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<HistoryEntry> onSelectEntry;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final byDay = <int, HistoryEntry>{};
    for (final entry in entries) {
      final date = entryDate(entry);
      if (date.year == viewMonth.year && date.month == viewMonth.month) {
        byDay[date.day] = entry;
      }
    }
    final firstDow = DateTime(viewMonth.year, viewMonth.month).weekday % 7;
    final daysInMonth = DateTime(viewMonth.year, viewMonth.month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 0; i < firstDow; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _HistoryDayCell(
          day: day,
          entry: byDay[day],
          onTap: byDay[day] == null ? null : () => onSelectEntry(byDay[day]!),
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: RtwColors.card,
        border: Border.all(color: RtwColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          children: [
            Row(
              children: [
                _CalendarArrow(icon: Icons.chevron_left, onTap: onPrevious),
                Expanded(
                  child: Text(
                    '${_months[viewMonth.month - 1]} ${viewMonth.year}',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge!.copyWith(fontSize: 19),
                  ),
                ),
                _CalendarArrow(icon: Icons.chevron_right, onTap: onNext),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final label in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          fontSize: 10,
                          color: const Color(0xFFBCB6A8),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 7,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1,
              children: cells,
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFEFEAE0)),
            const SizedBox(height: 13),
            Row(
              children: const [
                _HistoryLegendDot(answered: true),
                SizedBox(width: 7),
                _HistoryLegendLabel('Answered'),
                SizedBox(width: 18),
                _HistoryLegendDot(answered: false),
                SizedBox(width: 7),
                _HistoryLegendLabel('Missed'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarArrow extends StatelessWidget {
  const _CalendarArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFEFEAE0),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF5C584F)),
      ),
    );
  }
}

class _HistoryDayCell extends StatelessWidget {
  const _HistoryDayCell({required this.day, this.entry, this.onTap});

  final int day;
  final HistoryEntry? entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final has = entry != null;
    final answered = entry?.hasAnswer ?? false;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: has ? const Color(0x123E5BA0) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                fontSize: 13,
                fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                color: has ? RtwColors.ink : const Color(0xFFC3BDAF),
              ),
            ),
            const SizedBox(height: 3),
            _HistoryLegendDot(answered: answered, empty: !has),
          ],
        ),
      ),
    );
  }
}

class _HistoryLegendDot extends StatelessWidget {
  const _HistoryLegendDot({required this.answered, this.empty = false});

  final bool answered;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: empty || !answered ? Colors.transparent : RtwColors.blue,
        shape: BoxShape.circle,
        border: empty || answered
            ? null
            : Border.all(color: const Color(0xFFC4BDAD), width: 1.5),
      ),
    );
  }
}

class _HistoryLegendLabel extends StatelessWidget {
  const _HistoryLegendLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.bodySmall!.copyWith(fontSize: 12, color: RtwColors.subText),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.onReview,
    required this.onAnswer,
    required this.onQuickReveal,
  });

  final HistoryEntry entry;
  final VoidCallback onReview;
  final VoidCallback onAnswer;
  final VoidCallback onQuickReveal;

  @override
  Widget build(BuildContext context) {
    final skipped = entry.status == HistoryStatus.skipped;
    final revealed = entry.status == HistoryStatus.revealed;
    final selected = entry.selectedOptionId;
    final answerLabel = selected == null
        ? null
        : entry.question.option(selected).label;
    final world = selected == null
        ? entry.question.worldShareFor(entry.question.options.first.id)
        : entry.question.worldShareFor(selected);
    final totalShort = compactCount(entry.question.totalAnswers);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: skipped ? const Color(0xFFFCFAF4) : RtwColors.card,
        border: Border.all(
          color: skipped
              ? RtwColors.clay.withValues(alpha: 0.5)
              : RtwColors.border,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Eyebrow(
                    '${entry.question.dateLabel} · ${entry.question.category}',
                  ),
                ),
                if (entry.status == HistoryStatus.scored)
                  Text.rich(
                    TextSpan(
                      text: '${entry.readAccuracy ?? 0}',
                      children: const [
                        TextSpan(
                          text: '/100',
                          style: TextStyle(color: Color(0xFFBCB6A8)),
                        ),
                      ],
                    ),
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: RtwColors.clay,
                      fontSize: 11,
                    ),
                  )
                else if (revealed)
                  Text(
                    'NOT SCORED',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      fontSize: 9,
                      letterSpacing: 1,
                      color: RtwColors.faint,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              entry.question.prompt,
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontSize: 18,
                height: 1.28,
                color: const Color(0xFF2C2A24),
              ),
            ),
            if (entry.status == HistoryStatus.scored &&
                answerLabel != null) ...[
              const SizedBox(height: 13),
              Wrap(
                spacing: 9,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _HistoryAnswerPill('You said $answerLabel'),
                  Text(
                    'World $world% · you guessed ${entry.prediction}%',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      fontSize: 11,
                      color: RtwColors.subText,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _AnsweredLabel('$totalShort answered'),
              const SizedBox(height: 11),
              _HistoryTextAction(label: 'See the reveal →', onTap: onReview),
            ] else if (revealed) ...[
              const SizedBox(height: 13),
              Wrap(
                spacing: 9,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (answerLabel != null)
                    _HistoryAnswerPill('You said $answerLabel'),
                  Text(
                    answerLabel == null
                        ? 'World: ${entry.question.worldShareFor('yes')}% said Yes'
                        : 'World $world% · you guessed ${entry.prediction}%',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      fontSize: 11,
                      color: RtwColors.subText,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _AnsweredLabel('$totalShort answered'),
              const SizedBox(height: 11),
              Wrap(
                spacing: 18,
                children: [
                  _HistoryTextAction(
                    label: 'See the reveal →',
                    onTap: onReview,
                  ),
                  if (!entry.played)
                    _HistoryTextAction(
                      label: 'Answer it anyway',
                      muted: true,
                      onTap: onAnswer,
                    ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 11),
              Text(
                'You skipped this one.',
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontSize: 12,
                  color: RtwColors.faint,
                ),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: onAnswer,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: RtwColors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: const Text('Answer it →'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: onQuickReveal,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RtwColors.ink,
                      side: const BorderSide(
                        color: Color(0xFFDCD6C9),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: const Text('Quick reveal'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryAnswerPill extends StatelessWidget {
  const _HistoryAnswerPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: RtwColors.blueTint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          color: RtwColors.blue,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AnsweredLabel extends StatelessWidget {
  const _AnsweredLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
        fontSize: 10,
        letterSpacing: 0.5,
        color: const Color(0xFFBCB6A8),
      ),
    );
  }
}

class _HistoryTextAction extends StatelessWidget {
  const _HistoryTextAction({
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          color: muted ? RtwColors.muted : RtwColors.blue,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class PartyScreen extends ConsumerStatefulWidget {
  const PartyScreen({super.key});

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

enum _PartyRoundState { setup, play, done }

enum _PartyPlayPhase { question, answer, predict, result }

class _PartyScreenState extends ConsumerState<PartyScreen> {
  _PartyRoundState roundState = _PartyRoundState.setup;
  _PartyPlayPhase playPhase = _PartyPlayPhase.question;
  String category = 'All';
  bool unansweredOnly = false;
  bool answerMode = false;
  bool chronological = false;
  final selectedMonths = <String>{};

  DateTime _entryDate(HistoryEntry entry) =>
      DateTime.parse(entry.question.dailyKey);

  String _monthKey(HistoryEntry entry) {
    final date = _entryDate(entry);
    return '${date.year}-${date.month}';
  }

  String _monthLabel(String key) {
    final parts = key.split('-').map(int.parse).toList();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[parts[1] - 1]} ${parts[0]}';
  }

  List<HistoryEntry> _deck(RtwController controller) {
    var entries = controller.history.where((entry) {
      final matchesCategory =
          category == 'All' || entry.question.category == category;
      final matchesAnswered =
          !unansweredOnly || entry.status != HistoryStatus.scored;
      final matchesMonth =
          selectedMonths.isEmpty || selectedMonths.contains(_monthKey(entry));
      return matchesCategory && matchesAnswered && matchesMonth;
    }).toList();
    if (chronological) {
      entries = entries.reversed.toList();
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(rtwControllerProvider);
    final deck = _deck(controller);
    if (!controller.hasHistory) {
      return _LiveDataEmptyState(
        location: '/party',
        title: 'No questions to play yet.',
        body: 'Party mode uses closed live questions from history.',
        actionLabel: 'View history',
        onAction: () => context.go('/history'),
        showBottomNav: false,
      );
    }
    final partyIndex = deck.isEmpty
        ? 0
        : controller.partyIndex.clamp(0, deck.length - 1).toInt();
    final card = deck.isEmpty ? controller.history.first : deck[partyIndex];
    final selected =
        controller.partyAnswer ??
        card.selectedOptionId ??
        card.question.options.first.id;
    final world = card.question.worldShareFor(selected);
    final score = calculateReadAccuracy(
      predictedShare: controller.partyPrediction,
      actualShare: world,
    );
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    final topPadding = roundState == _PartyRoundState.play ? 54.0 : 60.0;
    const bottomPadding = 34.0;
    final playHeight =
        (MediaQuery.sizeOf(context).height - topPadding - bottomPadding)
            .clamp(0.0, double.infinity)
            .toDouble();
    return AppScaffold(
      location: '/party',
      showBottomNav: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          isWide ? topPadding : _screenTopPadding(context, topPadding),
          24,
          bottomPadding,
        ),
        children: switch (roundState) {
          _PartyRoundState.setup => _buildSetup(context, ref, controller, deck),
          _PartyRoundState.play => [
            SizedBox(
              height: playHeight,
              child: _buildPlay(
                context,
                ref,
                controller,
                deck,
                card,
                world,
                score,
              ),
            ),
          ],
          _PartyRoundState.done => _buildDone(context, ref, deck.length),
        },
      ),
    );
  }

  List<Widget> _buildSetup(
    BuildContext context,
    WidgetRef ref,
    RtwController controller,
    List<HistoryEntry> deck,
  ) {
    final categories = controller.categories;
    final monthKeys = <String>[];
    for (final entry in controller.history) {
      final key = _monthKey(entry);
      if (!monthKeys.contains(key)) monthKeys.add(key);
    }
    final catTitle = category == 'All'
        ? ''
        : '${category[0]}${category.substring(1).toLowerCase()}';
    final summary =
        '${deck.length}${category == 'All' ? (unansweredOnly ? ' unanswered' : ' questions') : ' $catTitle${unansweredOnly ? ' unanswered' : ''} questions'}${selectedMonths.isEmpty ? '' : ' · ${selectedMonths.length} ${selectedMonths.length == 1 ? 'month' : 'months'}'} · ${chronological ? 'oldest first' : 'shuffled'}';

    return [
      Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => context.go('/history'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '\u2190 History',
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                color: RtwColors.subText,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Eyebrow('Party mode', color: RtwColors.clay),
      const SizedBox(height: 10),
      Text(
        'Read the room.',
        style: Theme.of(
          context,
        ).textTheme.headlineLarge!.copyWith(fontSize: 36, height: 1.06),
      ),
      const SizedBox(height: 12),
      Text(
        'Run through past questions and reveal how the world really answered. No scores — play it solo or with friends.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium!.copyWith(fontSize: 14, height: 1.55),
      ),
      const SizedBox(height: 28),
      const Eyebrow('Topic'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in categories)
            _PartySetupChip(
              label: value == 'All'
                  ? 'All topics'
                  : '${value[0]}${value.substring(1).toLowerCase()}',
              selected: category == value,
              onTap: () => setState(() => category = value),
            ),
        ],
      ),
      const SizedBox(height: 24),
      const Eyebrow('When'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _PartySetupChip(
            label: 'All months',
            selected: selectedMonths.isEmpty,
            compact: true,
            onTap: () => setState(selectedMonths.clear),
          ),
          for (final key in monthKeys)
            _PartySetupChip(
              label: _monthLabel(key),
              selected: selectedMonths.contains(key),
              compact: true,
              onTap: () => setState(() {
                if (selectedMonths.contains(key)) {
                  selectedMonths.remove(key);
                } else {
                  selectedMonths.add(key);
                }
              }),
            ),
        ],
      ),
      const SizedBox(height: 24),
      const Eyebrow('Questions'),
      const SizedBox(height: 12),
      _PartySegmentGroup(
        children: [
          _SegmentChoice(
            label: 'All questions',
            selected: !unansweredOnly,
            onTap: () => setState(() => unansweredOnly = false),
          ),
          _SegmentChoice(
            label: 'Unanswered only',
            selected: unansweredOnly,
            onTap: () => setState(() => unansweredOnly = true),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Eyebrow('How you play'),
      const SizedBox(height: 12),
      _PartySegmentGroup(
        children: [
          _SegmentChoice(
            label: 'Just reveal',
            selected: !answerMode,
            onTap: () => setState(() => answerMode = false),
          ),
          _SegmentChoice(
            label: 'Answer & predict',
            selected: answerMode,
            onTap: () => setState(() => answerMode = true),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Eyebrow('Order'),
      const SizedBox(height: 12),
      _PartySegmentGroup(
        children: [
          _SegmentChoice(
            label: 'Shuffled',
            selected: !chronological,
            onTap: () => setState(() => chronological = false),
          ),
          _SegmentChoice(
            label: 'Chronological',
            selected: chronological,
            onTap: () => setState(() => chronological = true),
          ),
        ],
      ),
      const SizedBox(height: 30),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: RtwColors.blue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              summary,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                fontSize: 11,
                letterSpacing: 0.6,
                color: RtwColors.subText,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (deck.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFEFEAE0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Nothing to play here - try another topic',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: RtwColors.faint,
              fontWeight: FontWeight.w600,
            ),
          ),
        )
      else
        RtwButton(
          label: 'Start the round →',
          onPressed: () {
            ref.read(rtwControllerProvider).resetParty();
            ref.read(rtwControllerProvider).setPartyMode(answerMode);
            setState(() {
              roundState = _PartyRoundState.play;
              playPhase = answerMode
                  ? _PartyPlayPhase.answer
                  : _PartyPlayPhase.question;
            });
          },
        ),
    ];
  }

  Widget _buildPlay(
    BuildContext context,
    WidgetRef ref,
    RtwController controller,
    List<HistoryEntry> deck,
    HistoryEntry card,
    int world,
    int score,
  ) {
    final yesWorld = card.question.worldShareFor('yes');
    final noWorld = card.question.worldShareFor('no');
    final majorityWord = yesWorld >= noWorld ? 'said Yes' : 'said No';
    final majorityPct = yesWorld >= noWorld ? yesWorld : noWorld;
    final answeredBefore = card.hasAnswer;
    final selectedLabel = controller.partyAnswer == null
        ? ''
        : card.question.option(controller.partyAnswer!).label;
    final content = <Widget>[
      Eyebrow(card.question.category, color: RtwColors.clay),
      const SizedBox(height: 14),
      Text(
        card.question.prompt,
        style: Theme.of(
          context,
        ).textTheme.headlineMedium!.copyWith(fontSize: 31, height: 1.18),
      ),
      if (controller.partyAnswerMode &&
          playPhase == _PartyPlayPhase.answer) ...[
        const SizedBox(height: 14),
        _PartyHintLine(
          filled: !answeredBefore,
          text: answeredBefore
              ? 'You answered ${card.question.option(card.selectedOptionId!).label} on ${card.question.dateLabel} · just for fun now'
              : 'This replay can save a practice answer, but it will not change official results or Read Score.',
        ),
        const SizedBox(height: 18),
        for (final option in card.question.options)
          AnswerTile(
            option: option,
            selected: controller.partyAnswer == option.id,
            onTap: () {
              ref.read(rtwControllerProvider).answerParty(option.id);
              setState(() => playPhase = _PartyPlayPhase.predict);
            },
          ),
      ],
      if (controller.partyAnswerMode &&
          playPhase == _PartyPlayPhase.predict) ...[
        const SizedBox(height: 26),
        Text(
          'What share also answered “$selectedLabel”?',
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: 14,
            color: RtwColors.subText,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text.rich(
            TextSpan(
              text: '${controller.partyPrediction}',
              children: const [
                TextSpan(text: '%', style: TextStyle(fontSize: 32)),
              ],
            ),
            style: Theme.of(context).textTheme.displayLarge!.copyWith(
              color: RtwColors.blue,
              fontSize: 74,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 14),
        PredictionSlider(
          value: controller.partyPrediction,
          onChanged: ref.read(rtwControllerProvider).setPartyPrediction,
          showLabels: false,
        ),
      ],
      if (playPhase == _PartyPlayPhase.result) ...[
        const SizedBox(height: 30),
        _PartyWorldBar(yesShare: yesWorld),
        const SizedBox(height: 14),
        controller.partyAnswerMode
            ? Text(
                'You guessed ${controller.partyPrediction}% · it was $world%',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: RtwColors.muted,
                  letterSpacing: 1.2,
                ),
              )
            : Text.rich(
                TextSpan(
                  text: 'The world ',
                  children: [
                    TextSpan(
                      text: majorityWord,
                      style: const TextStyle(
                        color: RtwColors.clay,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' — $majorityPct% of ${compactCount(card.question.totalAnswers)} people.',
                    ),
                  ],
                ),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge!.copyWith(fontSize: 20, height: 1.4),
              ),
        if (controller.partyAnswerMode)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text.rich(
              TextSpan(
                text: 'Read score: ',
                children: [
                  TextSpan(
                    text: '$score/100',
                    style: const TextStyle(
                      color: RtwColors.clay,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(
                    text: ' — closeness to the crowd, not being right.',
                  ),
                ],
              ),
              style: Theme.of(
                context,
              ).textTheme.titleLarge!.copyWith(fontSize: 20, height: 1.4),
            ),
          ),
      ],
    ];
    return Column(
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                roundState = _PartyRoundState.setup;
                playPhase = _PartyPlayPhase.question;
              }),
              icon: const Icon(Icons.close, size: 15),
              label: const Text('Exit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5C584F),
                backgroundColor: RtwColors.card,
                side: const BorderSide(color: Color(0xFFDCD6C9)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const Spacer(),
            Eyebrow('${controller.partyIndex + 1} / ${deck.length}'),
          ],
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: _buildPartyFooter(ref, controller, deck.length, card),
        ),
      ],
    );
  }

  Widget _buildPartyFooter(
    WidgetRef ref,
    RtwController controller,
    int deckLength,
    HistoryEntry card,
  ) {
    switch (playPhase) {
      case _PartyPlayPhase.question:
        return RtwButton(
          label: 'Reveal the world ↓',
          onPressed: () {
            ref.read(rtwControllerProvider).revealPartyCard();
            setState(() => playPhase = _PartyPlayPhase.result);
          },
        );
      case _PartyPlayPhase.answer:
        return const SizedBox.shrink();
      case _PartyPlayPhase.predict:
        return RtwButton(
          label: 'Lock it in ↓',
          onPressed: () async {
            final answer = controller.partyAnswer;
            if (answer != null && !card.countedTowardScore) {
              await ref
                  .read(rtwControllerProvider)
                  .savePracticeAnswer(
                    card,
                    answer,
                    controller.partyPrediction,
                    source: 'party-replay',
                  );
            }
            if (!mounted) return;
            ref.read(rtwControllerProvider).revealPartyCard();
            setState(() => playPhase = _PartyPlayPhase.result);
          },
        );
      case _PartyPlayPhase.result:
        return _PartyResultButton(
          label: controller.partyIndex == deckLength - 1
              ? 'Finish round'
              : 'Next question →',
          onPressed: () {
            if (controller.partyIndex == deckLength - 1) {
              ref.read(rtwControllerProvider).resetParty();
              setState(() {
                roundState = _PartyRoundState.done;
                playPhase = _PartyPlayPhase.question;
              });
            } else {
              ref
                  .read(rtwControllerProvider)
                  .nextPartyCard(deckLength: deckLength);
              setState(() {
                playPhase = controller.partyAnswerMode
                    ? _PartyPlayPhase.answer
                    : _PartyPlayPhase.question;
              });
            }
          },
        );
    }
  }

  List<Widget> _buildDone(BuildContext context, WidgetRef ref, int deckLength) {
    return [
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
      const Center(child: Eyebrow('Round complete', color: RtwColors.clay)),
      const SizedBox(height: 14),
      Text(
        "That's the room read.",
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.headlineLarge!.copyWith(fontSize: 34, height: 1.1),
      ),
      const SizedBox(height: 12),
      Text(
        'You ran through $deckLength ${deckLength == 1 ? 'question' : 'questions'}. Go again or head back.',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium!.copyWith(fontSize: 15, height: 1.55),
      ),
      const SizedBox(height: 30),
      RtwButton(
        label: 'New round',
        onPressed: () => setState(() {
          roundState = _PartyRoundState.setup;
          playPhase = _PartyPlayPhase.question;
        }),
      ),
      const SizedBox(height: 10),
      RtwButton(
        label: 'Back to history',
        secondary: true,
        onPressed: () => context.go('/history'),
      ),
    ];
  }
}

class _PartyResultButton extends StatelessWidget {
  const _PartyResultButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(double.infinity, 58),
        padding: const EdgeInsets.all(18),
        backgroundColor: RtwColors.ink,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

class _PartyHintLine extends StatelessWidget {
  const _PartyHintLine({required this.text, required this.filled});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 7),
          decoration: BoxDecoration(
            color: filled ? Colors.transparent : RtwColors.blue,
            border: filled
                ? Border.all(color: RtwColors.blue, width: 1.5)
                : null,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontSize: 13,
              height: 1.45,
              color: filled ? RtwColors.blue : RtwColors.muted,
            ),
          ),
        ),
      ],
    );
  }
}

class _PartyWorldBar extends StatelessWidget {
  const _PartyWorldBar({required this.yesShare});

  final int yesShare;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 54,
        child: Stack(
          children: [
            Container(color: const Color(0xFFE6E0D3)),
            FractionallySizedBox(
              widthFactor: yesShare.clamp(0, 100) / 100,
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              child: Container(color: RtwColors.blue),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Text(
                      'YES $yesShare%',
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: RtwColors.paper,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'NO',
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: const Color(0xFF7A7466),
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartySetupChip extends StatelessWidget {
  const _PartySetupChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(compact ? 20 : 22),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 16,
          vertical: compact ? 8 : 9,
        ),
        decoration: BoxDecoration(
          color: selected ? RtwColors.blueTint : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 20 : 22),
          border: Border.all(
            color: selected ? RtwColors.blue : RtwColors.borderStrong,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: selected ? RtwColors.blue : RtwColors.subText,
            fontSize: compact ? 13 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PartySegmentGroup extends StatelessWidget {
  const _PartySegmentGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEAE0),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [for (final child in children) Expanded(child: child)],
      ),
    );
  }
}

class _SegmentChoice extends StatelessWidget {
  const _SegmentChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected ? RtwColors.ink : Colors.transparent,
        foregroundColor: selected ? Colors.white : RtwColors.subText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  bool accepting = false;

  Future<void> _acceptInvite() async {
    if (accepting) return;
    setState(() => accepting = true);
    final ok = await ref.read(rtwControllerProvider).acceptInvite(widget.code);
    if (!mounted) return;
    setState(() => accepting = false);
    if (ok) context.go('/insights');
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(rtwControllerProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return AppScaffold(
      location: '/invite',
      maxWidth: 520,
      showBottomNav: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          isWide ? 80 : _screenTopPadding(context, 72),
          24,
          34,
        ),
        children: [
          const RtwLogo(),
          const SizedBox(height: 48),
          const Eyebrow('Friend invite', color: RtwColors.clay),
          const SizedBox(height: 10),
          Text(
            'Read the world together.',
            style: Theme.of(
              context,
            ).textTheme.headlineLarge!.copyWith(fontSize: 36, height: 1.08),
          ),
          const SizedBox(height: 14),
          Text(
            'Join this leaderboard to compare Read Scores and decide whether to share daily answers with each other.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(fontSize: 15, height: 1.55),
          ),
          const SizedBox(height: 28),
          RtwCard(
            dark: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.code.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: const Color(0xFFB7B1A4),
                    fontSize: 11,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your scores stay private unless you choose to share answers.',
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: RtwColors.paper,
                    fontSize: 22,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
          if (controller.lastError != null) ...[
            const SizedBox(height: 14),
            Text(
              controller.lastError!,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: RtwColors.clay,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 24),
          RtwButton(
            label: accepting ? 'Joining...' : 'Accept invite',
            icon: Icons.arrow_forward,
            onPressed: accepting ? null : _acceptInvite,
          ),
          const SizedBox(height: 10),
          RtwButton(
            label: 'Not now',
            secondary: true,
            onPressed: () => context.go('/today'),
          ),
        ],
      ),
    );
  }
}

class ShortLinkScreen extends ConsumerStatefulWidget {
  const ShortLinkScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<ShortLinkScreen> createState() => _ShortLinkScreenState();
}

class _ShortLinkScreenState extends ConsumerState<ShortLinkScreen> {
  bool failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final route = await ref
        .read(rtwControllerProvider)
        .resolveShortCodeRoute(widget.code);
    if (!mounted) return;
    if (route == null) {
      setState(() => failed = true);
      return;
    }
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(rtwControllerProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return AppScaffold(
      location: '/invite',
      maxWidth: 520,
      showBottomNav: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          isWide ? 80 : _screenTopPadding(context, 72),
          24,
          34,
        ),
        children: [
          const RtwLogo(),
          const SizedBox(height: 48),
          const Eyebrow('Shared link', color: RtwColors.clay),
          const SizedBox(height: 10),
          Text(
            failed ? 'This link is unavailable.' : 'Opening Read the World.',
            style: Theme.of(
              context,
            ).textTheme.headlineLarge!.copyWith(fontSize: 36, height: 1.08),
          ),
          const SizedBox(height: 14),
          Text(
            failed
                ? (controller.lastError ??
                      'The link may have expired or been removed.')
                : 'Taking you to the right place.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(fontSize: 15, height: 1.55),
          ),
          const SizedBox(height: 28),
          RtwCard(
            dark: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.code.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: const Color(0xFFB7B1A4),
                    fontSize: 11,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  failed
                      ? 'You can still answer today\'s question.'
                      : 'One daily read, one shared world.',
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: RtwColors.paper,
                    fontSize: 22,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (failed)
            RtwButton(
              label: 'Continue to today',
              icon: Icons.arrow_forward,
              onPressed: () => context.go('/today'),
            )
          else
            const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
        ],
      ),
    );
  }
}

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(rtwControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return AppScaffold(
      location: '/insights',
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          isWide ? 52 : _screenTopPadding(context, 60),
          24,
          30,
        ),
        children: [
          if (!isWide) ...[
            Row(
              children: [
                const Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(fit: BoxFit.scaleDown, child: RtwLogo()),
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => context.go('/account'),
                  child: CircleAvatar(
                    radius: 21,
                    backgroundColor: RtwColors.blue,
                    child: Text(
                      controller.displayName.isEmpty
                          ? 'R'
                          : controller.displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
          ],
          const Eyebrow('Your Read Score'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      controller.readScoreText,
                      style: Theme.of(context).textTheme.displayLarge!.copyWith(
                        fontSize: 62,
                        height: 0.9,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    controller.readScorePercentileLabel,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: RtwColors.blue,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            controller.answeredCountText,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 26),
          const Eyebrow('You read these best'),
          const SizedBox(height: 12),
          for (final insight in controller.categoryInsights.where(
            (item) => item.best,
          ))
            _InsightBar(insight: insight),
          const SizedBox(height: 18),
          const Eyebrow('You misjudge these'),
          const SizedBox(height: 12),
          for (final insight in controller.categoryInsights.where(
            (item) => !item.best,
          ))
            _InsightBar(insight: insight),
          if (settings.friends) ...[
            const SizedBox(height: 26),
            const Eyebrow('Friends'),
            const SizedBox(height: 12),
            if (settings.friendsLeaderboard) ...[
              RtwCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < controller.friends.length; i++) ...[
                      _FriendScoreRow(
                        rank: i + 1,
                        friend: controller.friends[i],
                        onToggle: () => ref
                            .read(rtwControllerProvider)
                            .toggleFriendAnswerVisibility(
                              controller.friends[i],
                            ),
                        onRemove: () => ref
                            .read(rtwControllerProvider)
                            .removeFriend(controller.friends[i]),
                      ),
                      if (i != controller.friends.length - 1)
                        const Divider(height: 1, color: RtwColors.border),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            _DashedInviteButton(
              onPressed: () async {
                final url = await ref
                    .read(rtwControllerProvider)
                    .createInviteUrl();
                if (!context.mounted) return;
                if (url.isEmpty) return;
                await _showInviteSheet(context, url);
              },
            ),
            if (settings.friendsLeaderboard) ...[
              const SizedBox(height: 10),
              Text(
                'Friends compare Read Scores. Tap a name to set answer visibility, or swipe to remove.',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: 12,
                  color: RtwColors.faint,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DashedInviteButton extends StatelessWidget {
  const _DashedInviteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(color: const Color(0xFFD8D2C5), radius: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: SizedBox(
            height: 50,
            child: Center(
              child: Text(
                'Invite a friend →',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: const Color(0xFF5C584F),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect.deflate(0.75), Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

class _InsightBar extends StatelessWidget {
  const _InsightBar({required this.insight});

  final CategoryInsight insight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                insight.name,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: RtwColors.ink,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                '${insight.score}',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: RtwColors.subText,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: insight.score / 100,
              minHeight: 6,
              color: insight.best ? RtwColors.blue : RtwColors.clay,
              backgroundColor: const Color(0xFFE6E0D3),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendScoreRow extends StatelessWidget {
  const _FriendScoreRow({
    required this.rank,
    required this.friend,
    required this.onToggle,
    required this.onRemove,
  });

  final int rank;
  final FriendRow friend;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      onTap: friend.me ? null : onToggle,
      child: ColoredBox(
        color: friend.me ? const Color(0xFFE8EEF2) : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '$rank',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    fontSize: 13,
                    color: RtwColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  friend.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: friend.me ? FontWeight.w800 : FontWeight.w600,
                    color: RtwColors.ink,
                  ),
                ),
              ),
              if (!friend.me)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: friend.answersShared
                        ? RtwColors.blueTint
                        : Colors.transparent,
                    border: Border.all(
                      color: friend.answersShared
                          ? const Color(0x663E5BA0)
                          : RtwColors.borderStrong,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    friend.answersShared ? 'Answers shared' : 'Scores only',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: friend.answersShared
                          ? RtwColors.blue
                          : RtwColors.muted,
                      fontSize: 9,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              Text(
                formattedReadScore(friend.score),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge!.copyWith(fontSize: 17),
              ),
            ],
          ),
        ),
      ),
    );

    if (friend.me) return row;
    return Dismissible(
      key: ValueKey('friend-${friend.uid}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        color: RtwColors.danger,
        child: const Text(
          'Remove',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      child: row,
    );
  }
}

class _FriendAnswerComparisonRow extends StatelessWidget {
  const _FriendAnswerComparisonRow({
    required this.comparison,
    required this.question,
  });

  final FriendAnswerComparison comparison;
  final RtwQuestion question;

  @override
  Widget build(BuildContext context) {
    final option = question.option(comparison.selectedOptionId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comparison.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: RtwColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${option.label} · guessed ${comparison.predictedShare}%',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: 12,
                    color: RtwColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (comparison.readAccuracy != null)
            Text(
              '${comparison.readAccuracy}/100',
              style: Theme.of(
                context,
              ).textTheme.titleLarge!.copyWith(fontSize: 17),
            ),
        ],
      ),
    );
  }
}

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(rtwControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    final colors = [
      RtwColors.blue,
      RtwColors.clay,
      RtwColors.green,
      RtwColors.ink2,
    ];
    return AppScaffold(
      location: '/account',
      maxWidth: 520,
      showBottomNav: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          _screenTopPadding(context, 60),
          24,
          40,
        ),
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => context.go('/insights'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '\u2190 Back',
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                      color: RtwColors.subText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              const Eyebrow('Profile'),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                InkWell(
                  onTap: ref.read(rtwControllerProvider).cycleAvatar,
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                    radius: 45,
                    backgroundColor: colors[controller.avatarIndex],
                    child: Text(
                      (controller.displayName.isEmpty
                              ? '?'
                              : controller.displayName[0])
                          .toUpperCase(),
                      style: Theme.of(context).textTheme.headlineLarge!
                          .copyWith(color: Colors.white, fontSize: 34),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: ref.read(rtwControllerProvider).cycleAvatar,
                  style: TextButton.styleFrom(
                    foregroundColor: RtwColors.blue,
                    textStyle: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Change colour'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Eyebrow('Display name'),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: controller.displayName,
            onChanged: ref.read(rtwControllerProvider).setDisplayName,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              filled: true,
              fillColor: RtwColors.card,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RtwRadii.input),
                borderSide: const BorderSide(color: RtwColors.borderStrong),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RtwRadii.input),
                borderSide: const BorderSide(color: RtwColors.borderStrong),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(RtwRadii.input),
                borderSide: const BorderSide(color: RtwColors.blue, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _AccountPanel(
            children: [
              _AccountToggleRow(
                title: 'Daily reminder',
                subtitle: 'Ping me when a new question drops',
                value: controller.dailyReminder,
                onTap: () => ref.read(rtwControllerProvider).toggleReminder(),
              ),
              _AccountActionRow(
                title: 'Email',
                value: controller.email,
                showDivider: true,
              ),
              _AccountActionRow(
                title: 'Change password',
                showDivider: false,
                onTap: () async {
                  await ref
                      .read(rtwControllerProvider)
                      .sendPasswordReset(controller.email);
                  if (!context.mounted) return;
                  final message =
                      ref.read(rtwControllerProvider).lastError ??
                      'Password reset email sent.';
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
                },
              ),
            ],
          ),
          if (settings.onboardingDemographics) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Eyebrow('About you'),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/onboarding/about'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: RtwColors.blue,
                    textStyle: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _AccountPanel(
              children: [
                _AccountInfoRow(
                  title: 'Date of birth',
                  value: controller.birthdateDisplay,
                ),
                _AccountInfoRow(
                  title: 'Gender',
                  value: controller.genderDisplay,
                ),
                _AccountInfoRow(
                  title: 'Country',
                  value: controller.countryDisplay,
                  showDivider: false,
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          _AccountPanel(
            children: [
              _AccountActionRow(
                title: 'Restart onboarding',
                onTap: () => context.go('/onboarding'),
              ),
              _AccountActionRow(
                title: 'Log out',
                onTap: () async {
                  await ref.read(rtwControllerProvider).signOut();
                  if (context.mounted) context.go('/auth');
                },
              ),
              _AccountActionRow(
                title: 'Clear all data',
                danger: true,
                showDivider: false,
                onTap: ref.read(rtwControllerProvider).clearAllData,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Clearing data erases your scores, streak, saved answers, friends, and notification tokens.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: const Color(0xFFBCB6A8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RtwColors.card,
        border: Border.all(color: RtwColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }
}

class _AccountToggleRow extends StatelessWidget {
  const _AccountToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFEFEAE0))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(color: RtwColors.faint),
                  ),
                ],
              ),
            ),
            _AccountSwitch(value: value),
          ],
        ),
      ),
    );
  }
}

class _AccountSwitch extends StatelessWidget {
  const _AccountSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 46,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? RtwColors.blue : RtwColors.borderStrong,
        borderRadius: BorderRadius.circular(20),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _AccountActionRow extends StatelessWidget {
  const _AccountActionRow({
    required this.title,
    this.value,
    this.onTap,
    this.danger = false,
    this.showDivider = true,
  });

  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final textColor = danger ? RtwColors.danger : RtwColors.ink;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: Color(0xFFEFEAE0)))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge!.copyWith(color: textColor),
              ),
            ),
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: RtwColors.faint),
                ),
              ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: danger ? RtwColors.danger : RtwColors.faint,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountInfoRow extends StatelessWidget {
  const _AccountInfoRow({
    required this.title,
    required this.value,
    this.showDivider = true,
  });

  final String title;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: Color(0xFFEFEAE0)))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge!.copyWith(color: RtwColors.subText),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                color: RtwColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
