import { useCallback, useEffect, useState } from 'react';
import { RefreshCw, ExternalLink, Ban, Undo2, UserMinus } from 'lucide-react';
import api from '../utils/api';
import { Drawer, Overlay, ErrorBox, NoticeBox } from './Dialog';
import { type Raw, num, str, obj, firstList, euro, fiDate, errorText, parseEuroToCents } from '../utils/parse';

// GET /admin/orders/:id (2.16, contract C13): the order, its items, customer/store/courier, a timeline of status
// timestamps, payments/refunds, payouts, chat, delivery proof link, returns and disputes. Every part is read
// defensively: a part the answer does not contain is shown as "not in the answer", never as "none".

type Detail = {
  order: Raw;
  items: Raw[];
  customer: Raw | null;
  store: Raw | null;
  courier: Raw | null;
  timeline: { label: string; at: string; note: string | null }[];
  refunds: Raw[] | null;
  payouts: Raw[] | null;
  messages: Raw[] | null;
  returns: Raw[] | null;
  disputes: Raw[] | null;
  proofUrl: string | null;
  refundableCents: number | null;
};

const TIMESTAMPS: [string, string][] = [
  ['createdAt', 'Checkout started'],
  ['paidAt', 'Paid'],
  ['confirmedAt', 'Store accepted'],
  ['dispatchStartedAt', 'Courier search started (scheduled)'],
  ['acceptedAt', 'Courier accepted the job'],
  ['courierArrivedAt', 'Courier at the shop'],
  ['readyAt', 'Store marked it ready'],
  ['pickedUpAt', 'Picked up'],
  ['deliveryProblemAt', 'Courier reported a delivery problem'],
  ['returnedToStoreAt', 'Taken back to the shop'],
  ['returnReceivedAt', 'Store got it back'],
  ['deliveredAt', 'Delivered / collected'],
  ['cancelledAt', 'Cancelled'],
  ['disputedAt', 'Card dispute opened'],
];

function parseTimeline(raw: unknown, order: Raw): Detail['timeline'] {
  const rows: Detail['timeline'] = [];
  if (Array.isArray(raw)) {
    for (const e of raw as Raw[]) {
      const at = str(e.at) ?? str(e.time) ?? str(e.createdAt) ?? str(e.timestamp);
      if (!at) continue;
      const key = str(e.label) ?? str(e.event) ?? str(e.status) ?? str(e.type) ?? str(e.key) ?? 'Event';
      rows.push({ label: TIMESTAMPS.find(([k]) => k === key)?.[1] ?? key, at, note: str(e.note) ?? str(e.detail) ?? str(e.reason) });
    }
  } else if (raw && typeof raw === 'object') {
    for (const [k, v] of Object.entries(raw as Raw)) {
      if (typeof v === 'string' && v) rows.push({ label: TIMESTAMPS.find(([key]) => key === k)?.[1] ?? k, at: v, note: null });
    }
  }
  if (rows.length === 0) {
    for (const [k, label] of TIMESTAMPS) {
      const at = str(order[k]);
      if (at) rows.push({ label, at, note: k === 'cancelledAt' ? str(order.cancelReason) : k === 'deliveryProblemAt' ? str(order.deliveryProblemReason) : null });
    }
  }
  return rows.sort((a, b) => new Date(a.at).getTime() - new Date(b.at).getTime());
}

function parseDetail(data: Raw): Detail {
  const order = obj(data.order ?? data);
  const payments = obj(data.payments ?? data.payment);
  const proof = data.deliveryProof ?? order.deliveryProof;
  const total = num(order.totalCents);
  const refunded = num(order.refundedCents) ?? num(payments.refundedCents) ?? 0;
  return {
    order,
    items: firstList(data.items, order.items) ?? [],
    customer: (data.customer ?? order.customer ?? order.user) ? obj(data.customer ?? order.customer ?? order.user) : null,
    store: (data.store ?? order.store) ? obj(data.store ?? order.store) : null,
    courier: (data.courier ?? order.courier) ? obj(data.courier ?? order.courier) : null,
    timeline: parseTimeline(data.timeline ?? order.timeline, order),
    refunds: firstList(data.refunds, payments.refunds, order.refunds),
    payouts: firstList(data.payouts, order.payouts),
    messages: firstList(data.messages, data.chat, obj(data.chat).messages, order.messages),
    returns: firstList(data.returns, order.returns),
    disputes: firstList(data.disputes, order.disputes),
    proofUrl: typeof proof === 'string' ? proof : str(obj(proof).url) ?? str(obj(proof).photoUrl) ?? str(data.deliveryProofUrl) ?? str(order.deliveryProofUrl),
    refundableCents: num(data.refundableCents) ?? num(payments.refundableCents) ?? num(order.refundableCents)
      ?? (total !== null && order.paymentStatus === 'SUCCEEDED' ? Math.max(0, total - refunded) : null),
  };
}

