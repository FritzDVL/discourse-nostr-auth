// Best-effort kind:0 (user metadata) fetch from a small list of relays.
//
// This is browser-side on purpose. Doing it server-side would force us to
// bundle a Ruby WebSocket client and keep relay state in the Discourse
// process, which is exactly the kind of dependency surface we're trying to
// avoid. If profile fetch fails, the user still signs in — Discourse will
// just use the fallback `nostr:abc123...` display name from the strategy.
//
// We race relays and return the FIRST valid kind:0 event we receive that
// matches the pubkey. We don't try to be clever about freshness — for an
// initial login, any of the user's recent profile metadata is fine.

export interface NostrProfile {
  name?: string;
  display_name?: string;
  picture?: string;
  nip05?: string;
  about?: string;
}

export async function fetchProfile(
  pubkey: string,
  relays: string[],
  timeoutMs: number,
): Promise<NostrProfile | null> {
  const attempts = relays.map((url) => fetchProfileFromRelay(pubkey, url, timeoutMs));
  const result = await firstSuccess(attempts);
  return result;
}

function fetchProfileFromRelay(
  pubkey: string,
  url: string,
  timeoutMs: number,
): Promise<NostrProfile | null> {
  return new Promise((resolve) => {
    let ws: WebSocket | null = null;
    let done = false;
    const finish = (val: NostrProfile | null) => {
      if (done) return;
      done = true;
      try { ws?.close(); } catch { /* ignore */ }
      resolve(val);
    };

    const timer = setTimeout(() => finish(null), timeoutMs);

    try {
      ws = new WebSocket(url);
    } catch {
      clearTimeout(timer);
      finish(null);
      return;
    }

    const subId = "p" + Math.random().toString(36).slice(2, 10);

    ws.onopen = () => {
      ws?.send(JSON.stringify(["REQ", subId, { authors: [pubkey], kinds: [0], limit: 1 }]));
    };

    ws.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (!Array.isArray(msg)) return;
        if (msg[0] === "EVENT" && msg[1] === subId && msg[2]?.kind === 0) {
          const parsed = safeParse(msg[2].content);
          clearTimeout(timer);
          finish(parsed);
        } else if (msg[0] === "EOSE" && msg[1] === subId) {
          clearTimeout(timer);
          finish(null);
        }
      } catch { /* ignore */ }
    };

    ws.onerror = () => { clearTimeout(timer); finish(null); };
    ws.onclose = () => { clearTimeout(timer); finish(null); };
  });
}

function safeParse(s: string): NostrProfile | null {
  try {
    const obj = JSON.parse(s);
    if (typeof obj !== "object" || obj === null) return null;
    return {
      name: typeof obj.name === "string" ? obj.name : undefined,
      display_name: typeof obj.display_name === "string" ? obj.display_name : undefined,
      picture: typeof obj.picture === "string" ? obj.picture : undefined,
      nip05: typeof obj.nip05 === "string" ? obj.nip05 : undefined,
      about: typeof obj.about === "string" ? obj.about : undefined,
    };
  } catch {
    return null;
  }
}

async function firstSuccess<T>(promises: Promise<T | null>[]): Promise<T | null> {
  return new Promise((resolve) => {
    let remaining = promises.length;
    if (remaining === 0) return resolve(null);
    promises.forEach((p) => {
      p.then((v) => {
        if (v !== null) resolve(v);
        if (--remaining === 0) resolve(null);
      }).catch(() => {
        if (--remaining === 0) resolve(null);
      });
    });
  });
}
