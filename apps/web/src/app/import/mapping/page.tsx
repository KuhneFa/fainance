"use client";

import { useEffect, useState } from "react";
import { importCsv, previewCsv, type PreviewResponse } from "@/lib/api";
import { base64ToFile, loadLastImport } from "@/lib/session";
import Link from "next/link";

export default function MappingPage() {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<PreviewResponse | null>(null);
  const [dateCol, setDateCol] = useState<string>("");
  const [amountCol, setAmountCol] = useState<string>("");
  const [descCol, setDescCol] = useState<string>("");

  const [err, setErr] = useState<string | null>(null);
  const [result, setResult] = useState<any>(null);

  useEffect(() => {
    (async () => {
      if (!file) return;
      setErr(null);
      try {
        const p = await previewCsv(file);
        setPreview(p);
        setDateCol(p.suggested_mapping.date ?? "");
        setAmountCol(p.suggested_mapping.amount ?? "");
        setDescCol(p.suggested_mapping.description ?? "");
      } catch (e: any) {
        setErr(String(e?.message ?? e));
      }
    })();
  }, [file]);

  useEffect(() => {
  if (file) return;
  const stored = loadLastImport();
  if (!stored) return;

  const restoredFile = base64ToFile(stored.base64, stored.filename, stored.mime);
  setFile(restoredFile);
  setPreview(stored.preview);
  setDateCol(stored.preview?.suggested_mapping?.date ?? "");
  setAmountCol(stored.preview?.suggested_mapping?.amount ?? "");
  setDescCol(stored.preview?.suggested_mapping?.description ?? "");
  }, []);

  async function onImport() {
    setErr(null);
    setResult(null);
    if (!file) return;
    try {
      const mapping = {
        date_col: dateCol,
        amount_col: amountCol,
        description_col: descCol,
        currency_col: null,
        merchant_col: null,
      };
      const r = await importCsv(file, mapping);
      setResult(r);
    } catch (e: any) {
      setErr(String(e?.message ?? e));
    }
  }

  const cols = preview?.columns ?? [];

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-4xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold">Mapping</h1>
          <Link className="underline" href="/import">← Zurück</Link>
        </div>

        <div className="p-4 border rounded space-y-3">
          <input type="file" accept=".csv,text/csv" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          {!file && <p className="text-slate-600">Wähle die gleiche CSV nochmal aus.</p>}
        </div>

        {preview && (
          <div className="p-4 border rounded space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <label className="space-y-1">
                <div className="text-sm font-medium">Datum-Spalte</div>
                <select className="w-full border rounded p-2" value={dateCol} onChange={(e) => setDateCol(e.target.value)}>
                  <option value="">— wählen —</option>
                  {cols.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
              </label>

              <label className="space-y-1">
                <div className="text-sm font-medium">Betrag-Spalte</div>
                <select className="w-full border rounded p-2" value={amountCol} onChange={(e) => setAmountCol(e.target.value)}>
                  <option value="">— wählen —</option>
                  {cols.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
              </label>

              <label className="space-y-1">
                <div className="text-sm font-medium">Beschreibung-Spalte</div>
                <select className="w-full border rounded p-2" value={descCol} onChange={(e) => setDescCol(e.target.value)}>
                  <option value="">— wählen —</option>
                  {cols.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
              </label>
            </div>

            <button
              className="px-4 py-2 rounded bg-black text-white disabled:opacity-50"
              disabled={!dateCol || !amountCol || !descCol}
              onClick={onImport}
            >
              Import starten
            </button>

            {err && <div className="text-red-600">{err}</div>}
            {result && (
              <div className="p-3 rounded bg-slate-50 border">
                <pre className="text-sm overflow-auto">{JSON.stringify(result, null, 2)}</pre>
                <Link className="underline" href="/transactions">→ Zu Transaktionen</Link>
              </div>
            )}
          </div>
        )}
      </div>
    </main>
  );
}
