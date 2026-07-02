import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart';
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

