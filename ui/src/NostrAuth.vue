<template>
  <div :class="['modal', { open }]" @click.self="close">
    <div class="card">
      <h2>Sign in with Nostr</h2>
      <p v-if="state === 'idle'">Click below to sign a one-time challenge with your Nostr extension.</p>
      <p v-else-if="state === 'signing'">Waiting for your Nostr extension…</p>
      <p v-else-if="state === 'verifying'">Verifying signature…</p>
      <p v-else-if="state === 'fetching_profile'">Fetching your profile…</p>
      <p v-else-if="state === 'done'">Signed in. Redirecting…</p>

      <div v-if="error" class="err">{{ error }}</div>

      <div class="actions">
        <button class="btn ghost" @click="close" :disabled="state === 'done'">Cancel</button>
        <button
          v-if="state === 'idle' || state === 'error'"
          class="btn primary"
          @click="start"
        >Sign event</button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from "vue";
import { hasNip07, signLoginEvent } from "./nip07";
import { fetchProfile } from "./relays";

type State = "idle" | "signing" | "verifying" | "fetching_profile" | "done" | "error";

const open = ref(false);
const state = ref<State>("idle");
const error = ref<string | null>(null);

// Site settings injected by Discourse into the global Site object.
// Falls back to the canonical default relay list if unavailable (e.g. dev preview).
function defaultRelays(): string[] {
  const raw = (window as any).Discourse?.SiteSettings?.nostr_default_relays
    ?? "wss://relay.damus.io|wss://nos.lol|wss://relay.snort.social";
  return String(raw).split("|").map((s) => s.trim()).filter(Boolean);
}

function profileTimeoutMs(): number {
  return Number((window as any).Discourse?.SiteSettings?.nostr_profile_fetch_timeout_ms ?? 4000);
}

function csrfToken(): string {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta?.getAttribute("content") ?? "";
}

function close() {
  if (state.value === "done") return;
  open.value = false;
  state.value = "idle";
  error.value = null;
}

async function start() {
  error.value = null;

  if (!hasNip07()) {
    state.value = "error";
    error.value = "No Nostr extension detected. Install Alby, nos2x, or another NIP-07 extension and reload the page.";
    return;
  }

  try {
    // 1. Ask the server for a fresh challenge nonce.
    const chRes = await fetch("/auth/nostr/challenge", { credentials: "same-origin" });
    if (!chRes.ok) throw new Error("challenge_failed");
    const ch = await chRes.json();

    // 2. Ask the extension to sign a kind:22242 event embedding the challenge.
    state.value = "signing";
    const signed = await signLoginEvent(ch.challenge, ch.relay);

    // 3. Best-effort profile lookup in parallel (browser-side, no server WS deps).
    state.value = "fetching_profile";
    const profilePromise = fetchProfile(signed.pubkey, defaultRelays(), profileTimeoutMs())
      .catch(() => null);
    const profile = await Promise.race([
      profilePromise,
      new Promise<null>((r) => setTimeout(() => r(null), profileTimeoutMs() + 500)),
    ]);

    // 4. POST the signed event (+ optional profile metadata) to the server.
    state.value = "verifying";
    const form = new FormData();
    form.set("event", JSON.stringify(signed));
    if (profile) form.set("profile", JSON.stringify(profile));

    const vRes = await fetch("/auth/nostr/verify", {
      method: "POST",
      credentials: "same-origin",
      headers: { "X-CSRF-Token": csrfToken() },
      body: form,
      redirect: "follow",
    });
    if (!vRes.ok && vRes.type !== "opaqueredirect") {
      throw new Error("verify_failed");
    }

    state.value = "done";
    // The server redirects to /auth/nostr/callback which finishes the login.
    window.location.href = vRes.url || "/";
  } catch (e: any) {
    state.value = "error";
    if (e?.message === "no_nip07") {
      error.value = "No Nostr extension detected.";
    } else if (typeof e?.message === "string" && e.message.toLowerCase().includes("cancel")) {
      error.value = "Sign-in cancelled.";
    } else {
      error.value = "Could not sign in with Nostr. Please try again.";
    }
  }
}

onMounted(() => {
  window.addEventListener("discourse-nostr:open", () => {
    open.value = true;
    state.value = "idle";
    error.value = null;
  });
});
</script>
