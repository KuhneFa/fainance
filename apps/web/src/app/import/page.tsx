"use client";

import { useState } from "react";
import { previewCsv, type PreviewResponse } from "@/lib/api";
import { fileToBase64, saveLastImport, clearLastImport } from "@/lib/session";
import Link from "next/link";

export default function ImportPage() {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<PreviewResponse | null>(null);
  const [err, setErr] = useState<string | null>(null);

  async function onPreview() {
    setErr(null);
    if (!file) return;
    try {
      const p = await previewCsv(file);
      setPreview(p);
      const base64 = await fileToBase64(file);
      saveLastImport({
        filename: file.name,
        mime: file.type || "text/csv",
        base64,
        preview: p,
      });
    } catch (e: any) {
      setErr(String(e?.message ?? e));
    }
  }

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-4xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold">CSV Import</h1>
          <Link className="underline" href="/">Home</Link>
        </div>

        <div className="p-4 border rounded space-y-3">
          <input
            type="file"
            accept=".csv,text/csv"
            onChange={(e) => {
                clearLastImport();
                setPreview(null);
                setErr(null);
                setFile(e.target.files?.[0] ?? null);
            }}
          />
          <button
            className="px-4 py-2 rounded bg-black text-white disabled:opacity-50"
            disabled={!file}
            onClick={onPreview}
          >
            Preview
          </button>
          {err && <div className="text-red-600">{err}</div>}
        </div>

        {preview && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="text-slate-600">
                Delimiter: <b>{preview.detected.delimiter}</b> · Header:{" "}
                <b>{String(preview.detected.has_header)}</b>
              </div>
              <Link
                className="px-4 py-2 rounded border"
                href={{
                  pathname: "/import/mapping",
                  query: { hasPreview: "1" },
                }}
              >
                Weiter zum Mapping →
              </Link>
            </div>

            <div className="border rounded overflow-auto">
              <table className="min-w-full text-sm">
                <thead className="bg-slate-50">
                  <tr>
                    {preview.columns.map((c) => (
                      <th key={c} className="text-left p-2 border-b">{c}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {preview.rows.map((r, idx) => (
                    <tr key={idx} className="border-b">
                      {preview.columns.map((c) => (
                        <td key={c} className="p-2">{r[c] ?? ""}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* MVP: wir speichern preview+file nicht global, deswegen Hinweis */}
            <p className="text-slate-600">
              Tipp: Die Mapping-Seite übernimmt automatisch die zuletzt ge-previewte Datei (solange der Tab offen ist).
            </p>
          </div>
        )}
      </div>
    </main>
  );
}
