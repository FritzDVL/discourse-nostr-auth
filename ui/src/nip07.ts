// Thin typed wrapper around the NIP-07 browser API exposed by Alby, nos2x,
// Flamingo, etc. as `window.nostr`. We never touch private keys here — the
// extension signs the event and returns it.
//
// https://github.com/nostr-protocol/nips/blob/master/07.md

export interface UnsignedEvent {
  pubkey: string;
  created_at: number;
  kind: number;
  tags: string[][];
  content: string;
}

export interface SignedEvent extends UnsignedEvent {
  id: string;
  sig: string;
}

interface Nip07Provider {
  getPublicKey(): Promise<string>;
  signEvent(event: UnsignedEvent): Promise<SignedEvent>;
  getRelays?(): Promise<Record<string, { read: boolean; write: boolean }>>;
}

declare global {
  interface Window {
    nostr?: Nip07Provider;
  }
}

export function hasNip07(): boolean {
  return typeof window !== "undefined" && !!window.nostr;
}

export async function signLoginEvent(challenge: string, relayHint: string): Promise<SignedEvent> {
  if (!window.nostr) throw new Error("no_nip07");
  const pubkey = await window.nostr.getPublicKey();
  const unsigned: UnsignedEvent = {
    pubkey,
    created_at: Math.floor(Date.now() / 1000),
    kind: 22242,
    tags: [
      ["relay", relayHint],
      ["challenge", challenge],
    ],
    content: "",
  };
  return window.nostr.signEvent(unsigned);
}
