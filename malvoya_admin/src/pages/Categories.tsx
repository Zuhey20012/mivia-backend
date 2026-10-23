import { useEffect, useState } from 'react';
import Layout from '../components/Layout';
import api from '../utils/api';

type Cat = {
  id: number; slug: string; parentId: number | null; nameEn: string; nameFi: string; icon: string; tileColor: string;
  sort: number; template: string | null; collection: boolean; active: boolean; products: number; visibleProducts: number;
};

const apiError = (err: unknown, fallback: string) =>
  (err as { response?: { data?: { error?: string } } })?.response?.data?.error ?? fallback;

/**
 * The category tree (seeded from the code; slugs and templates are fixed). Admins rename, reorder and hide nodes.
 * Every change is written to the audit log.
 */
export default function Categories() {
  const [cats, setCats] = useState<Cat[]>([]);
  const [uncategorised, setUncategorised] = useState({ products: 0, visibleProducts: 0 });
  const [error, setError] = useState<string | null>(null);

  async function load() {
    try {
      const r = await api.get('/admin/categories');
      setCats(r.data.categories);
      setUncategorised(r.data.uncategorised);
      setError(null);
    } catch {
      setError('Could not load categories.');
    }
  }
  useEffect(() => { load(); }, []);

  async function save(c: Cat, data: Partial<Pick<Cat, 'nameEn' | 'nameFi' | 'sort' | 'active'>>) {
    try { await api.patch(`/admin/categories/${c.id}`, data); await load(); }
    catch (err) { alert(apiError(err, 'Could not save the change')); }
  }

  function rename(c: Cat) {
    const en = window.prompt('English name', c.nameEn);
    if (en === null) return;
    const fi = window.prompt('Finnish name', c.nameFi);
    if (fi === null) return;
    save(c, { nameEn: en.trim(), nameFi: fi.trim() });
  }

  function move(c: Cat, dir: -1 | 1) {
    const siblings = cats.filter((x) => x.parentId === c.parentId).sort((a, b) => a.sort - b.sort);
    const i = siblings.findIndex((x) => x.id === c.id);
    const other = siblings[i + dir];
    if (!other) return;
    // Swap the two positions
    Promise.all([api.patch(`/admin/categories/${c.id}`, { sort: other.sort }), api.patch(`/admin/categories/${other.id}`, { sort: c.sort })])
      .then(load).catch((err) => alert(apiError(err, 'Could not reorder')));
  }

  const tops = cats.filter((c) => c.parentId === null).sort((a, b) => a.sort - b.sort);
  const row = (c: Cat, child: boolean) => (
    <tr key={c.id} className="table-row">
      <td className={`px-6 py-3 ${child ? 'pl-12' : 'font-semibold'}`}>
        <p className={c.active ? '' : 'text-gray-400 line-through'}>{c.nameEn} / {c.nameFi}</p>
        <p className="text-xs text-gray-400 font-mono">{c.slug}</p>
      </td>
      <td className="px-6 py-3 text-xs text-gray-500">{c.collection ? 'collection (saved filter)' : c.template ?? '—'}</td>
      <td className="px-6 py-3 text-xs text-gray-500">{c.icon} · {c.tileColor}</td>
      <td className="px-6 py-3">{c.visibleProducts} <span className="text-xs text-gray-400">/ {c.products}</span></td>
      <td className="px-6 py-3"><span className={c.active ? 'badge-green' : 'badge-gray'}>{c.active ? 'shown' : 'hidden'}</span></td>
      <td className="px-6 py-3 text-right whitespace-nowrap">
        <button className="text-xs text-gray-500 mr-3" onClick={() => move(c, -1)}>↑</button>
        <button className="text-xs text-gray-500 mr-3" onClick={() => move(c, 1)}>↓</button>
        <button className="text-xs text-blue-600 mr-3" onClick={() => rename(c)}>Rename</button>
        <button className="text-xs text-blue-600" onClick={() => save(c, { active: !c.active })}>{c.active ? 'Hide' : 'Show'}</button>
      </td>
    </tr>
  );

  return (
    <Layout>
      <div className="mb-8">
        <h1 className="text-2xl font-semibold tracking-tight">Categories</h1>
        <p className="text-gray-400 text-sm mt-1">
          The shopping categories of the apps. Counts are visible products / all products (drafts included). Slugs and attribute
          templates come from the code; hidden categories disappear from Home and the store editor. {uncategorised.products > 0 &&
          `${uncategorised.products} product(s) have no category yet (${uncategorised.visibleProducts} visible).`}
        </p>
      </div>
      {error && <p className="text-red-500 text-sm mb-4">{error}</p>}
      <div className="apple-card p-0 overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-100">
              {['Category', 'Template', 'Icon · tile', 'Products', 'Status', ''].map((h) => <th key={h} className="text-left px-6 py-4 text-xs font-medium text-gray-400 uppercase tracking-wider">{h}</th>)}
            </tr>
          </thead>
          <tbody>
            {tops.flatMap((t) => [row(t, false), ...cats.filter((c) => c.parentId === t.id).sort((a, b) => a.sort - b.sort).map((c) => row(c, true))])}
          </tbody>
        </table>
      </div>
    </Layout>
  );
}
