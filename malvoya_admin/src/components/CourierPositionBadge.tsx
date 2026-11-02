// A courier's position status (API 2.16.1, GET /admin/couriers and /admin/orders → `position`).
// Only the status and its times are shown here; the admin panel never shows a courier's coordinates.
export interface CourierPosition {
  status: 'live' | 'stale' | 'none';
  reportedAt: string | null;
  clearedAt: string | null;
}

/** Finnish wall-clock time, e.g. "31.10. 17:05" */
const hel = (iso: string) => new Date(iso).toLocaleString('fi-FI', {
  timeZone: 'Europe/Helsinki', day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit',
});

const LOOK: Record<CourierPosition['status'], { cls: string; label: string; hint: string }> = {
  live:  { cls: 'badge-green',  label: 'Position: live',  hint: 'The app reported a position in the last 2 minutes.' },
  stale: { cls: 'badge-yellow', label: 'Position: stale', hint: 'The last position is older than 2 minutes, so it counts as unknown (no ride pay, no arrival checks).' },
  none:  { cls: 'badge-gray',   label: 'No position',     hint: 'Offline, never sent, or cleared.' },
};

export function CourierPositionBadge({ position }: { position?: CourierPosition | null }) {
  // Servers before 2.16.1 send no position status
  if (!position) return null;
  const look = LOOK[position.status] ?? LOOK.none;
  const cleared = position.status === 'none' && position.clearedAt;
  const hint = [
    cleared
      ? 'No update arrived for 15 minutes, so the position was cleared automatically. An idle courier was set offline; a courier carrying a job keeps it.'
      : look.hint,
    position.reportedAt ? `Last reported: ${hel(position.reportedAt)}` : '',
    cleared ? `Cleared: ${hel(position.clearedAt!)}` : '',
  ].filter(Boolean).join('\n');
  return (
    <span style={{ display: 'inline-flex', flexDirection: 'column', gap: '0.125rem' }} title={hint}>
      <span className={look.cls}>{look.label}</span>
      {position.status !== 'none' && position.reportedAt && (
        <span style={{ color: '#8E8E93', fontSize: '0.75rem' }}>reported {hel(position.reportedAt)}</span>
      )}
      {cleared && (
        <span style={{ color: '#8E8E93', fontSize: '0.75rem' }}>cleared {hel(position.clearedAt!)}</span>
      )}
    </span>
  );
}
