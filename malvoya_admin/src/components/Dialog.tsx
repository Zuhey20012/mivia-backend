import type { ReactNode } from 'react';
import { X } from 'lucide-react';

/** Centred modal (same look as the Live page dialogs). */
export function Overlay({ title, onClose, children, wide = false }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  return (
    <div className="fixed inset-0 z-[60] bg-black/30 flex items-center justify-center p-4" role="dialog" aria-modal="true" aria-label={title}
      onClick={onClose}>
      <div className={`apple-card w-full ${wide ? 'max-w-2xl' : 'max-w-lg'} max-h-[85vh] flex flex-col`} onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start justify-between gap-4 mb-3">
          <h2 className="font-semibold">{title}</h2>
          <button className="text-gray-400 hover:text-gray-600" onClick={onClose} aria-label="Close"><X className="w-5 h-5" /></button>
        </div>
        <div className="overflow-y-auto">{children}</div>
      </div>
    </div>
  );
}

/** Panel sliding in from the right, for the details of one row. */
export function Drawer({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  return (
    <div className="fixed inset-0 z-50 bg-black/20 flex justify-end" role="dialog" aria-modal="true" aria-label={title} onClick={onClose}>
      <div className="bg-white w-full max-w-2xl h-full overflow-y-auto shadow-2xl p-6" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start justify-between gap-4 mb-4 sticky top-0 bg-white pb-3 border-b border-gray-100 -mx-6 px-6 -mt-6 pt-6 z-10">
          <h2 className="font-semibold text-lg">{title}</h2>
          <button className="text-gray-400 hover:text-gray-600" onClick={onClose} aria-label="Close"><X className="w-5 h-5" /></button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function ErrorBox({ children }: { children: ReactNode }) {
  return <div className="bg-red-50 text-red-600 text-sm rounded-xl px-4 py-3">{children}</div>;
}

export function NoticeBox({ children }: { children: ReactNode }) {
  return <div className="bg-green-50 text-green-700 text-sm rounded-xl px-4 py-3">{children}</div>;
}
