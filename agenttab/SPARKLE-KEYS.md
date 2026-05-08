# Sparkle Update Signing Keys

AgentTAB updates are signed with an EdDSA keypair so Sparkle can verify
update payloads client-side, even though we don't code-sign the app
itself. Two keys are involved: a **public** key embedded in every shipped
copy of AgentTAB.app, and a **private** key on each release machine that
signs new DMGs.

## Where the keys live

| Key | Storage | Committed? |
|-----|---------|------------|
| **Public**  | `agenttab/sparkle-public-key.txt` (committed to git) | yes — public keys are meant to be public |
| **Private** | macOS Keychain on the release machine, entry "Private key for signing Sparkle updates" (managed by Sparkle's `generate_keys` / `sign_update`) | NEVER |

The public key is the trust root: every shipped copy of AgentTAB has it
in its `Info.plist` (`SUPublicEDKey`), and Sparkle verifies every update
DMG against it before installing. **All release machines must sign with
the matching private key**, otherwise installs reject the update.

## Initial setup (already done)

The keypair was generated during M7.1. To reproduce on a fresh checkout:

```sh
SPARKLE_VERSION=2.6.4
curl -L "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
     -o /tmp/sparkle-${SPARKLE_VERSION}.tar.xz
mkdir -p /tmp/sparkle-cli && tar xJf /tmp/sparkle-${SPARKLE_VERSION}.tar.xz -C /tmp/sparkle-cli
/tmp/sparkle-cli/bin/generate_keys              # one-time, prompts Keychain on first run
/tmp/sparkle-cli/bin/generate_keys -p           # prints just the public key
```

If you're a NEW release machine (not the one that generated the original
keypair), you need the existing private key — see "Adding a release
machine" below.

## Loss recovery

If the private key is lost (Keychain wiped, machine retired without
backup), every shipped AgentTAB install can no longer verify new updates
— the embedded public key won't match a freshly-generated private key.
Recovery requires:

1. Generate a new keypair.
2. Update `agenttab/sparkle-public-key.txt` with the new public key.
3. Ship a new DMG (out-of-band, manual download) with the new public key
   embedded.
4. From then on, sign all updates with the new private key.

**Mitigation**: back up the private key:

- Open Keychain Access.
- Find "Private key for signing Sparkle updates".
- Right-click → Export → save as `.p12`.
- Store offline (1Password, encrypted volume, hardware token).

## Adding a release machine

Each additional release machine needs the same private key in its
Keychain (so signed updates verify against the same public key already
shipped). Workflow:

1. Export the `.p12` from the original release machine (see above).
2. Transfer securely (1Password share, GPG-encrypted file).
3. On the new machine, double-click the `.p12` → import to Keychain.
4. Verify: `/tmp/sparkle-cli/bin/generate_keys -p` should print the SAME
   public key as `cat agenttab/sparkle-public-key.txt`. If not, the
   import failed.

## What to do if the public key file is missing

The Xcode build hard-fails with:

```
error: sparkle-public-key.txt missing — generate via Sparkle's generate_keys, see SPARKLE-KEYS.md
```

This is intentional — building without an embedded public key would
produce an unverifiable Sparkle channel. Run the setup steps above
(or `git checkout` the file if it was deleted) and rebuild.
