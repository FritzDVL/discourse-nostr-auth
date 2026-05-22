import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath, URL } from "node:url";

// Build a single self-contained IIFE that Discourse can register as a plugin
// asset (see plugin.rb `register_asset 'javascripts/nostr.iife.js'`).
// Output lands at ../assets/javascripts/nostr.iife.js so it is shipped with
// the plugin and served at the usual Discourse plugin-asset URL. No code
// splitting — Discourse loads plugin JS as a single tag.
export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  build: {
    target: "es2020",
    cssCodeSplit: false,
    emptyOutDir: false,
    outDir: fileURLToPath(new URL("../assets/javascripts", import.meta.url)),
    lib: {
      entry: fileURLToPath(new URL("./src/main.ts", import.meta.url)),
      name: "DiscourseNostrAuth",
      formats: ["iife"],
      fileName: () => "nostr.iife.js",
    },
    rollupOptions: {
      output: {
        inlineDynamicImports: true,
      },
    },
  },
});
