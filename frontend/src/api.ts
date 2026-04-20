import type { BaseGamesMap, Caps, Defaults, NetworkPreset, RunRequest, RunResponse } from './types';

// Build-time env. Set VITE_API_URL in .env.development (dev) and .env.production
// (build). Falls back to localhost:8080 for direct `vite` invocations without
// env files loaded.
const DEFAULT_BASE =
  (import.meta.env as Record<string, string | undefined>).VITE_API_URL
  ?? (import.meta.env as Record<string, string | undefined>).VITE_API_BASE  // legacy name
  ?? 'http://localhost:8080';

async function jsonGet<T>(path: string): Promise<T> {
  const r = await fetch(`${DEFAULT_BASE}${path}`);
  if (!r.ok) throw new Error(`${path} → ${r.status} ${r.statusText}`);
  return r.json() as Promise<T>;
}

async function jsonPost<T>(path: string, body: unknown): Promise<T> {
  const r = await fetch(`${DEFAULT_BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!r.ok) {
    let msg = `${r.status} ${r.statusText}`;
    try {
      const j = await r.json();
      if (j?.error) msg = j.error;
    } catch { /* body wasn't json */ }
    throw new Error(msg);
  }
  return r.json() as Promise<T>;
}

export const fetchDefaults = () =>
  jsonGet<{ defaults: Defaults; caps: Caps }>('/defaults');

export const fetchBaseGames = () =>
  jsonGet<{ base_games: BaseGamesMap }>('/base-games');

export const fetchNetworkConfigs = () =>
  jsonGet<{ presets: NetworkPreset[] }>('/network-configs');

export const postRun = (body: RunRequest) =>
  jsonPost<RunResponse>('/run', body);

export const ping = () => jsonGet<{ status: string }>('/health');
