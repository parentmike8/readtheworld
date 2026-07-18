import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart';
import 'theme/tokens.dart';
import 'v2/deferred_invite.dart';
import 'widgets.dart';

final Uri _marketingSiteUri = Uri.parse('https://readtheworld.today');
final Uri _termsUri = Uri.parse('https://readtheworld.today/terms');
final Uri _privacyUri = Uri.parse('https://readtheworld.today/privacy');

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

Future<void> _openExternalUri(Uri uri) async {
  await launchUrl(
    uri,
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool creating = false;
  bool phoneMode = false;
  bool obscure = true;
  bool authBusy = false;
  bool handoffFailed = false;
  bool deferredInviteAvailable = false;
  bool deferredInviteBusy = false;
  bool deferredInviteInvalid = false;
  String? deferredInviteCode;
  String? handoffCode;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController();
  final phoneCodeController = TextEditingController();

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
    final phone = Uri.base.queryParameters['phone'];
    if (phone != null && phone.isNotEmpty) {
      phoneMode = true;
      phoneController.text = phone;
    }
    final nextHandoffCode = Uri.base.queryParameters['handoff']?.trim();
    if (nextHandoffCode != null && nextHandoffCode.isNotEmpty) {
      handoffCode = nextHandoffCode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _redeemHandoff();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkDeferredInvite());
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    phoneCodeController.dispose();
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

  Future<void> _sendPhoneCode() async {
    if (authBusy) return;
    setState(() => authBusy = true);
    final ok = await ref
        .read(rtwControllerProvider)
        .startPhoneSignIn(phoneController.text);
    final route = ok
        ? await ref.read(rtwControllerProvider).postAuthRoute()
        : null;
    if (!mounted) return;
    setState(() => authBusy = false);
    if (route != null) context.go(route);
  }

  Future<void> _verifyPhoneCode() async {
    await _runAuth(
      () => ref
          .read(rtwControllerProvider)
          .verifyPhoneCode(phoneCodeController.text),
    );
  }

  Future<void> _redeemHandoff() async {
    final code = handoffCode;
    if (code == null || authBusy) return;
    setState(() {
      authBusy = true;
      handoffFailed = false;
    });
    final route = await ref
        .read(rtwControllerProvider)
        .redeemAuthHandoff(
          code,
          fallbackRoute: Uri.base.queryParameters['next'],
        );
    if (!mounted) return;
    setState(() {
      authBusy = false;
      handoffFailed = route == null;
    });
    if (route != null) context.go(route);
  }

  Future<void> _checkDeferredInvite() async {
    final check = await checkDeferredInvite();
    if (!mounted || !check.available) return;
    final code = check.code;
    if (code != null) {
      ref.read(rtwControllerProvider).stashPendingInviteCode(code);
    }
    setState(() {
      deferredInviteAvailable = true;
      deferredInviteCode = code;
    });
  }

  Future<void> _pasteDeferredInvite() async {
    if (deferredInviteBusy) return;
    setState(() {
      deferredInviteBusy = true;
      deferredInviteInvalid = false;
    });
    final code = await readDeferredInvite();
    if (!mounted) return;
    if (code == null) {
      setState(() {
        deferredInviteBusy = false;
        deferredInviteInvalid = true;
      });
      return;
    }
    ref.read(rtwControllerProvider).stashPendingInviteCode(code);
    setState(() {
      deferredInviteBusy = false;
      deferredInviteCode = code;
    });
  }

  void _showSignIn() {
    setState(() {
      handoffCode = null;
      handoffFailed = false;
      authBusy = false;
    });
    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(rtwControllerProvider);
    if (handoffCode != null) {
      return _AuthHandoffScreen(
        busy: authBusy || !handoffFailed,
        onRetry: _redeemHandoff,
        onSignIn: _showSignIn,
      );
    }
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final isWide = width >= 820;
    final useWebPhoneSurface = kIsWeb && !isWide;
    final mobileWidth = rtwMobileSurfaceWidth(size);

    Widget authForm({bool mobile = false}) {
      return _AuthForm(
        creating: creating,
        phoneMode: phoneMode,
        obscure: obscure,
        busy: authBusy,
        errorText: controller.lastError,
        emailController: emailController,
        passwordController: passwordController,
        phoneController: phoneController,
        phoneCodeController: phoneCodeController,
        phoneCodeSent: controller.phoneCodeSent,
        mobile: mobile,
        onSelectEmail: () {
          ref.read(rtwControllerProvider).resetPhoneSignIn();
          setState(() => phoneMode = false);
        },
        onSelectPhone: () => setState(() => phoneMode = true),
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
        onSendPhoneCode: _sendPhoneCode,
        onVerifyPhoneCode: _verifyPhoneCode,
        onEditPhone: () {
          ref.read(rtwControllerProvider).resetPhoneSignIn();
          phoneCodeController.clear();
        },
        onGoogle: () =>
            _runAuth(ref.read(rtwControllerProvider).authenticateWithGoogle),
        onApple: () =>
            _runAuth(ref.read(rtwControllerProvider).authenticateWithApple),
        onForgotPassword: () => ref
            .read(rtwControllerProvider)
            .sendPasswordReset(emailController.text),
        invitePrompt: deferredInviteAvailable
            ? _DeferredInvitePrompt(
                saved: deferredInviteCode != null,
                busy: deferredInviteBusy,
                invalid: deferredInviteInvalid,
                onPaste: () => unawaited(_pasteDeferredInvite()),
              )
            : null,
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
            FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
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
                  : "Your Read Score and today's question are waiting.",
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

class _AuthHandoffScreen extends StatelessWidget {
  const _AuthHandoffScreen({
    required this.busy,
    required this.onRetry,
    required this.onSignIn,
  });

  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final failed = !busy;
    return Scaffold(
      backgroundColor: RtwColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Container(
              width: 480,
              padding: const EdgeInsets.fromLTRB(40, 44, 40, 40),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: RtwColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1428241C),
                    blurRadius: 48,
                    offset: Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RtwLogo(),
                  const SizedBox(height: 44),
                  if (busy)
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        color: RtwColors.blue,
                        strokeWidth: 3,
                      ),
                    )
                  else
                    const Icon(
                      Icons.error_outline_rounded,
                      color: RtwColors.clay,
                      size: 38,
                    ),
                  const SizedBox(height: 28),
                  Text(
                    failed
                        ? 'We couldn\'t open your account.'
                        : 'Opening Read the World',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge!.copyWith(
                      fontSize: 34,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    failed
                        ? 'The secure link may have expired. Try again or sign in instead.'
                        : 'Signing you in securely.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (failed) ...[
                    const SizedBox(height: 30),
                    RtwButton(label: 'Try again', onPressed: onRetry),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: onSignIn,
                      style: _authTextButtonStyle(),
                      child: const Text('Sign in instead'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    required this.creating,
    required this.phoneMode,
    required this.obscure,
    required this.busy,
    required this.errorText,
    required this.emailController,
    required this.passwordController,
    required this.phoneController,
    required this.phoneCodeController,
    required this.phoneCodeSent,
    required this.onSelectEmail,
    required this.onSelectPhone,
    required this.onToggleMode,
    required this.onToggleObscure,
    required this.onSubmitEmail,
    required this.onSendPhoneCode,
    required this.onVerifyPhoneCode,
    required this.onEditPhone,
    required this.onGoogle,
    required this.onApple,
    required this.onForgotPassword,
    this.invitePrompt,
    this.mobile = false,
  });

  final bool creating;
  final bool phoneMode;
  final bool obscure;
  final bool busy;
  final String? errorText;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController phoneController;
  final TextEditingController phoneCodeController;
  final bool phoneCodeSent;
  final VoidCallback onSelectEmail;
  final VoidCallback onSelectPhone;
  final VoidCallback onToggleMode;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmitEmail;
  final VoidCallback onSendPhoneCode;
  final VoidCallback onVerifyPhoneCode;
  final VoidCallback onEditPhone;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onForgotPassword;
  final Widget? invitePrompt;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final title = phoneMode
        ? 'Sign in by phone.'
        : creating
        ? 'Create your account.'
        : 'Welcome back.';
    final subtitle = phoneMode
        ? 'We’ll text you a one-time code.'
        : creating
        ? 'Free, forever. One question a day.'
        : 'Sign in to save your answers.';
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
        if (invitePrompt != null) ...[
          const SizedBox(height: 18),
          invitePrompt!,
        ],
        const SizedBox(height: 24),
        _AuthMethodTabs(
          phoneMode: phoneMode,
          busy: busy,
          onSelectEmail: onSelectEmail,
          onSelectPhone: onSelectPhone,
        ),
        const SizedBox(height: 22),
        if (phoneMode)
          _PhoneAuthFields(
            busy: busy,
            codeSent: phoneCodeSent,
            phoneController: phoneController,
            codeController: phoneCodeController,
            onSendCode: onSendPhoneCode,
            onVerifyCode: onVerifyPhoneCode,
            onEditPhone: onEditPhone,
          )
        else ...[
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
        ],
        SizedBox(height: mobile ? 22 : 24),
        if (!phoneMode)
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
        if (creating && !phoneMode) ...[
          const SizedBox(height: 12),
          const _AuthLegalNotice(),
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
        SizedBox(height: mobile ? 32 : 28),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (phoneMode) ...[
                Text(
                  'Prefer email? ',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                InkWell(
                  onTap: onSelectEmail,
                  child: Text(
                    'Use email instead',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: RtwColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ] else ...[
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
            ],
          ),
        ),
      ],
    );
  }
}

class _DeferredInvitePrompt extends StatelessWidget {
  const _DeferredInvitePrompt({
    required this.saved,
    required this.busy,
    required this.invalid,
    required this.onPaste,
  });

  final bool saved;
  final bool busy;
  final bool invalid;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RtwColors.blue.withValues(alpha: 0.08),
        border: Border.all(color: RtwColors.blue.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            saved ? 'Room invite saved' : 'Finish your room invite',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: RtwColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            saved
                ? 'Sign in or create an account. We’ll take you to the room next.'
                : 'Paste the invite you opened before installing the app.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(fontSize: 13, height: 1.4),
          ),
          if (!saved) ...[
            const SizedBox(height: 9),
            TextButton(
              onPressed: busy ? null : onPaste,
              style: _authTextButtonStyle(),
              child: Text(busy ? 'Checking invite…' : 'Paste invite'),
            ),
          ],
          if (invalid) ...[
            const SizedBox(height: 5),
            Text(
              'That copied link is not a Read the World room invite.',
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: RtwColors.clay,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthLegalNotice extends StatelessWidget {
  const _AuthLegalNotice();

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(fontSize: 12, color: RtwColors.faint);
    final linkStyle = baseStyle.copyWith(
      color: RtwColors.blue,
      fontWeight: FontWeight.w800,
    );

    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('By creating an account, you agree to our ', style: baseStyle),
          InkWell(
            onTap: () => _openExternalUri(_termsUri),
            child: Text('Terms', style: linkStyle),
          ),
          Text(' and ', style: baseStyle),
          InkWell(
            onTap: () => _openExternalUri(_privacyUri),
            child: Text('Privacy Policy', style: linkStyle),
          ),
          Text('.', style: baseStyle),
        ],
      ),
    );
  }
}

class _AuthMethodTabs extends StatelessWidget {
  const _AuthMethodTabs({
    required this.phoneMode,
    required this.busy,
    required this.onSelectEmail,
    required this.onSelectPhone,
  });

  final bool phoneMode;
  final bool busy;
  final VoidCallback onSelectEmail;
  final VoidCallback onSelectPhone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: RtwColors.card,
        border: Border.all(color: RtwColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AuthMethodTab(
              label: 'Email',
              selected: !phoneMode,
              onTap: busy ? null : onSelectEmail,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _AuthMethodTab(
              label: 'Phone',
              selected: phoneMode,
              onTap: busy ? null : onSelectPhone,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthMethodTab extends StatelessWidget {
  const _AuthMethodTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? RtwColors.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: selected ? RtwColors.paper : RtwColors.subText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneAuthFields extends StatelessWidget {
  const _PhoneAuthFields({
    required this.busy,
    required this.codeSent,
    required this.phoneController,
    required this.codeController,
    required this.onSendCode,
    required this.onVerifyCode,
    required this.onEditPhone,
  });

  final bool busy;
  final bool codeSent;
  final TextEditingController phoneController;
  final TextEditingController codeController;
  final VoidCallback onSendCode;
  final VoidCallback onVerifyCode;
  final VoidCallback onEditPhone;

  @override
  Widget build(BuildContext context) {
    if (codeSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('Verification code'),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : onEditPhone,
                style: _authTextButtonStyle(),
                child: const Text('Edit phone'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: codeController,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textInputAction: TextInputAction.done,
            enabled: !busy,
            onSubmitted: (_) => onVerifyCode(),
            decoration: const InputDecoration(hintText: '123456'),
          ),
          const SizedBox(height: 14),
          RtwButton(
            label: busy ? 'Checking...' : 'Verify code',
            onPressed: busy ? null : onVerifyCode,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: busy ? null : onSendCode,
              style: _authTextButtonStyle(),
              child: const Text('Send a new code'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Phone number'),
        const SizedBox(height: 8),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          textInputAction: TextInputAction.done,
          enabled: !busy,
          onSubmitted: (_) => onSendCode(),
          decoration: const InputDecoration(hintText: '+1 555 123 4567'),
        ),
        const SizedBox(height: 14),
        RtwButton(
          label: busy ? 'Sending...' : 'Text me a code',
          onPressed: busy ? null : onSendCode,
        ),
        const SizedBox(height: 10),
        Text(
          'Message and data rates may apply.',
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: RtwColors.faint,
            fontSize: 12,
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
  const ShortLinkScreen({
    super.key,
    required this.code,
    this.unsupported = false,
  });

  final String code;

  /// Legacy v1 links (friend invites, result shares) that no longer have a
  /// destination: skip resolution and show the dead-end state directly.
  final bool unsupported;

  @override
  ConsumerState<ShortLinkScreen> createState() => _ShortLinkScreenState();
}

class _ShortLinkScreenState extends ConsumerState<ShortLinkScreen> {
  bool failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.unsupported) {
      failed = true;
      return;
    }
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
                ? (widget.unsupported
                      ? 'This link is no longer supported.'
                      : (controller.lastError ??
                            'The link may have expired or been removed.'))
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