const statusBadge: Record<string, string> = {
  PENDING: 'badge-yellow', CONFIRMED: 'badge-blue', PROCESSING: 'badge-blue',
  SHIPPED: 'badge-blue', DELIVERED: 'badge-green', CANCELLED: 'badge-red', REFUNDED: 'badge-gray',
};

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-6">
      <h3 className="text-xs uppercase tracking-wide text-gray-400 font-medium mb-2">{title}</h3>
      {children}
    </section>
  );
}

function KV({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-4 py-1 text-sm border-b border-gray-50 last:border-0">
      <span className="text-gray-500">{k}</span>
      <span className="text-right break-words min-w-0">{v}</span>
    </div>
  );
}

const Missing = () => <p className="text-sm text-gray-400">Not in the API answer.</p>;

function Person({ p, kind }: { p: Raw | null; kind: string }) {
  if (!p) return <p className="text-sm text-gray-400">{kind === 'Courier' ? 'No courier assigned.' : 'Not in the API answer.'}</p>;
  const user = obj(p.user);
  const name = str(p.name) ?? str(user.name) ?? '—';
  const email = str(p.email) ?? str(user.email);
  const phone = str(p.phone) ?? str(user.phone);
  return (
    <div className="text-sm">
      <p className="font-medium">{name}{num(p.id) !== null && <span className="text-gray-400 font-normal"> · #{num(p.id)}</span>}</p>
      {email && <p className="text-gray-500">{email}</p>}
      {phone && <p className="text-gray-500"><a className="text-blue-600" href={`tel:${phone}`}>{phone}</a></p>}
      {str(p.address) && <p className="text-gray-500">{str(p.address)}</p>}
    </div>
  );
}

type Action = 'cancel' | 'refund' | 'unassign' | null;

export default function OrderDrawer({ orderId, onClose, onChanged }: { orderId: number; onClose: () => void; onChanged?: () => void }) {
  const [detail, setDetail] = useState<Detail | null>(null);
  const [error, setError] = useState('');
  const [reload, setReload] = useState(0);
  const [action, setAction] = useState<Action>(null);
  const [notice, setNotice] = useState('');

  const fetchDetail = useCallback(() => api.get(`/admin/orders/${orderId}`), [orderId]);

  useEffect(() => {
    let cancelled = false;
    fetchDetail()
      .then((r) => { if (!cancelled) { setDetail(parseDetail(obj(r.data))); setError(''); } })
      .catch((e) => { if (!cancelled) setError(errorText(e, `Could not load order #${orderId}.`)); });
    return () => { cancelled = true; };
  }, [fetchDetail, orderId, reload]);

  const done = (text: string) => {
    setAction(null);
    setNotice(text);
    setReload((n) => n + 1);
    onChanged?.();
  };

  const o = detail?.order ?? {};
  const status = str(o.status) ?? '';
  const paid = o.paymentStatus === 'SUCCEEDED';
  const canCancel = !!detail && !['CANCELLED', 'SHIPPED', 'DELIVERED', 'REFUNDED'].includes(status);
  const canRefund = !!detail && paid && (detail.refundableCents ?? 0) > 0;
  const canUnassign = !!detail && !!detail.courier && !['CANCELLED', 'DELIVERED', 'REFUNDED'].includes(status);

  return (
    <Drawer title={`Order #${orderId}`} onClose={onClose}>
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        {status && <span className={statusBadge[status] ?? 'badge-gray'}>{status}</span>}
        {str(o.paymentStatus) && <span className={paid ? 'badge-green' : o.paymentStatus === 'FAILED' ? 'badge-red' : 'badge-yellow'}>payment {str(o.paymentStatus)}</span>}
        {str(o.fulfilment) === 'PICKUP' && <span className="badge-purple">pickup</span>}
        {(str(o.disputedAt) || str(o.disputeStatus)) && <span className="badge-red">dispute {str(o.disputeStatus) ?? ''}</span>}
        <button className="apple-btn-secondary text-xs px-3 py-1.5 ml-auto" onClick={() => { setNotice(''); setReload((n) => n + 1); }}>
          <RefreshCw className="w-3 h-3" /> Refresh
        </button>
      </div>

      {notice && <div className="mb-4"><NoticeBox>{notice}</NoticeBox></div>}
      {error && <div className="mb-4"><ErrorBox>{error}</ErrorBox></div>}
      {!error && !detail && <p className="text-sm text-gray-400">Loading…</p>}

      {detail && (
        <>
          <div className="flex gap-2 flex-wrap mb-6">
            <button className="apple-btn-danger text-xs px-3 py-1.5" disabled={!canCancel} onClick={() => { setNotice(''); setAction('cancel'); }}
              title={canCancel ? 'Cancel the order and refund everything paid' : 'Only orders not yet picked up or delivered can be cancelled'}
              style={canCancel ? undefined : { opacity: 0.4, cursor: 'not-allowed' }}>
              <Ban className="w-3 h-3" /> Cancel with full refund
            </button>
            <button className="apple-btn-secondary text-xs px-3 py-1.5" disabled={!canRefund} onClick={() => { setNotice(''); setAction('refund'); }}
              title={canRefund ? 'Refund part of the payment as a goodwill gesture' : 'Nothing left to refund on this order'}
              style={canRefund ? undefined : { opacity: 0.4, cursor: 'not-allowed' }}>
              <Undo2 className="w-3 h-3" /> Partial goodwill refund
            </button>
            <button className="apple-btn-secondary text-xs px-3 py-1.5" disabled={!canUnassign} onClick={() => { setNotice(''); setAction('unassign'); }}
              title={canUnassign ? 'Take the job from this courier and offer it again' : 'No courier to unassign'}
              style={canUnassign ? undefined : { opacity: 0.4, cursor: 'not-allowed' }}>
              <UserMinus className="w-3 h-3" /> Unassign courier
            </button>
          </div>

          <div className="grid sm:grid-cols-3 gap-4 mb-6">
            <div><h3 className="text-xs uppercase tracking-wide text-gray-400 font-medium mb-1">Customer</h3><Person p={detail.customer} kind="Customer" /></div>
            <div><h3 className="text-xs uppercase tracking-wide text-gray-400 font-medium mb-1">Store</h3><Person p={detail.store} kind="Store" /></div>
            <div><h3 className="text-xs uppercase tracking-wide text-gray-400 font-medium mb-1">Courier</h3><Person p={detail.courier} kind="Courier" /></div>
          </div>

          <Section title="Items">
            {detail.items.length === 0 ? <Missing /> : (
              <table className="w-full text-sm">
                <tbody>
                  {detail.items.map((it, i) => {
                    const product = obj(it.product);
                    const variant = obj(it.variant);
                    const qty = num(it.quantity) ?? 1;
                    const unit = num(it.unitCents) ?? num(it.priceCents) ?? num(it.unitPriceCents);
                    return (
                      <tr key={num(it.id) ?? i} className="border-b border-gray-50 last:border-0">
                        <td className="py-1.5 pr-3">{qty} ×</td>
                        <td className="py-1.5 pr-3">{str(it.name) ?? str(product.name) ?? `Item #${num(it.productId) ?? '?'}`}
                          {(str(variant.label) ?? str(it.variantLabel)) && <span className="text-gray-400"> · {str(variant.label) ?? str(it.variantLabel)}</span>}</td>
                        <td className="py-1.5 text-right whitespace-nowrap">{unit !== null ? euro(unit * qty) : '—'}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </Section>

          <Section title="Delivery">
            <KV k="How" v={str(o.fulfilment) === 'PICKUP' ? 'Reserve & collect at the store' : str(o.scheduledStart) ? `Scheduled ${fiDate(str(o.scheduledStart))} – ${fiDate(str(o.scheduledEnd))}` : 'As soon as possible'} />
            {str(o.deliveryAddress) && <KV k="Address" v={str(o.deliveryAddress)} />}
            {str(o.handoverMethod) && <KV k="Handover" v={str(o.handoverMethod)} />}
            {str(o.deliveryProblemAt) && <KV k="Delivery problem" v={`${str(o.deliveryProblemReason) ?? 'OTHER'}${str(o.deliveryProblemNote) ? ` · ${str(o.deliveryProblemNote)}` : ''}`} />}
            <KV k="Delivery proof" v={detail.proofUrl
              ? <a className="text-blue-600 inline-flex items-center gap-1" href={detail.proofUrl} target="_blank" rel="noreferrer noopener">Open photo (signed link) <ExternalLink className="w-3 h-3" /></a>
              : str(o.handoverMethod) === 'PHOTO' ? 'Photo deleted (kept 30 days) or not in the answer' : 'No photo'} />
          </Section>

          <Section title="Timeline">
            {detail.timeline.length === 0 ? <Missing /> : (
              <ol className="relative border-l border-gray-200 ml-1.5">
                {detail.timeline.map((t, i) => (
                  <li key={`${t.label}${t.at}${i}`} className="ml-4 pb-2">
                    <span className="absolute -left-1.5 w-3 h-3 rounded-full bg-gray-300 mt-1" />
                    <p className="text-sm"><span className="font-medium">{t.label}</span> <span className="text-gray-400">· {fiDate(t.at)}</span></p>
                    {t.note && <p className="text-xs text-gray-500">{t.note}</p>}
                  </li>
                ))}
              </ol>
            )}
          </Section>

          <Section title="Payment and refunds">
            <KV k="Items" v={euro(num(o.subtotalCents))} />
            <KV k="Delivery fee" v={euro(num(o.deliveryFeeCents))} />
            {(num(o.serviceFeeCents) ?? 0) > 0 && <KV k="Service fee" v={euro(num(o.serviceFeeCents))} />}
            {(num(o.smallOrderFeeCents) ?? 0) > 0 && <KV k="Small-order fee" v={euro(num(o.smallOrderFeeCents))} />}
            {(num(o.tipCents) ?? 0) > 0 && <KV k="Tip (to the courier)" v={euro(num(o.tipCents))} />}
            {(num(o.discountCents) ?? 0) > 0 && <KV k="Discount (paid by Malvoya)" v={`− ${euro(num(o.discountCents))}`} />}
            <KV k="Customer paid" v={<span className="font-semibold">{euro(num(o.totalCents))}</span>} />
            <KV k="Paid at" v={fiDate(str(o.paidAt))} />
            <KV k="Refunded so far" v={euro(num(o.refundedCents) ?? 0)} />
            <KV k="Still refundable" v={euro(detail.refundableCents)} />
            <KV k="Commission" v={euro(num(o.commissionCents))} />
            {str(o.stripePaymentIntentId) && <KV k="Stripe payment" v={<code className="text-xs">{str(o.stripePaymentIntentId)}</code>} />}
            {detail.refunds && detail.refunds.length > 0 && (
              <ul className="mt-2 space-y-1">
                {detail.refunds.map((r, i) => (
                  <li key={num(r.id) ?? i} className="text-sm bg-gray-50 rounded-xl px-3 py-2">
                    <span className="font-medium">{euro(num(r.amountCents) ?? num(r.cents) ?? num(r.amount))}</span>
                    <span className="text-gray-400"> · {fiDate(str(r.createdAt) ?? str(r.at))}</span>
                    {(str(r.reason) ?? str(r.source)) && <span className="text-gray-600"> · {str(r.reason) ?? str(r.source)}</span>}
                    {(str(r.status)) && <span className="text-gray-400"> · {str(r.status)}</span>}
                  </li>
                ))}
              </ul>
            )}
          </Section>

          <Section title="Payouts">
            {detail.payouts === null ? <Missing /> : detail.payouts.length === 0 ? <p className="text-sm text-gray-400">No payouts (created on delivery).</p> : (
              <table className="w-full text-sm">
                <tbody>
                  {detail.payouts.map((p, i) => (
                    <tr key={num(p.id) ?? i} className="border-b border-gray-50 last:border-0 align-top">
                      <td className="py-1.5 pr-3">{str(p.party) ?? '—'}</td>
                      <td className="py-1.5 pr-3 font-medium">{euro(num(p.amountCents))}</td>
                      <td className="py-1.5 pr-3"><span className={p.status === 'PAID' ? 'badge-green' : p.status === 'FAILED' ? 'badge-red' : p.status === 'HELD' || p.status === 'FROZEN' ? 'badge-orange' : 'badge-gray'}>{str(p.status) ?? '—'}</span></td>
                      <td className="py-1.5 text-xs text-gray-500">
                        {str(p.paidAt) ? `paid ${fiDate(str(p.paidAt))}` : str(p.releaseAt) ? `release ${fiDate(str(p.releaseAt))}` : ''}
                        {str(p.failureReason) && <span className="block text-red-500">{str(p.failureReason)}</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </Section>

          <Section title="Returns">
            {detail.returns === null ? <Missing /> : detail.returns.length === 0 ? <p className="text-sm text-gray-400">No returns.</p> : (
              <ul className="space-y-2">
                {detail.returns.map((r, i) => (
                  <li key={num(r.id) ?? i} className="text-sm bg-gray-50 rounded-xl px-3 py-2">
                    <p><span className="font-medium">Return #{num(r.id) ?? '?'}</span> · <span className="badge-gray">{str(r.status) ?? '—'}</span> · {str(r.reason) ?? ''}
                      <span className="text-gray-400"> · {fiDate(str(r.createdAt))}</span></p>
                    <p className="text-gray-600">Refund {num(r.refundCents) !== null ? euro(num(r.refundCents)) : `expected ${euro(num(r.expectedRefundCents))}`}</p>
                    {str(r.conditionNote) && <p className="text-xs text-gray-500">Customer: {str(r.conditionNote)}</p>}
                    {str(r.storeNote) && <p className="text-xs text-gray-500">Store: {str(r.storeNote)}</p>}
                  </li>
                ))}
              </ul>
            )}
          </Section>

          <Section title="Card disputes">
            {detail.disputes === null && !str(o.disputedAt) ? <p className="text-sm text-gray-400">None reported.</p>
              : (detail.disputes ?? []).length === 0
                ? <KV k={`Opened ${fiDate(str(o.disputedAt))}`} v={<span className="badge-red">{str(o.disputeStatus) ?? 'open'}</span>} />
                : (
                  <ul className="space-y-1">
                    {(detail.disputes ?? []).map((d, i) => (
                      <li key={num(d.id) ?? str(d.stripeDisputeId) ?? i} className="text-sm bg-red-50 rounded-xl px-3 py-2">
                        <span className="font-medium">{euro(num(d.amountCents) ?? num(d.amount))}</span> · {str(d.status) ?? '—'} · {str(d.reason) ?? ''}
                        <span className="text-gray-400"> · {fiDate(str(d.createdAt) ?? str(d.openedAt))}</span>
                      </li>
                    ))}
                  </ul>
                )}
          </Section>

          <Section title="Chat (customer and courier)">
            {detail.messages === null ? <Missing /> : detail.messages.length === 0 ? <p className="text-sm text-gray-400">No messages (deleted 30 days after the order closed).</p> : (
              <ul className="space-y-1.5">
                {detail.messages.map((m, i) => (
                  <li key={num(m.id) ?? i} className="text-sm bg-gray-50 rounded-xl px-3 py-2">
                    <div className="text-xs text-gray-500 flex gap-2"><span className="font-medium text-gray-700">{str(m.senderRole) ?? str(m.role) ?? '—'}</span><span className="ml-auto">{fiDate(str(m.createdAt))}</span></div>
                    <p className="break-words">{str(m.text) ?? ''}</p>
                  </li>
                ))}
              </ul>
            )}
          </Section>
        </>
      )}

      {detail && action === 'cancel' && (
        <CancelDialog orderId={orderId} totalCents={num(o.totalCents)} paid={paid} onClose={() => setAction(null)}
          onDone={() => done(`Order #${orderId} was cancelled${paid ? ' and the payment refunded' : ''}.`)} />
      )}
      {detail && action === 'refund' && (
        <RefundDialog orderId={orderId} refundableCents={detail.refundableCents ?? 0} onClose={() => setAction(null)}
          onDone={(cents) => done(`${euro(cents)} was refunded to the customer of order #${orderId}.`)} />
      )}
      {detail && action === 'unassign' && (
        <UnassignDialog orderId={orderId} courierName={str(detail.courier?.name) ?? str(obj(detail.courier?.user).name) ?? 'the courier'} onClose={() => setAction(null)}
          onDone={() => done(`The courier was taken off order #${orderId}; the job is offered to couriers again.`)} />
      )}
    </Drawer>
  );
}

function useSubmit() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const run = async (fn: () => Promise<unknown>, fallback: string): Promise<boolean> => {
    setBusy(true);
    setError('');
    try { await fn(); return true; }
    catch (e) { setError(errorText(e, fallback)); return false; }
    finally { setBusy(false); }
  };
  return { busy, error, setError, run };
}

function CancelDialog({ orderId, totalCents, paid, onClose, onDone }: { orderId: number; totalCents: number | null; paid: boolean; onClose: () => void; onDone: () => void }) {
  const [reason, setReason] = useState('');
  const [confirming, setConfirming] = useState(false);
  const { busy, error, setError, run } = useSubmit();

  const review = (e: React.FormEvent) => {
    e.preventDefault();
    if (reason.trim().length < 5) return setError('Write a reason (at least 5 characters). It is shown to the customer and the store and kept in the audit log.');
    setError('');
    setConfirming(true);
  };
  const submit = async () => {
    if (await run(() => api.post(`/admin/orders/${orderId}/cancel`, { reason: reason.trim() }), 'The order could not be cancelled.')) onDone();
  };

  return (
    <Overlay title={`Cancel order #${orderId}?`} onClose={busy ? () => undefined : onClose}>
      {!confirming ? (
        <form onSubmit={review}>
          <p className="text-sm text-gray-600 mb-3">
            The order is cancelled, the stock goes back to the store and {paid ? <>the customer gets everything paid back ({euro(totalCents)})</> : 'the unpaid checkout is released'}.
            The customer and the store are told the reason. The action is recorded in the audit log.
          </p>
          <label className="text-sm block mb-3">
            <span className="block text-gray-500 mb-1">Reason *</span>
            <textarea className="apple-input w-full min-h-24" maxLength={200} value={reason} autoFocus
              placeholder="e.g. “The store cannot fulfil the order; agreed with the customer by phone.”" onChange={(e) => setReason(e.target.value)} />
          </label>
          {error && <div className="mb-3"><ErrorBox>{error}</ErrorBox></div>}
          <div className="flex gap-2 justify-end">
            <button type="button" className="apple-btn-secondary" onClick={onClose}>Back</button>
            <button type="submit" className="apple-btn-danger" disabled={!reason.trim()}>Continue</button>
          </div>
        </form>
      ) : (
        <div>
          <p className="text-sm mb-2">Please confirm: cancel order <b>#{orderId}</b>{paid ? <> and refund <b>{euro(totalCents)}</b> in full</> : ''}.</p>
          <p className="text-sm text-gray-500 bg-gray-50 rounded-xl px-3 py-2 mb-3">“{reason.trim()}”</p>
          <p className="text-xs text-gray-400 mb-3">This cannot be undone.</p>
          {error && <div className="mb-3"><ErrorBox>{error}</ErrorBox></div>}
          <div className="flex gap-2 justify-end">
            <button type="button" className="apple-btn-secondary" disabled={busy} onClick={() => setConfirming(false)}>Back</button>
            <button type="button" className="apple-btn-danger" disabled={busy} onClick={submit}>{busy ? 'Cancelling…' : paid ? 'Yes, cancel and refund' : 'Yes, cancel'}</button>
          </div>
        </div>
      )}
    </Overlay>
  );
}

function RefundDialog({ orderId, refundableCents, onClose, onDone }: { orderId: number; refundableCents: number; onClose: () => void; onDone: (cents: number) => void }) {
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [fromStore, setFromStore] = useState(false);
  const [confirming, setConfirming] = useState<number | null>(null);
  const { busy, error, setError, run } = useSubmit();

  const review = (e: React.FormEvent) => {
    e.preventDefault();
    const cents = parseEuroToCents(amount);
    if (cents === null) return setError('Enter the amount in euros, e.g. 5 or 12,50.');
    if (cents > refundableCents) return setError(`At most ${euro(refundableCents)} can still be refunded on this order.`);
    if (reason.trim().length < 5) return setError('Write a reason (at least 5 characters). It is kept in the audit log.');
    setError('');
    setConfirming(cents);
  };
  const submit = async () => {
    if (confirming === null) return;
    const cents = confirming;
    if (await run(() => api.post(`/admin/orders/${orderId}/refund`, { cents, reason: reason.trim(), fromStore }), 'The refund could not be made.')) onDone(cents);
  };

  return (
    <Overlay title={`Goodwill refund · order #${orderId}`} onClose={busy ? () => undefined : onClose}>
      {confirming === null ? (
        <form onSubmit={review}>
          <p className="text-sm text-gray-600 mb-3">
            Refunds part of the payment to the customer's card through Stripe. The order itself is not changed.
            Still refundable: <b>{euro(refundableCents)}</b>.
          </p>
          <label className="text-sm block mb-3">
            <span className="block text-gray-500 mb-1">Amount (€) *</span>
            <input className="apple-input" inputMode="decimal" value={amount} autoFocus placeholder="e.g. 5,00" onChange={(e) => setAmount(e.target.value)} />
          </label>
          <label className="text-sm block mb-3">
            <span className="block text-gray-500 mb-1">Reason *</span>
            <textarea className="apple-input w-full min-h-20" maxLength={200} value={reason}
              placeholder="e.g. “Delivery 40 minutes late; goodwill.”" onChange={(e) => setReason(e.target.value)} />
          </label>
          <label className="text-sm flex items-start gap-2 mb-3">
            <input type="checkbox" className="mt-1" checked={fromStore} onChange={(e) => setFromStore(e.target.checked)} />
            <span>Take it from the store's payout<span className="block text-xs text-gray-400">Only when the store caused the problem. Unticked, Malvoya pays the refund and the store payout stays the same.</span></span>
          </label>
          {error && <div className="mb-3"><ErrorBox>{error}</ErrorBox></div>}
          <div className="flex gap-2 justify-end">
            <button type="button" className="apple-btn-secondary" onClick={onClose}>Back</button>
            <button type="submit" className="apple-btn-primary" disabled={!amount.trim() || !reason.trim()}>Continue</button>
          </div>
        </form>
      ) : (
        <div>
          <p className="text-sm mb-2">Please confirm: refund <b>{euro(confirming)}</b> to the customer of order <b>#{orderId}</b>, paid by <b>{fromStore ? "the store (taken from its payout)" : 'Malvoya'}</b>.</p>
          <p className="text-sm text-gray-500 bg-gray-50 rounded-xl px-3 py-2 mb-3">“{reason.trim()}”</p>
          <p className="text-xs text-gray-400 mb-3">Card refunds cannot be taken back.</p>
          {error && <div className="mb-3"><ErrorBox>{error}</ErrorBox></div>}
          <div className="flex gap-2 justify-end">
            <button type="button" className="apple-btn-secondary" disabled={busy} onClick={() => setConfirming(null)}>Back</button>
            <button type="button" className="apple-btn-danger" disabled={busy} onClick={submit}>{busy ? 'Refunding…' : `Yes, refund ${euro(confirming)}`}</button>
          </div>
        </div>
      )}
    </Overlay>
  );
}

function UnassignDialog({ orderId, courierName, onClose, onDone }: { orderId: number; courierName: string; onClose: () => void; onDone: () => void }) {
  const { busy, error, run } = useSubmit();
  const submit = async () => {
    if (await run(() => api.post(`/admin/orders/${orderId}/unassign-courier`), 'The courier could not be unassigned.')) onDone();
  };
  return (
    <Overlay title={`Unassign the courier of order #${orderId}?`} onClose={busy ? () => undefined : onClose}>
      <p className="text-sm text-gray-600 mb-3">
        <b>{courierName}</b> loses the job and the order goes back to being offered to nearby couriers. Use it when the courier cannot
        continue (for example after an incident). The action is recorded in the audit log.
      </p>
      {error && <div className="mb-3"><ErrorBox>{error}</ErrorBox></div>}
      <div className="flex gap-2 justify-end">
        <button type="button" className="apple-btn-secondary" disabled={busy} onClick={onClose}>Back</button>
        <button type="button" className="apple-btn-danger" disabled={busy} onClick={submit}>{busy ? 'Unassigning…' : 'Yes, unassign and offer again'}</button>
      </div>
    </Overlay>
  );
}

