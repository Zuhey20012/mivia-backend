/** Clears two-step sign-in (account deletion, an admin reset from the SEED_ADMIN_* settings, turning it off). */
export const TWO_STEP_OFF = {
  totpSecret: null,
  totpEnabledAt: null,
  totpLastStep: null,
  totpRecoveryCodes: [] as string[],
  totpFailures: 0,
  totpLockedUntil: null,
};
