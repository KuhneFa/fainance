const KEY = "financeai:last_import";

export type StoredImport = {
  filename: string;
  mime: string;
  base64: string;     // file content
  preview: any;       // PreviewResponse
};

export async function fileToBase64(file: File): Promise<string> {
  const buf = await file.arrayBuffer();
  const bytes = new Uint8Array(buf);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

export function base64ToFile(base64: string, filename: string, mime: string): File {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new File([bytes], filename, { type: mime });
}

export function saveLastImport(data: StoredImport) {
  sessionStorage.setItem(KEY, JSON.stringify(data));
}

export function loadLastImport(): StoredImport | null {
  const raw = sessionStorage.getItem(KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function clearLastImport() {
  sessionStorage.removeItem(KEY);
}
