import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';

import '../config/theme.dart';
import '../l10n.dart';
import 'register.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../realtime_notification_service.dart';
import '../widgets/forgot_password_sheet.dart';

class LoginScreen extends StatefulWidget {
  /// Opened from inside the app (a guest going to pay, Profile…): closes itself once signed in,
  /// so the customer lands back where they were with their bag intact.
  final bool returnAfterSignIn;
  const LoginScreen({super.key, this.returnAfterSignIn = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePass = true;
  String? _error;
  // The last sign-in failed on the email/password check: offer the reset right there
  bool _wrongPassword = false;

  AuthService? _auth;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    // Explicitly start with blank fields - no autofill or saved email at top
    _emailCtrl.clear();
    _passCtrl.clear();
    if (widget.returnAfterSignIn) {
      _auth = Provider.of<AuthService>(context, listen: false)..addListener(_onAuth);
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuth);
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Signed in (any method, or a new account): go back to the screen that opened sign-in. The short
  /// wait lets a code sheet or the register screen close itself first.
  void _onAuth() {
    if (_returned || !(_auth?.isAuthenticated ?? false)) return;
    _returned = true;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      final nav = Navigator.of(context);
      nav.popUntil((r) => r == route);
      nav.pop(true);
    });
  }

  Future<void> _handleLogin() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = tr(context, 'Please enter your email and password.', 'Kirjoita sähköpostiosoitteesi ja salasanasi.'));
      return;
    }
    setState(() { _loading = true; _error = null; _wrongPassword = false; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    if (mounted) {
      if (err != null) {
        setState(() {
          _error = localizeServerMessage(context, err);
          _wrongPassword = err == 'Invalid credentials' || err == 'Invalid email or password.';
          _loading = false;
        });
      } else {
        RealtimeNotificationService.notifyCustomerJoined(
          context,
          email: _emailCtrl.text.trim(),
          name: auth.currentUser?.name ?? 'Customer',
        );
      }
    }
  }

  /// Email → code → new password. Signs in at the end, so the customer carries on where they were.
  Future<void> _openForgotPassword() async {
    final typed = _emailCtrl.text.trim();
    final outcome = await showForgotPasswordSheet(context, email: typed.contains('@') ? typed : null);
    if (outcome == null || !mounted) return;
    _emailCtrl.text = outcome.email;
    _passCtrl.clear();
    setState(() { _error = null; _wrongPassword = false; });
    MSnack.show(context, outcome.signedIn
          ? tr(context, 'New password saved. You are signed in.', 'Uusi salasana tallennettu. Olet kirjautunut sisään.')
          : tr(context, 'New password saved. Sign in with it now.', 'Uusi salasana tallennettu. Kirjaudu sillä nyt sisään.'));
  }

  Future<void> _handleGoogle() async {
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.loginWithGoogle();
    if (mounted) {
      if (err != null) {
        setState(() { _error = localizeServerMessage(context, err); _loading = false; });
      } else {
        final email = auth.currentUser?.email ?? '';
        final name = auth.currentUser?.name ?? 'Customer';
        if (email.isNotEmpty) {
          RealtimeNotificationService.notifyCustomerJoined(
            context,
            email: email,
            name: name,
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(email.isEmpty
                ? tr(context, 'Signed in with Google', 'Kirjauduttu Googlella')
                : tr(context, 'Signed in with Google as $email', 'Kirjauduttu Googlella: $email')),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showPhoneDialog() {
    final l10n = AppLocalizations.of(context);
    final phoneCtrl = TextEditingController();
    final otpCtrl = TextEditingController();
    int step = 1; // 1 = Phone number, 2 = 6-digit SMS verification
    int countdown = 60;
    Timer? timer;
    String? verificationId;
    int? resendToken;
    bool isProcessing = false;

    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final inputBg = AppTheme.inputBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    String formatDestination(String input) {
      final trimmed = input.trim();
      if (trimmed.contains('@')) return trimmed;
      var p = trimmed.replaceAll(' ', '').replaceAll('-', '');
      if (p.startsWith('00')) {
        p = '+${p.substring(2)}';
      } else if (p.startsWith('0')) {
        p = '+358${p.substring(1)}';
      } else if (!p.startsWith('+')) {
        p = '+$p';
      }
      return p;
    }

    showMSheet(context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 20, left: 24, right: 24,
          ),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(MRadius.lg)),
            border: Border.all(color: cardBorder),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MSheetHandle(),
                const SizedBox(height: MSpace.xl),
                if (step == 1) ...[
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.shield_outlined, color: AppTheme.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.translate('signInWithPhone'), style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: textPrimary)),
                            Text(tr(context, 'We send a one-time code by text message or email', 'Lähetämme kertakäyttöisen koodin tekstiviestillä tai sähköpostiin'),
                                style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MSpace.xl),
                  Text(tr(context, 'Phone number or email', 'Puhelinnumero tai sähköposti'), style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w700, color: textPrimary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: TextStyle(color: textPrimary, fontSize: MTextSize.bodyL, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: tr(context, '+358… or name@example.com', '+358… tai nimi@esimerkki.fi'),
                      hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.6)),
                      prefixIcon: const Icon(Icons.phonelink_lock_rounded, color: AppTheme.primary),
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: cardBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: cardBorder)),
                    ),
                  ),
                  const SizedBox(height: MSpace.sm),
                  Text(tr(context, 'You will get a 6-digit code. Enter it on the next step.', 'Saat 6-numeroisen koodin. Kirjoita se seuraavassa vaiheessa.'),
                      style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: MSpace.lg),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: isProcessing ? null : () async {
                        final rawDestination = phoneCtrl.text.trim();
                        if (rawDestination.length < 5) {
                          MSnack.show(context, tr(context, 'Enter your phone number or email address.', 'Kirjoita puhelinnumerosi tai sähköpostiosoitteesi.'));
                          return;
                        }
                        final destination = formatDestination(rawDestination);
                        setDialogState(() => isProcessing = true);

                        if (!destination.contains('@')) {
                          // Real Firebase Phone Auth SMS
                          try {
                            await fb_auth.FirebaseAuth.instance.verifyPhoneNumber(
                              phoneNumber: destination,
                              timeout: const Duration(seconds: 60),
                              verificationCompleted: (fb_auth.PhoneAuthCredential credential) async {
                                try {
                                  final userCred = await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
                                  final userPhone = userCred.user?.phoneNumber ?? destination;
                                  final cleanDigits = userPhone.replaceAll(RegExp(r'[^0-9]'), '');
                                  final idToken = await userCred.user?.getIdToken();
                                  final auth = Provider.of<AuthService>(context, listen: false);
                                  final phoneErr = idToken == null
                                    ? 'Phone verification failed'
                                    : await auth.exchangeFirebasePhoneToken(idToken);
                                if (phoneErr != null) throw Exception(phoneErr);

                                  if (mounted) {
                                    RealtimeNotificationService.notifyCustomerJoined(
                                      context,
                                      email: '$cleanDigits@phone.malvoya.app',
                                      phone: userPhone,
                                      name: 'Customer ($userPhone)',
                                    );
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  debugPrint('Auto verification error: $e');
                                }
                              },
                              verificationFailed: (fb_auth.FirebaseAuthException e) async {
                                debugPrint('Firebase verification failed (${e.code}): falling back to backend Twilio SMS OTP');
                                final res = await RealtimeNotificationService.sendRealOtp(
                                  destination: destination,
                                  channel: 'sms',
                                );
                                setDialogState(() => isProcessing = false);
                                if (res['ok'] == true) {
                                  verificationId = null; // Mark as backend Twilio OTP
                                  countdown = 60;
                                  timer?.cancel();
                                  timer = Timer.periodic(const Duration(seconds: 1), (t) {
                                    if (countdown > 0) {
                                      setDialogState(() => countdown--);
                                    } else {
                                      t.cancel();
                                    }
                                  });
                                  setDialogState(() => step = 2);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.sms_rounded, color: MPalette.green, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(tr(context, 'Code sent by text message to $destination. Enter it below.',
                                                'Koodi lähetetty tekstiviestillä numeroon $destination. Kirjoita se alle.')),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: MPalette.night,
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 5),
                                    ),
                                  );
                                } else {
                                  MSnack.error(context, res['error'] ?? tr(context, 'The code could not be sent. Please try again.', 'Koodia ei voitu lähettää. Yritä uudelleen.'));
                                }
                              },
                              codeSent: (String verId, int? token) {
                                verificationId = verId;
                                resendToken = token;
                                countdown = 60;
                                timer?.cancel();
                                timer = Timer.periodic(const Duration(seconds: 1), (t) {
                                  if (countdown > 0) {
                                    setDialogState(() => countdown--);
                                  } else {
                                    t.cancel();
                                  }
                                });
                                setDialogState(() {
                                  step = 2;
                                  isProcessing = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.sms_rounded, color: MPalette.green, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(tr(context, 'Code sent by text message to $destination. Enter it below.',
                                              'Koodi lähetetty tekstiviestillä numeroon $destination. Kirjoita se alle.')),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: MPalette.night,
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              },
                              codeAutoRetrievalTimeout: (String verId) {
                                verificationId = verId;
                              },
                            );
                          } catch (e) {
                            debugPrint('Phone verification exception: $e, falling back to Twilio SMS');
                            final res = await RealtimeNotificationService.sendRealOtp(
                              destination: destination,
                              channel: 'sms',
                            );
                            setDialogState(() => isProcessing = false);
                            if (res['ok'] == true) {
                              verificationId = null;
                              countdown = 60;
                              timer?.cancel();
                              timer = Timer.periodic(const Duration(seconds: 1), (t) {
                                if (countdown > 0) {
                                  setDialogState(() => countdown--);
                                } else {
                                  t.cancel();
                                }
                              });
                              setDialogState(() => step = 2);
                            } else {
                              MSnack.error(context, res['error'] ?? tr(context, 'The code could not be sent. Check the number and try again.',
                                      'Koodia ei voitu lähettää. Tarkista numero ja yritä uudelleen.'));
                            }
                          }
                        } else {
                          // Email OTP
                          final res = await RealtimeNotificationService.sendRealOtp(
                            destination: destination,
                          );
                          setDialogState(() => isProcessing = false);
                          if (res['ok'] == true) {
                            countdown = 60;
                            timer?.cancel();
                            timer = Timer.periodic(const Duration(seconds: 1), (t) {
                              if (countdown > 0) {
                                setDialogState(() => countdown--);
                              } else {
                                t.cancel();
                              }
                            });
                            setDialogState(() => step = 2);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.mark_email_read_rounded, color: MPalette.green, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(tr(context, 'Code sent to $destination. Check your inbox.', 'Koodi lähetetty osoitteeseen $destination. Tarkista saapuneet viestit.')),
                                    ),
                                  ],
                                ),
                                backgroundColor: MPalette.night,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          } else {
                            MSnack.error(context, res['error'] ?? tr(context, 'The code could not be sent. Please try again.', 'Koodia ei voitu lähettää. Yritä uudelleen.'));
                          }
                        }
                      },
                      child: isProcessing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.onBrand, strokeWidth: 2))
                          : Text(l10n.translate('sendVerificationCode'), style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.bold, color: AppTheme.onBrand)),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: MPalette.mint, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.mark_chat_read_rounded, color: MPalette.green, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.translate('verifyPhoneCode'), style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: textPrimary)),
                            Text(tr(context, 'Code sent to ${formatDestination(phoneCtrl.text.trim())}', 'Koodi lähetetty: ${formatDestination(phoneCtrl.text.trim())}'),
                                style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MSpace.xl),
                  Text(l10n.translate('enterSmsCode'), style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w700, color: textPrimary)),
                  const SizedBox(height: MSpace.sm),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: MTextSize.displayS, fontWeight: FontWeight.bold, letterSpacing: 8, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: '------',
                      hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.5), letterSpacing: 8),
                      counterText: '',
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: cardBorder)),
                      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20)), borderSide: BorderSide(color: AppTheme.primary, width: 2)),
                    ),
                  ),
                  const SizedBox(height: MSpace.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        countdown > 0
                            ? tr(context, 'Resend in ${countdown}s', 'Uusi koodi $countdown s kuluttua')
                            : tr(context, 'Didn’t get it?', 'Eikö koodi tullut?'),
                        style: TextStyle(fontSize: MTextSize.caption, color: textSecondary),
                      ),
                      if (countdown == 0)
                        TextButton(
                          onPressed: () async {
                            countdown = 60;
                            timer?.cancel();
                            timer = Timer.periodic(const Duration(seconds: 1), (t) {
                              if (countdown > 0) {
                                setDialogState(() => countdown--);
                              } else {
                                t.cancel();
                              }
                            });
                            final destination = formatDestination(phoneCtrl.text.trim());
                            if (verificationId != null && !destination.contains('@')) {
                              await fb_auth.FirebaseAuth.instance.verifyPhoneNumber(
                                phoneNumber: destination,
                                forceResendingToken: resendToken,
                                timeout: const Duration(seconds: 60),
                                verificationCompleted: (_) {},
                                verificationFailed: (e) {
                                  MSnack.show(context, tr(context, 'The code could not be sent again. Please try again.', 'Koodia ei voitu lähettää uudelleen. Yritä uudelleen.'));
                                },
                                codeSent: (verId, token) {
                                  verificationId = verId;
                                  resendToken = token;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(tr(context, 'A new code was sent to your phone.', 'Uusi koodi lähetettiin puhelimeesi.')),
                                      backgroundColor: MPalette.night,
                                    ),
                                  );
                                },
                                codeAutoRetrievalTimeout: (verId) => verificationId = verId,
                              );
                            } else {
                              final res = await RealtimeNotificationService.sendRealOtp(
                                destination: destination,
                              );
                              if (res['ok'] == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(tr(context, 'A new code was sent.', 'Uusi koodi lähetettiin.')),
                                    backgroundColor: MPalette.night,
                                  ),
                                );
                              }
                            }
                          },
                          child: Text(tr(context, 'Send again', 'Lähetä uudelleen'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: MTextSize.label)),
                        ),
                    ],
                  ),
                  const SizedBox(height: MSpace.xxl),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: MSpace.lg),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: isProcessing ? null : () async {
                        final entered = otpCtrl.text.trim();
                        if (entered.length != 6) {
                          MSnack.show(context, tr(context, 'Enter the 6-digit code.', 'Kirjoita 6-numeroinen koodi.'));
                          return;
                        }
                        setDialogState(() => isProcessing = true);
                        final destination = formatDestination(phoneCtrl.text.trim());
                        final auth = Provider.of<AuthService>(context, listen: false);

                        if (verificationId != null) {
                          // Real Firebase Phone Auth
                          try {
                            final credential = fb_auth.PhoneAuthProvider.credential(
                              verificationId: verificationId!,
                              smsCode: entered,
                            );
                            final userCred = await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
                            final userPhone = userCred.user?.phoneNumber ?? destination;
                            final cleanDigits = userPhone.replaceAll(RegExp(r'[^0-9]'), '');
                            final idToken = await userCred.user?.getIdToken();

                            final phoneErr = idToken == null
                                    ? 'Phone verification failed'
                                    : await auth.exchangeFirebasePhoneToken(idToken);
                                if (phoneErr != null) throw Exception(phoneErr);

                            timer?.cancel();
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              RealtimeNotificationService.notifyCustomerJoined(
                                context,
                                email: '$cleanDigits@phone.malvoya.app',
                                phone: userPhone,
                                name: 'Customer ($userPhone)',
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(tr(context, 'You’re signed in. Welcome!', 'Olet kirjautunut sisään. Tervetuloa!')),
                                  backgroundColor: MPalette.green,
                                ),
                              );
                            }
                          } on fb_auth.FirebaseAuthException catch (e) {
                            setDialogState(() => isProcessing = false);
                            if (ctx.mounted) {
                              MSnack.error(ctx, e.code == 'invalid-verification-code' || e.code == 'session-expired'
                                      ? tr(context, 'That code is wrong or has expired. Check it or ask for a new one.',
                                          'Koodi on väärä tai vanhentunut. Tarkista se tai pyydä uusi.')
                                      : tr(context, 'The code could not be checked. Please try again.', 'Koodia ei voitu tarkistaa. Yritä uudelleen.'));
                            }
                          } catch (e) {
                            setDialogState(() => isProcessing = false);
                            if (ctx.mounted) {
                              MSnack.error(ctx, tr(context, 'Signing in did not work. Please try again.', 'Kirjautuminen ei onnistunut. Yritä uudelleen.'));
                            }
                          }
                        } else {
                          // Email OTP verification
                          final verifyRes = await RealtimeNotificationService.verifyRealOtp(
                            destination: destination,
                            code: entered,
                          );
                          setDialogState(() => isProcessing = false);
                          if (verifyRes['ok'] == true) {
                            await auth.saveSession(
                              verifyRes['user'],
                              verifyRes['accessToken'],
                              verifyRes['refreshToken'],
                            );
                            timer?.cancel();
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              RealtimeNotificationService.notifyCustomerJoined(
                                context,
                                email: destination,
                                name: verifyRes['user']?['name'] ?? 'Customer',
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(tr(context, 'You’re signed in.', 'Olet kirjautunut sisään.')),
                                  backgroundColor: MPalette.green,
                                ),
                              );
                            }
                          } else {
                            if (ctx.mounted) {
                              MSnack.error(ctx, verifyRes['error'] ?? tr(context, 'That code is not right.', 'Koodi ei ole oikein.'));
                            }
                          }
                        }
                      },
                      child: isProcessing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.onBrand, strokeWidth: 2))
                          : Text(l10n.translate('verifyAndSignIn'), style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.bold, color: AppTheme.onBrand)),
                    ),
                  ),
                  const SizedBox(height: MSpace.sm),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        timer?.cancel();
                        setDialogState(() {
                          step = 1;
                          verificationId = null;
                        });
                      },
                      child: Text(l10n.translate('changePhone'), style: TextStyle(color: textSecondary, fontSize: MTextSize.label)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ), transparent: true, isScrollControlled: true, useSafeArea: false);
  }

  void _showLanguageSelector(BuildContext context) {
    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MRadius.lg)),
      ),
      builder: (ctx) {
        return Consumer<LocaleProvider>(
          builder: (context, provider, _) {
            final l10n = AppLocalizations.of(context);
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.lg, MSpace.xl, MSpace.xxl),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(MRadius.lg)),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MSheetHandle(),
                  const SizedBox(height: MSpace.lg),
                  Text(l10n.translate('selectLanguagePrompt'), style: TextStyle(fontSize: MTextSize.displayS, fontWeight: FontWeight.bold, color: textPrimary)),
                  const SizedBox(height: MSpace.xs),
                  Text(l10n.translate('languagesSubtitle'), style: TextStyle(fontSize: MTextSize.label, color: textSecondary)),
                  const SizedBox(height: MSpace.md),
                  Divider(height: 1, color: cardBorder),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: AppLocalizations.languages.entries.map((entry) {
                        final isSelected = provider.locale.languageCode == entry.key;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: 2),
                          title: Text(
                            entry.value,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: MTextSize.bodyL,
                              color: isSelected ? AppTheme.primary : textPrimary,
                            ),
                          ),
                          trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary) : null,
                          onTap: () {
                            provider.setLocale(Locale(entry.key));
                            Navigator.pop(ctx);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentLangKey = Provider.of<LocaleProvider>(context).locale.languageCode;
    final currentLangLabel = AppLocalizations.languages[currentLangKey] ?? 'English';
    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: MSpace.lg),

              // Top row: back (when opened from inside the app) and the language switcher pill
              Row(
                children: [
                  if (widget.returnAfterSignIn)
                    IconButton(
                      tooltip: tr(context, 'Back', 'Takaisin'),
                      onPressed: () => Navigator.maybePop(context),
                      icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                    ),
                  const Spacer(),
                  GestureDetector(
                  onTap: () => _showLanguageSelector(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 6),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.language_rounded, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          currentLangLabel.split(' ').first, // Shows flag
                          style: const TextStyle(fontSize: MTextSize.bodyM),
                        ),
                        const SizedBox(width: MSpace.xs),
                        Icon(Icons.arrow_drop_down, size: 18, color: textSecondary),
                      ],
                    ),
                  ),
                ),
                ],
              ),

              const SizedBox(height: MSpace.xxl),

              // Logo + Branding (Centered, clean Nordic style)
              Center(
                child: Column(
                  children: [
                    BrandTile(size: 76, background: AppTheme.primary),
                    const SizedBox(height: MSpace.lg),
                    Text('Malvoya', style: AppTheme.display(context, size: 34)),
                    const SizedBox(height: MSpace.xs),
                    Text(l10n.translate('boutiques'), style: TextStyle(fontSize: MTextSize.bodyM, color: textSecondary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              Text(l10n.translate('welcomeBack'), style: AppTheme.display(context, size: 28)),
              const SizedBox(height: 6),
              Text(l10n.translate('signInToContinue'), style: TextStyle(fontSize: MTextSize.bodyM, color: textSecondary)),
              const SizedBox(height: 28),

              // Email field (autocorrect and suggestions off, no prefilled email)
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  labelText: tr(context, 'Email or phone number', 'Sähköposti tai puhelinnumero'),
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),

              // Password field
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleLogin(),
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  labelText: l10n.translate('password'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePass ? tr(context, 'Show password', 'Näytä salasana') : tr(context, 'Hide password', 'Piilota salasana'),
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _openForgotPassword,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(tr(context, 'Forgot password?', 'Unohditko salasanan?'), style: const TextStyle(fontSize: MTextSize.bodyM)),
                ),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: MPalette.redLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MPalette.redLine),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: MPalette.red, size: 18),
                      const SizedBox(width: MSpace.sm),
                      Expanded(child: Text(_error!, style: const TextStyle(color: MPalette.red, fontSize: MTextSize.label))),
                    ],
                  ),
                ),
                if (_wrongPassword)
                  Padding(
                    padding: const EdgeInsets.only(top: MSpace.xs),
                    child: TextButton.icon(
                      onPressed: _openForgotPassword,
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      icon: const Icon(Icons.key_rounded, size: 18),
                      label: Text(tr(context, 'Forgot password? Reset it by email', 'Unohditko salasanan? Vaihda se sähköpostilla')),
                    ),
                  ),
              ],

              const SizedBox(height: MSpace.xxl),

              // Login button
              MButton(label: l10n.translate('login'), expand: true, loading: _loading, onPressed: _handleLogin),

              const SizedBox(height: MSpace.xxl),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: cardBorder)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
                    child: Text(l10n.translate('or'), style: TextStyle(color: textSecondary, fontSize: MTextSize.label, fontWeight: FontWeight.w500)),
                  ),
                  Expanded(child: Divider(color: cardBorder)),
                ],
              ),

              const SizedBox(height: MSpace.xl),

              // Google Sign-In button
              OutlinedButton(
                onPressed: _handleGoogle,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: cardBg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Google's own brand blue (their sign-in button guideline), not a Malvoya colour
                    const Icon(Icons.g_mobiledata_rounded, size: 28, color: Color(0xFF4285F4)),
                    const SizedBox(width: MSpace.sm),
                    Text(l10n.translate('continueWithGoogle'), style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, fontSize: MTextSize.bodyL)),
                  ],
                ),
              ),

              const SizedBox(height: MSpace.md),

              // Phone Sign-In button
              OutlinedButton(
                onPressed: _showPhoneDialog,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: cardBg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.phone_iphone_rounded, size: 20, color: AppTheme.primary),
                    const SizedBox(width: MSpace.sm),
                    Text(l10n.translate('continueWithPhone'), style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, fontSize: MTextSize.bodyL)),
                  ],
                ),
              ),

              const SizedBox(height: MSpace.md),

              // Malvoya Continue as Guest button (not when a guest opened sign-in from inside the app)
              if (!widget.returnAfterSignIn)
              OutlinedButton(
                onPressed: () async {
                  setState(() => _loading = true);
                  final auth = Provider.of<AuthService>(context, listen: false);
                  await auth.loginAsGuest();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: AppTheme.sunshine,
                  foregroundColor: AppTheme.ink,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.explore_outlined, size: 20, color: AppTheme.ink),
                    const SizedBox(width: MSpace.sm),
                    Text(
                      l10n.translate('guestLogin'),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink, fontSize: MTextSize.bodyL),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: MSpace.x3l),

              // Register link
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
                  },
                  child: Text.rich(
                    TextSpan(
                      text: '${l10n.translate('dontHaveAccount')} ',
                      style: TextStyle(color: textSecondary, fontSize: MTextSize.bodyM),
                      children: [
                        TextSpan(
                          text: l10n.translate('createOne'),
                          style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: MSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
