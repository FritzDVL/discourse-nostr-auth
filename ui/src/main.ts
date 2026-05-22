import { createApp } from "vue";
import NostrAuth from "./NostrAuth.vue";
import { mountIntoShadow } from "./shadow";

// Entry point for the IIFE bundle that Discourse loads as a plugin asset.
//
// The Vue widget mounts inside a closed shadow root so Discourse's global CSS
// cannot bleed into it. We listen for clicks on `.btn-social.nostr` (the
// button Discourse renders automatically for the `nostr` auth provider) and
// open the widget on demand.
function boot() {
  const host = document.getElementById("discourse-nostr-auth-host");
  if (!host) return;

  const { mountPoint } = mountIntoShadow(host);
  const app = createApp(NostrAuth);
  app.mount(mountPoint);

  // Intercept the standard auth button click so we can run the NIP-07 flow
  // in-page instead of redirecting to a fictional /auth/nostr GET endpoint.
  document.addEventListener(
    "click",
    (ev) => {
      const target = ev.target as HTMLElement | null;
      if (!target) return;
      const btn = target.closest(".btn-social.nostr");
      if (!btn) return;
      ev.preventDefault();
      ev.stopPropagation();
      window.dispatchEvent(new CustomEvent("discourse-nostr:open"));
    },
    true,
  );
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot, { once: true });
} else {
  boot();
}
