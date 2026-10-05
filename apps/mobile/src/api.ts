import { Platform } from "react-native";

export let API_URL = (
  process.env.EXPO_PUBLIC_API_URL ||
  (Platform.OS === "android" ? "http://127.0.0.1:8787" : "http://localhost:8787")
).replace(/\/$/, "");

export function setApiUrl(url: string) {
  if (!url) return;
  let formatted = url.trim().replace(/\/$/, "");
  if (!/^https?:\/\//i.test(formatted)) {
    formatted = `http://${formatted}`;
  }
  API_URL = formatted;
}

async function fetchApi(url: string, init?: RequestInit): Promise<Response> {
  try {
    return await fetch(url, init);
  } catch (err) {
    if (Platform.OS === "android" && !url.includes("127.0.0.1")) {
      const fallback = url.replace(/^http:\/\/[^/]+/, "http://127.0.0.1:8787");
      try {
        const res = await fetch(fallback, init);
        API_URL = "http://127.0.0.1:8787";
        return res;
      } catch {
        throw err;
      }
    }
    throw err;
  }
}

export class MuseApi {
  constructor(readonly token: string) {}
  async request<T>(path: string, body?: unknown, method?: string): Promise<T> {
    const response = await fetchApi(this.url(path), {
      method: method ?? (body === undefined ? "GET" : "POST"),
      headers: {
        Authorization: `Bearer ${this.token}`,
        ...(body === undefined || body instanceof FormData
          ? {}
          : { "Content-Type": "application/json" }),
      },
      body: body === undefined ? undefined : body instanceof FormData ? body : JSON.stringify(body),
    });
    const payload = await response.json();
    if (!response.ok)
      throw new Error(
        typeof payload.error === "string" ? payload.error : `Request failed (${response.status})`,
      );
    return payload;
  }
  url(path: string) {
    return path.startsWith("http") ? path : `${API_URL}${path}`;
  }
}

export async function createSession(
  accessKey?: string,
): Promise<{ token: string; mode: "sample" | "live" }> {
  const response = await fetchApi(`${API_URL}/api/session`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ accessKey }),
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Could not open your workspace.");
  return payload;
}
