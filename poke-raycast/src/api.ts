const BASE = "http://127.0.0.1:42123";

export type NearbyPeer = { id: string; displayName: string };
export type RecentPeer = { id: string; displayName: string; lastSeenISO: string };

export async function isHealthy() {
  try {
    const r = await fetch(`${BASE}/v1/health`, { cache: "no-store" });
    if (!r.ok) return false;
    const j = (await r.json()) as { ok?: boolean };
    return Boolean(j?.ok);
  } catch {
    return false;
  }
}

export async function getStatus() {
  const r = await fetch(`${BASE}/v1/status`);
  if (!r.ok) throw new Error(`status ${r.status}`);
  return (await r.json()) as {
    ok: boolean;
    name: string;
    visible: boolean;
    nearbyCount: number;
    nearby: NearbyPeer[];
  };
}

export async function getPeers() {
  const r = await fetch(`${BASE}/v1/peers`);
  if (!r.ok) throw new Error(`status ${r.status}`);
  return (await r.json()) as {
    ok: boolean;
    nearby: NearbyPeer[];
    recentlySeen: RecentPeer[];
  };
}

export async function sendPoke(to: string, note?: string) {
  const r = await fetch(`${BASE}/v1/poke`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ to, note: note ?? "" }),
  });
  if (!r.ok) throw new Error(`status ${r.status}`);
  return (await r.json()) as { ok: boolean; delivered: boolean };
}

export async function setVisible(visible: boolean) {
  const r = await fetch(`${BASE}/v1/visible`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ visible }),
  });
  if (!r.ok) throw new Error(`status ${r.status}`);
  return (await r.json()) as { ok: boolean; visible: boolean };
}
