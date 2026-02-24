"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { listTransactions, patchTransactionCategory, type Transaction } from "@/lib/api";
import { CATEGORIES } from "@/lib/categories";

function formatEUR(amountCents: number) {
  const v = amountCents / 100;
  return new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" }).format(v);
}

export default function TransactionsPage() {
  const [items, setItems] = useState<Transaction[]>([]);
  const [q, setQ] = useState("");
  const [category, setCategory] = useState<string>("");
  const [err, setErr] = useState<string | null>(null);
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");

  async function load() {
    setErr(null);
    try {
      const res = await listTransactions({ page: 1, page_size: 50, q: q || undefined, category: category || undefined, from_date: fromDate || undefined, to_date: toDate || undefined });
      setItems(res.items);
    } catch (e: any) {
      setErr(String(e?.message ?? e));
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function onChangeCategory(id: string, newCat: string) {
    // optimistic UI
    setItems((prev) => prev.map((t) => (t.id === id ? { ...t, category: newCat } : t)));
    try {
      await patchTransactionCategory(id, newCat);
    } catch (e: any) {
      setErr(String(e?.message ?? e));
      // reload to be safe
      await load();
    }
  }

  return (
    <main className="min-h-screen p-8">
      <div className="max-w-6xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold">Transaktionen</h1>
          <div className="flex gap-3">
            <Link className="underline" href="/import">CSV importieren</Link>
            <Link className="underline" href="/">Home</Link>
            <Link className="underline" href="/dashboard">Dashboard</Link>
          </div>
        </div>

        <div className="p-4 border rounded flex flex-col md:flex-row gap-3 md:items-center">
          <input className="border rounded p-2 flex-1" placeholder="Suche (Merchant/Description)" value={q} onChange={(e) => setQ(e.target.value)} />
          <input
                type="date"
                className="border rounded p-2"
                value={fromDate}
                onChange={(e) => setFromDate(e.target.value)}
          />
          <input
                type="date"
                className="border rounded p-2"
                value={toDate}
                onChange={(e) => setToDate(e.target.value)}
          />
          <select className="border rounded p-2" value={category} onChange={(e) => setCategory(e.target.value)}>
            <option value="">Alle Kategorien</option>
            {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
          <button className="px-4 py-2 rounded bg-black text-white" onClick={load}>Filtern</button>
        </div>

        {err && <div className="text-red-600">{err}</div>}

        <div className="border rounded overflow-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50">
              <tr>
                <th className="text-left p-2 border-b">Datum</th>
                <th className="text-left p-2 border-b">Beschreibung</th>
                <th className="text-left p-2 border-b">Merchant</th>
                <th className="text-right p-2 border-b">Betrag</th>
                <th className="text-left p-2 border-b">Kategorie</th>
              </tr>
            </thead>
            <tbody>
              {items.map((t) => (
                <tr key={t.id} className="border-b">
                  <td className="p-2 whitespace-nowrap">{t.booking_date}</td>
                  <td className="p-2">{t.description}</td>
                  <td className="p-2">{t.merchant ?? ""}</td>
                  <td className="p-2 text-right whitespace-nowrap">{formatEUR(t.amount_cents)}</td>
                  <td className="p-2">
                    <select
                      className="border rounded p-1"
                      value={t.category}
                      onChange={(e) => onChangeCategory(t.id, e.target.value)}
                    >
                      {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
                    </select>
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr>
                  <td className="p-4 text-slate-600" colSpan={5}>Keine Daten. Importiere zuerst eine CSV.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </main>
  );
}
