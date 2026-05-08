# Sparkle Update Signing Keys

AgentTAB releases are signed with an EdDSA keypair so Sparkle can verify
updates client-side, even though we don't code-sign the app itself.

## Where the keys live

- **Private key**: macOS Keychain on the developer machine, under entry
  "Sparkle EdDSA private key for AgentTAB" (managed by Sparkle's
  `generate_keys` / `sign_update` tools).
- **Public key**: `agenttab/sparkle-public-key.txt` (gitignored — generated
  per-machine via `generate_keys`).

## Initial setup

```sh
SPARKLE_VERSION=2.6.4
curl -L "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
     -o /tmp/sparkle-${SPARKLE_VERSION}.tar.xz
mkdir -p /tmp/sparkle-cli && tar xJf /tmp/sparkle-${SPARKLE_VERSION}.tar.xz -C /tmp/sparkle-cli
/tmp/sparkle-cli/bin/generate_keys                        # first run; prompts Keychain
/tmp/sparkle-cli/bin/generate_keys | grep -E '^[A-Za-z0-9+/=]+$' | tail -1 \
    > agenttab/sparkle-public-key.txt
```

## Loss recovery

If the private key is lost (Keychain wiped, machine retired without backup),
EVERY existing AgentTAB install can no longer verify new updates — the
embedded public key won't match a freshly-generated private key. You'd
have to ship a new DMG (out-of-band, manual download) that bundles a new
public key, then resume Sparkle updates from there.

**Mitigation**: back up the private key by exporting from Keychain Access:
- Find "Sparkle EdDSA private key for AgentTAB"
- Right-click → Export → save as `.p12` or similar
- Store offline (1Password, hardware token, encrypted volume).

## Multi-developer setup (future)

For a team of devs releasing builds, each release machine needs the same
private key in its Keychain. The simplest path is to share an exported
`.p12` via a password manager. The `agenttab/sparkle-public-key.txt` file
is gitignored, so each fresh clone needs to re-run `generate_keys` (or
have the canonical public key copied in) — the public key MUST match the
private key used to sign the appcast, otherwise Sparkle rejects updates.
