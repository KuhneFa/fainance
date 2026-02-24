const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? "http://localhost:8000";

export type PreviewResponse = {
  detected: { delimiter: string; has_header: boolean; encoding: string };
  columns: string[];
  rows: Record<string, string>[];
  suggested_mapping: { date: string | null; amount: string | null; description: string | null };
};

export async function previewCsv(file: File): Promise<PreviewResponse> {
  const fd = new FormData();
  fd.append("file", file);

  const res = await fetch(`${API_BASE}/v1/import/preview`, { method: "POST", body: fd });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

export async function importCsv(file: File, mapping: any): Promise<any> {
  const fd = new FormData();
  fd.append("file", file);
  fd.append("mapping", JSON.stringify(mapping));

  const res = await fetch(`${API_BASE}/v1/import/csv`, { method: "POST", body: fd });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

export type Transaction = {
  id: string;
  booking_date: string;
  amount_cents: number;
  currency: string;
  description: string;
  merchant: string | null;
  category: string;
};

export async function listTransactions(params?: {
  page?: number;
  page_size?: number;
  category?: string;
  q?: string;
  from_date?: string;
  to_date?: string;
}): Promise<{ items: Transaction[]; page: number; page_size: number; total: number }> {
  const usp = new URLSearchParams();
  if (params?.page) usp.set("page", String(params.page));
  if (params?.page_size) usp.set("page_size", String(params.page_size));
  if (params?.category) usp.set("category", params.category);
  if (params?.q) usp.set("q", params.q);
  if (params?.from_date) usp.set("from_date", params.from_date);
  if (params?.to_date) usp.set("to_date", params.to_date);

  const res = await fetch(`${API_BASE}/v1/transactions?${usp.toString()}`, { cache: "no-store" });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

export async function patchTransactionCategory(id: string, category: string): Promise<Transaction> {
  const res = await fetch(`${API_BASE}/v1/transactions/${id}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ category }),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

export type SummaryResponse = {
  from_date: string | null;
  to_date: string | null;
  income_cents: number;
  expense_cents: number;
  net_cents: number;
  by_category: { category: string; expense_cents: number }[];
};

export async function getSummary(params?: { from_date?: string; to_date?: string }): Promise<SummaryResponse> {
  const usp = new URLSearchParams();
  if (params?.from_date) usp.set("from_date", params.from_date);
  if (params?.to_date) usp.set("to_date", params.to_date);

  const res = await fetch(`${API_BASE}/v1/analytics/summary?${usp.toString()}`, { cache: "no-store" });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

export type TimeseriesPoint = {
  period: string; // YYYY-MM
  income_cents: number;
  expense_cents: number; // positive
  net_cents: number;
};

export type TimeseriesResponse = {
  from_date: string | null;
  to_date: string | null;
  points: TimeseriesPoint[];
};

export async function getTimeseries(params?: { from_date?: string; to_date?: string; interval?: "day" | "week" | "month" }): Promise<TimeseriesResponse> {
  const usp = new URLSearchParams();
  if (params?.from_date) usp.set("from_date", params.from_date);
  if (params?.to_date) usp.set("to_date", params.to_date);
  if (params?.interval) usp.set("interval", params.interval);

  const res = await fetch(`${API_BASE}/v1/analytics/timeseries?${usp.toString()}`, { cache: "no-store" });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

export async function getRange(): Promise<{ min_date: string | null; max_date: string | null }> {
  const res = await fetch(`${API_BASE}/v1/analytics/range`, { cache: "no-store" });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

