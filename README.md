# discourse-nostr-auth

Sign in with [Nostr](https://nostr.com) for [Discourse](https://www.discourse.org).
A user clicks **Sign in with Nostr**, their browser extension (Alby, nos2x,
Flamingo, …) signs a one-time challenge, and Discourse logs them in against
their Nostr public key — no email, no password.

> Status: **v1, NIP-07 (browser extension) only.** NIP-46 (remote signer
> over Nostr) is planned for v2. See [Roadmap](#roadmap).

## How it works

1. Discourse renders a standard auth-provider button — the same machinery
   used by Google, GitHub, etc.
2. Clicking the button opens a small in-page widget (Vue, shadow-DOM
   isolated) that asks the server for a fresh challenge nonce.
3. The widget calls `window.nostr.signEvent(...)` (NIP-07). The browser
   extension shows its own confirmation dialog. The user's private key
   **never leaves the extension**.
4. The widget POSTs the signed kind:22242 event back to
   `/auth/nostr/verify`. The server:
   - re-checks every NIP-01 structural rule,
   - re-computes the event id from the canonical serialization,
   - verifies the BIP-340 Schnorr signature against the embedded pubkey,
   - then — and only then — hands the verified pubkey to OmniAuth and
     Discourse's `ManagedAuthenticator` does the rest (account lookup,
     creation, linking).
5. The widget also does a best-effort kind:0 profile fetch from a small
   default relay list (damus, nos.lol, snort) so the new account picks up
   the user's display name and avatar. This is **browser-side on purpose** —
   the server intentionally does not bundle a Ruby WebSocket client.

## Why a pure-Ruby BIP-340 verifier?

The Schnorr verifier in `lib/discourse_nostr/bip340_verifier.rb` is plain
Ruby on top of `OpenSSL::Digest::SHA256`. No `rbsecp256k1`, no
`libsecp256k1`, no `bitcoinrb`, no native-extension gems at all.

That choice is deliberate. Discourse's plugin install discipline runs
`gem install --ignore-dependencies` against a long-lived base image, and
every native-extension dependency is one libsecp256k1 ABI bump away from
breaking boot on every site running this plugin. Owning the verifier means
we own the security-critical code path. To make sure we never regress, the
plugin runs the official BIP-340 test vectors as a **boot-time smoke test**
(`lib/discourse_nostr/boot_smoke_test.rb`) and refuses to start if either
the good-signature or bad-signature check fails. The full vector suite runs
under CI in `spec/bip340_verifier_spec.rb`.

## Settings

| Key                                | Default                                                              | Notes                                          |
| ---------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------- |
| `discourse_nostr_enabled`          | `false`                                                              | Master kill switch.                            |
| `nostr_default_relays`             | `wss://relay.damus.io \| wss://nos.lol \| wss://relay.snort.social`  | Browser-side profile lookup only.              |
| `nostr_challenge_ttl_seconds`      | `300`                                                                | How long a challenge nonce remains valid.      |
| `nostr_event_clock_skew_seconds`   | `60`                                                                 | Allowed +/- skew on `event.created_at`.        |
| `nostr_profile_fetch_timeout_ms`   | `4000`                                                               | Per-relay timeout for kind:0 metadata.         |

## Install (development)

```bash
cd /var/discourse
./launcher enter app
cd /var/www/discourse/plugins
git clone https://github.com/FritzDVL/discourse-nostr-auth
cd discourse-nostr-auth/ui && npm install && npm run build
```

Then enable `discourse_nostr_enabled` in Admin → Site Settings.

## Roadmap

- **v1 (this release)** — NIP-07 browser extensions only.
- **v2** — NIP-46 ("bunker:") remote signers, so mobile-only users with
  Amber / Nsec.app can sign in without a browser extension.

## CI

A GitHub Actions workflow is shipped as `ci.example.yml` in the repo root.
After cloning, move it into place and commit — the file ships outside
`.github/workflows/` only because the initial push was done with a token
that did not carry the `workflow` OAuth scope, and GitHub blocks any tree
write touching `.github/workflows/` from such tokens.

```bash
mkdir -p .github/workflows
git mv ci.example.yml .github/workflows/ci.yml
git commit -m "ci: enable GitHub Actions workflow"
git push
```

## License

MIT. See [LICENSE](./LICENSE).
