import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// Shown when the person says they are not 18 or older (both languages; the error box picks one).
const notOldEnoughMessage =
    'Malvoya-tilin voi luoda vain 18 vuotta täyttänyt. / You must be 18 or older to create a Malvoya account.';

/// The "I am 18 or older" checkbox used on the register screen and in [askAgeConfirmation].
class AgeCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const AgeCheckbox({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(MRadius.sm),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: MSpace.xs),
          child: Row(
            children: [
              Checkbox(
                value: value,
                activeColor: AppTheme.primary,
                checkColor: AppTheme.onBrand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                onChanged: (v) => onChanged(v ?? false),
              ),
              const SizedBox(width: MSpace.xs),
              Expanded(
                child: Text(
                  tr(context, 'I am 18 or older', 'Olen täyttänyt 18 vuotta'),
                  style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w700, color: AppTheme.primaryText(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks a person creating a new account through Google, Apple, phone or an email code to confirm
/// that they are 18 or older. True once they ticked the box and continued.
Future<bool> askAgeConfirmation(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      var checked = false;
      return StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(tr(ctx, 'One more thing', 'Vielä yksi asia')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(ctx, 'You are creating a new Malvoya account. Accounts are for people aged 18 or older.',
                    'Olet luomassa uutta Malvoya-tiliä. Tilin voi luoda 18 vuotta täyttänyt.'),
                style: TextStyle(fontSize: MTextSize.bodyM, height: 1.4, color: AppTheme.primaryText(ctx)),
              ),
              const SizedBox(height: MSpace.md),
              AgeCheckbox(value: checked, onChanged: (v) => setDialog(() => checked = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
            FilledButton(
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: Text(tr(ctx, 'Continue', 'Jatka')),
            ),
          ],
        ),
      );
    },
  );
  return ok == true;
}

/// Finishes a social sign-in that answered [AuthService.ageConfirmationRequired]: asks the
/// person and repeats the request with `ageConfirmed: true`. Any other result is returned as it is.
Future<String?> resolveAgeGate(BuildContext context, AuthService auth, String? result) async {
  if (result != AuthService.ageConfirmationRequired) return result;
  if (!context.mounted) {
    auth.cancelAgeRetry();
    return 'Please sign in again.';
  }
  final confirmed = await askAgeConfirmation(context);
  if (!confirmed) {
    auth.cancelAgeRetry();
    return notOldEnoughMessage;
  }
  return auth.retryWithAgeConfirmed();
}
