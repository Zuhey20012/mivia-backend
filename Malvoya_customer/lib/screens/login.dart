import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/brand_mark.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import 'register.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../realtime_notification_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePass = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Explicitly start with blank fields - no autofill or saved email at top
    _emailCtrl.clear();
    _passCtrl.clear();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    if (mounted) {
      if (err != null) {
        setState(() { _error = err; _loading = false; });
      } else {
        RealtimeNotificationService.notifyCustomerJoined(
          context,
          email: _emailCtrl.text.trim(),
          name: auth.currentUser?.name ?? 'Customer',
        );
      }
    }
  }

  Future<void> _handleGoogle() async {
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.loginWithGoogle();
    if (mounted) {
      if (err != null) {
        setState(() { _error = err; _loading = false; });
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
            content: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('🔐 Google Security Alert: Sign-in verified for $email. Security alert dispatched to your Google Account email.'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF17131C),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 20, left: 24, right: 24,
          ),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: cardBorder),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
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
                            Text(l10n.translate('signInWithPhone'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                            Text('SMS- tai sähköpostivahvistus • Kertakäyttöinen turvakoodi', style: TextStyle(fontSize: 12, color: textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Puhelinnumero tai sähköposti', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: '+358... tai nimi@esimerkki.fi',
                      hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.6)),
                      prefixIcon: const Icon(Icons.phonelink_lock_rounded, color: AppTheme.primary),
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: cardBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: cardBorder)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Vastaanota aito 6-numeroinen vahvistuskoodi puhelimeen tai sähköpostiin.', style: TextStyle(fontSize: 11, color: textSecondary)),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: isProcessing ? null : () async {
                        final rawDestination = phoneCtrl.text.trim();
                        if (rawDestination.length < 5) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Syötä puhelinnumero tai sähköpostiosoite.')),
                          );
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
                                          const Icon(Icons.sms_rounded, color: Color(0xFF248A52), size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text('Vahvistuskoodi lähetetty tekstiviestillä kohteeseen $destination. Syötä koodi alle.'),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: const Color(0xFF1E293B),
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 5),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(res['error'] ?? e.message ?? 'Vahvistuskoodin lähetys epäonnistui.'),
                                      backgroundColor: Colors.red.shade700,
                                    ),
                                  );
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
                                        const Icon(Icons.sms_rounded, color: Color(0xFF248A52), size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text('Vahvistuskoodi lähetetty tekstiviestillä kohteeseen $destination. Syötä koodi alle.'),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: const Color(0xFF1E293B),
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Virhe: $e'), backgroundColor: Colors.red.shade700),
                              );
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
                                    const Icon(Icons.mark_email_read_rounded, color: Color(0xFF248A52), size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text('Vahvistuskoodi lähetetty sähköpostiin $destination. Tarkista saapuneet viestit.'),
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF1E293B),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(res['error'] ?? 'Vahvistuskoodin lähetys epäonnistui.'),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          }
                        }
                      },
                      child: isProcessing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(l10n.translate('sendVerificationCode'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.mark_chat_read_rounded, color: Color(0xFF248A52), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.translate('verifyPhoneCode'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                            Text('Koodi lähetetty kohteeseen ${formatDestination(phoneCtrl.text.trim())}', style: TextStyle(fontSize: 12, color: textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(l10n.translate('enterSmsCode'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8, color: textPrimary),
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
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        countdown > 0 ? 'Resend in ${countdown}s' : 'Resend code',
                        style: TextStyle(fontSize: 12, color: textSecondary),
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.message ?? 'Uudelleenlähetys epäonnistui.')),
                                  );
                                },
                                codeSent: (verId, token) {
                                  verificationId = verId;
                                  resendToken = token;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Uusi SMS-vahvistuskoodi lähetetty puhelimeesi.'),
                                      backgroundColor: Color(0xFF1E293B),
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
                                  const SnackBar(
                                    content: Text('Uusi vahvistuskoodi lähetetty.'),
                                    backgroundColor: Color(0xFF1E293B),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Resend', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 13)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: isProcessing ? null : () async {
                        final entered = otpCtrl.text.trim();
                        if (entered.length != 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Syötä 6-numeroinen vahvistuskoodi.')),
                          );
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
                                const SnackBar(
                                  content: Text('Kirjauduttu sisään onnistuneesti! Tervetuloa.'),
                                  backgroundColor: Color(0xFF248A52),
                                ),
                              );
                            }
                          } on fb_auth.FirebaseAuthException catch (e) {
                            setDialogState(() => isProcessing = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(e.message ?? 'Virheellinen tai vanhentunut vahvistuskoodi.'),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isProcessing = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Vahvistus epäonnistui: $e'),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
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
                                const SnackBar(
                                  content: Text('Kirjauduttu sisään onnistuneesti!'),
                                  backgroundColor: Color(0xFF248A52),
                                ),
                              );
                            }
                          } else {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(verifyRes['error'] ?? 'Virheellinen vahvistuskoodi.'),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          }
                        }
                      },
                      child: isProcessing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(l10n.translate('verifyAndSignIn'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        timer?.cancel();
                        setDialogState(() {
                          step = 1;
                          verificationId = null;
                        });
                      },
                      child: Text(l10n.translate('changePhone'), style: TextStyle(color: textSecondary, fontSize: 13)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLanguageSelector(BuildContext context) {
    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Consumer<LocaleProvider>(
          builder: (context, provider, _) {
            final l10n = AppLocalizations.of(context);
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.translate('selectLanguagePrompt'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textPrimary)),
                  const SizedBox(height: 4),
                  Text(l10n.translate('languagesSubtitle'), style: TextStyle(fontSize: 13, color: textSecondary)),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: cardBorder),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: AppLocalizations.languages.entries.map((entry) {
                        final isSelected = provider.locale.languageCode == entry.key;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          title: Text(
                            entry.value,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 16,
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
    final currentLangLabel = AppLocalizations.languages[currentLangKey] ?? '🇬🇧 English';
    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Top row: Language switcher pill
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => _showLanguageSelector(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, size: 18, color: textSecondary),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Logo + Branding (Centered, clean Nordic style)
              Center(
                child: Column(
                  children: [
                    BrandTile(size: 76, background: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text('Malvoya', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.8)),
                    const SizedBox(height: 4),
                    Text(l10n.translate('boutiques'), style: TextStyle(fontSize: 14, color: textSecondary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              Text(l10n.translate('welcomeBack'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(l10n.translate('signInToContinue'), style: TextStyle(fontSize: 14, color: textSecondary)),
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
                  labelText: '${l10n.translate('email')} / ${l10n.translate('phoneLabel')}',
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
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFCDD2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFD93025), size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFD93025), fontSize: 13))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Login button
              SizedBox(
                width: double.infinity,
                child: _loading
                    ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
                    : ElevatedButton(
                        onPressed: _handleLogin,
                        child: Text(l10n.translate('login')),
                      ),
              ),

              const SizedBox(height: 24),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: cardBorder)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(l10n.translate('or'), style: TextStyle(color: textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                  Expanded(child: Divider(color: cardBorder)),
                ],
              ),

              const SizedBox(height: 20),

              // Google Sign-In button
              OutlinedButton(
                onPressed: _handleGoogle,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  backgroundColor: cardBg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.g_mobiledata_rounded, size: 28, color: Color(0xFF4285F4)),
                    const SizedBox(width: 8),
                    Text(l10n.translate('continueWithGoogle'), style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, fontSize: 15)),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Phone Sign-In button
              OutlinedButton(
                onPressed: _showPhoneDialog,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  backgroundColor: cardBg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.phone_iphone_rounded, size: 20, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(l10n.translate('continueWithPhone'), style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, fontSize: 15)),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Malvoya Continue as Guest button
              OutlinedButton(
                onPressed: () async {
                  setState(() => _loading = true);
                  final auth = Provider.of<AuthService>(context, listen: false);
                  await auth.loginAsGuest();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.04),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.explore_outlined, size: 20, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      l10n.translate('guestLogin'),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 15),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Register link
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
                  },
                  child: RichText(
                    text: TextSpan(
                      text: '${l10n.translate('dontHaveAccount')} ',
                      style: TextStyle(color: textSecondary, fontSize: 14),
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

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
