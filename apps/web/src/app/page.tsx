import Link from "next/link";

export default function Home() {
  return (
    <main className="min-h-screen p-8">
      <div className="max-w-2xl mx-auto space-y-6">
        <h1 className="text-3xl font-bold">Finance AI (MVP)</h1>
        <p className="text-slate-600">
          CSV importieren, Kategorien sehen, später Insights & Dashboards.
        </p>
        <div className="flex gap-4">
          <Link className="px-4 py-2 rounded bg-black text-white" href="/import">
            CSV importieren
          </Link>
          <Link className="px-4 py-2 rounded border" href="/transactions">
            Transaktionen ansehen
          </Link>
          <Link className="px-4 py-2 rounded border" href="/dashboard">
            Dashboard ansehen
          </Link>
        </div>
      </div>
    </main>
  );
}
