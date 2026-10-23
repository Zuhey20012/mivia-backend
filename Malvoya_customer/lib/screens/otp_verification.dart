import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../auth_service.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  bool _loading = false;

  Future<void> _verifyOtp() async {
    String otp = _controllers.map((e) => e.text).join();
    if (otp.length < 6) return;

    setState(() => _loading = true);
    
    final error = await Provider.of<AuthService>(context, listen: false)
        .signInWithOtp(widget.verificationId, otp);

    if (error == null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (mounted) {
      setState(() => _loading = false);
      MSnack.show(context, error ?? 'Invalid OTP. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Phone')),
      body: Padding(
        padding: const EdgeInsets.all(MSpace.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: MSpace.xl),
            Text(
              'Enter the 6-digit code sent to',
              style: TextStyle(fontSize: MTextSize.bodyL, color: AppTheme.secondaryText(context)),
            ),
            const SizedBox(height: MSpace.sm),
            Text(
              widget.phoneNumber,
              style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: MSpace.x4l),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (index) {
                return SizedBox(
                  width: 45,
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    decoration: InputDecoration(
                      counterText: '',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(MRadius.sm),
                        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty && index < 5) {
                        _focusNodes[index + 1].requestFocus();
                      } else if (value.isEmpty && index > 0) {
                        _focusNodes[index - 1].requestFocus();
                      }
                      if (_controllers.every((e) => e.text.isNotEmpty)) {
                        _verifyOtp();
                      }
                    },
                  ),
                );
              }),
            ),
            const SizedBox(height: MSpace.x4l),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _loading ? null : _verifyOtp,
                child: _loading 
                  ? const CircularProgressIndicator(color: AppTheme.onBrand)
                  : const Text('Verify & Continue'),
              ),
            ),
            const SizedBox(height: MSpace.xl),
            TextButton(
              onPressed: () {},
              child: const Text('Resend Code'),
            ),
          ],
        ),
      ),
    );
  }
}
