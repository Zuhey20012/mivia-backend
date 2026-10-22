// PRH/YTJ business-ID check of a store (API 2.11). It pre-fills the admin's decision; it never approves anything.
export interface BusinessCheck {
  required: boolean;
  businessId: string | null;
  verificationStatus: 'matched' | 'name_mismatch' | 'not_found' | 'inactive' | 'unavailable' | null;
  registeredName: string | null;
  registeredAt: string | null;
  checkedAt: string | null;
}

const LOOK: Record<string, { cls: string; label: string; hint: string }> = {
  matched:       { cls: 'badge-green',  label: 'Registry: matched',       hint: 'The Y-tunnus exists, the company is active and its registered name matches the store.' },
  name_mismatch: { cls: 'badge-yellow', label: 'Registry: other name',     hint: 'The Y-tunnus exists and is active, but the registered name differs from the store name. Check that they belong together.' },
  not_found:     { cls: 'badge-red',    label: 'Registry: not found',      hint: 'PRH has no company with this Y-tunnus. Ask the seller to check it.' },
  inactive:      { cls: 'badge-red',    label: 'Registry: ceased',         hint: 'The company has ceased, was removed from the register or its business ID was invalidated.' },
  unavailable:   { cls: 'badge-gray',   label: 'Registry: no answer',      hint: 'PRH did not answer. Run the check again later.' },
};

export function BusinessCheckBadge({ check }: { check?: BusinessCheck | null }) {
  if (!check) return <span className="badge-gray">—</span>;
  if (!check.required) return <span className="badge-gray" title="Private sellers have no Y-tunnus">Private seller</span>;
  if (!check.verificationStatus) return <span className="badge-gray" title="The lookup has not finished yet">Not checked</span>;
  const look = LOOK[check.verificationStatus] ?? LOOK.unavailable;
  const details = [
    look.hint,
    check.businessId ? `Y-tunnus ${check.businessId}` : '',
    check.registeredName ? `Registered name: ${check.registeredName}` : '',
    check.registeredAt ? `Registered: ${new Date(check.registeredAt).toLocaleDateString('fi-FI')}` : '',
    check.checkedAt ? `Checked: ${new Date(check.checkedAt).toLocaleString('fi-FI')}` : '',
  ].filter(Boolean).join('\n');
  return <span className={look.cls} title={details}>{look.label}</span>;
}

/** The facts behind the badge, for the approval view. */
export function BusinessCheckDetails({ check }: { check?: BusinessCheck | null }) {
  if (!check?.required) return null;
  return (
    <p style={{ color: '#3C3C43', fontSize: '0.75rem', marginTop: '0.375rem', display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
      <BusinessCheckBadge check={check} />
      <span>Y-tunnus {check.businessId}</span>
      {check.registeredName && <span>· registered as <strong>{check.registeredName}</strong></span>}
      {check.registeredAt && <span>· since {new Date(check.registeredAt).toLocaleDateString('fi-FI')}</span>}
      {check.checkedAt && <span style={{ color: '#8E8E93' }}>· checked {new Date(check.checkedAt).toLocaleString('fi-FI')}</span>}
    </p>
  );
}
