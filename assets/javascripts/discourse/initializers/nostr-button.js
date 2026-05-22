import { withPluginApi } from "discourse/lib/plugin-api";

// The login button is rendered by Discourse's standard auth-provider machinery
// (see plugin.rb `auth_provider`). All this initializer does is bolt the
// Vue/Shadow-DOM widget onto the page when the user clicks the button, so the
// widget can talk to the NIP-07 browser extension and POST to /auth/nostr/verify.
//
// The widget bundle (`nostr.iife.js`) is built from /ui by Vite and registered
// as a plugin asset in plugin.rb. It mounts into a single shadow-rooted host
// element so Discourse CSS cannot bleed into it and vice versa.
export default {
  name: "discourse-nostr-auth",

  initialize() {
    withPluginApi("1.8.0", (api) => {
      api.onPageChange(() => {
        ensureHost();
      });
      ensureHost();
    });
  },
};

function ensureHost() {
  if (document.getElementById("discourse-nostr-auth-host")) return;
  const host = document.createElement("div");
  host.id = "discourse-nostr-auth-host";
  document.body.appendChild(host);

  // The IIFE bundle auto-mounts into #discourse-nostr-auth-host inside a
  // shadow root and listens for clicks on `.btn-social.nostr`.
}
