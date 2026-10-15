import { useState } from 'react';

/**
 * A small hand-drawn SVG chart of one daily series (no chart library): bars for amounts, a line for counts.
 * One series per chart, so the title names it and no legend is needed. Hovering a day shows its value.
 */
type Point = { date: string; value: number };

const INK = '#1D1D1F';
const MUTED = '#8E8E93';
const GRID = '#EEEEF0';
const SERIES = '#0071E3';
const NEGATIVE = '#B45309';

function niceMax(v: number) {
  if (v <= 0) return 1;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  const m = v / p;
  return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * p;
}

const shortDate = (d: string) => `${Number(d.slice(8, 10))}.${Number(d.slice(5, 7))}.`;

export default function DailyChart({ title, points, kind, format, note }: {
  title: string; points: Point[]; kind: 'bar' | 'line'; format: (v: number) => string; note?: string;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const W = 640, H = 200, L = 52, R = 12, T = 12, B = 26;
  const iw = W - L - R, ih = H - T - B;
  const max = niceMax(Math.max(0, ...points.map((p) => p.value)));
  const min = Math.min(0, ...points.map((p) => p.value));
  const lo = min < 0 ? -niceMax(-min) : 0;
  const y = (v: number) => T + ih - ((v - lo) / (max - lo)) * ih;
  const step = points.length ? iw / points.length : iw;
  const x = (i: number) => L + step * i + step / 2;
  const ticks = [lo, lo + (max - lo) / 2, max];
  const labelEvery = Math.max(1, Math.ceil(points.length / 7));
  const h = hover !== null ? points[hover] : null;
  const total = points.reduce((t, p) => t + p.value, 0);

  return (
    <div className="apple-card" style={{ position: 'relative' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: '0.5rem', gap: '1rem' }}>
        <h3 style={{ fontWeight: 600, fontSize: '0.9375rem' }}>{title}</h3>
        <span style={{ fontSize: '0.75rem', color: MUTED }}>
          {h ? `${shortDate(h.date)} · ${format(h.value)}` : `Total ${format(total)}`}
        </span>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label={`${title}, ${points.length} days, total ${format(total)}`}
        onMouseLeave={() => setHover(null)} style={{ display: 'block' }}>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={L} x2={W - R} y1={y(t)} y2={y(t)} stroke={GRID} strokeWidth={1} />
            <text x={L - 8} y={y(t) + 4} textAnchor="end" fontSize={10} fill={MUTED}>{format(t)}</text>
          </g>
        ))}
        {points.map((p, i) => (i % labelEvery === 0 || i === points.length - 1) && (
          <text key={p.date} x={x(i)} y={H - 8} textAnchor="middle" fontSize={10} fill={MUTED}>{shortDate(p.date)}</text>
        ))}
        {kind === 'bar' && points.map((p, i) => {
          const bw = Math.max(2, step - 2); // 2 px gap between bars
          const top = y(Math.max(0, p.value)), bottom = y(Math.min(0, p.value));
          const hgt = Math.max(p.value === 0 ? 0 : 1, bottom - top);
          const r = Math.min(4, bw / 2, hgt);
          return (
            <path key={p.date} fill={p.value < 0 ? NEGATIVE : SERIES} opacity={hover === null || hover === i ? 1 : 0.45}
              d={p.value >= 0
                ? `M${x(i) - bw / 2},${bottom} V${top + r} Q${x(i) - bw / 2},${top} ${x(i) - bw / 2 + r},${top} H${x(i) + bw / 2 - r} Q${x(i) + bw / 2},${top} ${x(i) + bw / 2},${top + r} V${bottom} Z`
                : `M${x(i) - bw / 2},${top} V${bottom - r} Q${x(i) - bw / 2},${bottom} ${x(i) - bw / 2 + r},${bottom} H${x(i) + bw / 2 - r} Q${x(i) + bw / 2},${bottom} ${x(i) + bw / 2},${bottom - r} V${top} Z`} />
          );
        })}
        {kind === 'line' && points.length > 0 && (
          <>
            <polyline fill="none" stroke={SERIES} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round"
              points={points.map((p, i) => `${x(i)},${y(p.value)}`).join(' ')} />
            {h && <line x1={x(hover!)} x2={x(hover!)} y1={T} y2={T + ih} stroke={MUTED} strokeWidth={1} strokeDasharray="3 3" />}
            {h && <circle cx={x(hover!)} cy={y(h.value)} r={4} fill={SERIES} stroke="#fff" strokeWidth={2} />}
          </>
        )}
        {/* Hit targets: a full-height column per day, wider than the mark */}
        {points.map((p, i) => (
          <rect key={`hit-${p.date}`} x={L + step * i} y={T} width={step} height={ih} fill="transparent"
            onMouseEnter={() => setHover(i)}>
            <title>{`${shortDate(p.date)}: ${format(p.value)}`}</title>
          </rect>
        ))}
        <line x1={L} x2={W - R} y1={y(0)} y2={y(0)} stroke={INK} strokeOpacity={0.25} strokeWidth={1} />
      </svg>
      {note && <p style={{ fontSize: '0.75rem', color: MUTED, marginTop: '0.5rem', lineHeight: 1.45 }}>{note}</p>}
    </div>
  );
}
