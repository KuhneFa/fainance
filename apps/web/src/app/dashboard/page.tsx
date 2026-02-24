"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend, LineChart, Line, CartesianGrid } from "recharts";
import { getSummary, type SummaryResponse } from "@/lib/api";
import { getTimeseries, type TimeseriesResponse } from "@/lib/api";
import { ComposedChart } from "recharts";


function formatEUR(cents: number) {
  return new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" }).format(cents / 100);
}

export default function DashboardPage() {
  const [fromDate, setFromDate] = useState("2026-01-01"); // MVP default
  const [toDate, setToDate] = useState("2026-01-31");
  const [data, setData] = useState<SummaryResponse | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [series, setSeries] = useState<TimeseriesResponse | null>(null);
  const [interval, setInterval] = useState<"day" | "week" | "month">("week");


    async function load() {
      setErr(null);
      try {
        const [summaryRes, seriesRes] = await Promise.all([
          getSummary({ from_date: fromDate || undefined, to_date: toDate || undefined }),
          getTimeseries({ from_date: fromDate || undefined, to_date: toDate || undefined, interval }),
        ]);
        setData(summaryRes);
        setSeries(seriesRes);
      } catch (e: any) {
        setErr(String(e?.message ?? e));
      }
    }


  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fromDate, toDate, interval]);

  const chartData = useMemo(() => {
    return (data?.by_category ?? []).map((x) => ({
      category: x.category,
      eur: x.expense_cents / 100,
    }));
  }, [data]);
  const lineData = useMemo(() => {
  return (series?.points ?? []).map((p) => ({
    period: p.period,
    income: p.income_cents / 100,
    expense: p.expense_cents / 100,
    net: p.net_cents / 100,
  }));
  }, [series]);


  return (
    <main className="min-h-screen p-8">
      <div className="max-w-6xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold">Dashboard</h1>
          <div className="flex gap-3">
            <Link className="underline" href="/transactions">Transaktionen</Link>
            <Link className="underline" href="/import">CSV importieren</Link>
            <Link className="underline" href="/">Home</Link>
          </div>
        </div>

        <div className="p-4 border rounded flex flex-col md:flex-row gap-3 md:items-center">
          <input type="date" className="border rounded p-2" value={fromDate} onChange={(e) => setFromDate(e.target.value)} />
          <input type="date" className="border rounded p-2" value={toDate} onChange={(e) => setToDate(e.target.value)} />
          <button className="px-4 py-2 rounded bg-black text-white" onClick={load}>Aktualisieren</button>
        </div>

        {err && <div className="text-red-600">{err}</div>}

        {data && (
          <>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="p-4 border rounded">
                <div className="text-sm text-slate-600">Einnahmen</div>
                <div className="text-2xl font-bold">{formatEUR(data.income_cents)}</div>
              </div>
              <div className="p-4 border rounded">
                <div className="text-sm text-slate-600">Ausgaben</div>
                <div className="text-2xl font-bold">{formatEUR(data.expense_cents)}</div>
              </div>
              <div className="p-4 border rounded">
                <div className="text-sm text-slate-600">Netto</div>
                <div className="text-2xl font-bold">{formatEUR(data.net_cents)}</div>
              </div>
            </div>

        {series && (
            <div className="p-4 border rounded space-y-3">
              <div className="flex items-center justify-between">
                <select className="border rounded p-2" value={interval} onChange={(e) => setInterval(e.target.value as any)}>
                  <option value="day">Täglich</option>
                  <option value="week">Wöchentlich</option>
                  <option value="month">Monatlich</option>
                </select>
                <h2 className="text-lg font-semibold">Historie</h2>
                <div className="text-sm text-slate-600">
                  {fromDate} – {toDate}
                </div>
              </div>

              <div className="h-80">
                <ResponsiveContainer width="100%" height="100%">
                  <ComposedChart data={lineData} margin={{ left: 10, right: 10, top: 10, bottom: 10 }}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="period" interval="preserveStartEnd" minTickGap={18} />
                    <YAxis />
                    <Tooltip formatter={(v: any) => `${Number(v).toFixed(2)} €`} />

                    {/* Ausgaben als Balken */}
                    <Bar dataKey="expense" />

                    {/* Netto als Linie */}
                    <Line type="linear" dataKey="net" dot={false} />
                  </ComposedChart>
                </ResponsiveContainer>
              </div>
            <p className="text-sm text-slate-600">
              Tipp: Für eine echte Kurve importiere CSVs über mehrere Monate. Aktuell gibt es {series.points.length} Datenpunkt(e).
            </p>
          </div>
        )}

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="p-4 border rounded space-y-3">
              <h2 className="text-lg font-semibold">Ausgaben pro Kategorie (Balken)</h2>
              <div className="h-80">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={chartData}>
                    <XAxis
                        dataKey="category"
                        interval={0}
                        tickMargin={14}
                        height={90}
                        angle={-25}
                        textAnchor="end"
                    />
                    <YAxis />
                    <Tooltip formatter={(v: any) => `${v} €`} />
                    <Bar dataKey="eur" />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
            <div className="p-4 border rounded space-y-3">
              <h2 className="text-lg font-semibold">Anteile (Kuchendiagramm)</h2>
              <div className="h-80">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                      <Pie
                        data={chartData}
                        dataKey="eur"
                        nameKey="category"
                        outerRadius={120}
                        label={false}
                        labelLine={false}
                      />
                      <Tooltip formatter={(v: any) => `${v} €`} />
                      <Legend />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            </div>
          </div>
          </>
        )}
      </div>
    </main>
  );
}
