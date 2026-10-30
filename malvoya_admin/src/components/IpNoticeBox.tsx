/**
 * A copyright / trademark notice (DSA Art. 16(2), API 2.16): who sent it, the work or mark, where it is used and the
 * good-faith statement. Shown in the report queues; removal goes through the usual statement-of-reasons flow, and the
 * seller is told what was reported, not the notifier's name or email (legal/ip_notice.md).
 */
export type IpNotice = {
  name?: string;
  email?: string;
  work?: string;
  location?: string;
  onBehalfOf?: string;
  goodFaith?: boolean;
  at?: string;
} | null | undefined;

export default function IpNoticeBox({ notice }: { notice: IpNotice }) {
  if (!notice) return null;
  return (
    <div className="mt-2 max-w-sm rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-gray-700">
      <p className="font-semibold text-amber-800">IP notice (DSA Art. 16)</p>
      <p><span className="text-gray-500">From:</span> {notice.name ?? '(removed)'}{notice.email ? ` · ${notice.email}` : ''}{notice.onBehalfOf ? ` · for ${notice.onBehalfOf}` : ''}</p>
      <p><span className="text-gray-500">Work or mark:</span> {notice.work}</p>
      <p><span className="text-gray-500">Where:</span> {notice.location}</p>
      <p className="text-gray-500">{notice.goodFaith ? 'Good-faith statement given' : 'No good-faith statement'}{notice.at ? ` · ${new Date(notice.at).toLocaleString('fi-FI')}` : ''}</p>
    </div>
  );
}
