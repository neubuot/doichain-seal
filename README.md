# Doichain Seal

[![Doichain Seal](https://doi-api.sendlabs.de/seal/github/neubuot/doichain-seal/seal.svg)](https://doi-api.sendlabs.de/seal/github/neubuot/doichain-seal)

A GitHub Action that gives every release a **tamper-evident timestamp on the Doichain blockchain**.
It computes the SHA-256 of your release files and anchors it on chain, together with repository, tag and commit.
Anyone can later check that a download is exactly the file you published, and since when it exists.

- **No account, no wallet, no secrets.** The job proves its identity with the GitHub OIDC token it already has.
- **Public proof.** The seal is a name `poe/<sha256>` on the public Doichain blockchain. It can be verified with any Doichain node, with the [Doichain API](https://doi-api.sendlabs.de/docs), with [Verifile](https://verifile.it/) or via the [Doichain MCP server](https://doi-api.sendlabs.de/mcp). If this service disappears, the proof stays.
- **A seal for your README** that shows the latest sealed release, its block and date (large card or compact badge), and a proof page per repository and per file.
- **Free.** DOI Labs pays the chain fees. 20 seals per repository and day, 300 per day for everyone.

[Proof page example](https://doi-api.sendlabs.de/seal) · [How it works](https://doi-api.sendlabs.de/seal#how) · [Deutsche Fassung](README.de.md)

## Usage

```yaml
name: Release
on:
  release:
    types: [published]

permissions:
  contents: read
  id-token: write      # lets the job prove its identity to the seal service

jobs:
  seal:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./build.sh                      # produces dist/*
      - uses: neubuot/doichain-seal@v1
        with:
          files: |
            dist/*
            SHA256SUMS
```

Then add the seal to your README (the action prints the exact snippet in the job summary). The large seal shows tag, block and date, a compact badge is available as `badge.svg`:

```markdown
[![Doichain Seal](https://doi-api.sendlabs.de/seal/github/OWNER/REPO/seal.svg)](https://doi-api.sendlabs.de/seal/github/OWNER/REPO)
```

### Inputs

| Input | Default | Description |
|---|---|---|
| `files` | required | Files to seal, one glob per line. Directories are skipped. |
| `api-url` | `https://doi-api.sendlabs.de` | Base URL of the Doichain API that runs the seal service. |
| `note` | | Optional note, stored publicly on the chain (at most 60 characters). |
| `wait` | `0` | Seconds to wait for the first confirmation. A block arrives about every 10 minutes, so `900` is a sensible value if you need the block height inside the workflow. |
| `retry` | `1` | Retries when the seal service waits for the next Doichain block (HTTP 503). The node accepts about 25 chained seals per block, so a busy service asks you to come back in 10 minutes. Each retry waits 10 minutes. |
| `fail-on-error` | `true` | Fail the step when a file cannot be sealed, or only warn. |
| `summary` | `true` | Write a job summary with proof links and the badge snippet. |

### Outputs

| Output | Description |
|---|---|
| `results` | JSON array, one object per file: `file`, `size`, `hash`, `status` (`anchored`, `already_anchored`, `confirmed`, `failed`), `txid`, `proof_url`, `badge_url`. |
| `sealed` / `failed` | Number of sealed and failed files. |
| `repo-page-url` | Proof page of the repository. |
| `badge-url` | Large SVG seal of the repository (latest seal). The compact badge is the same path with `badge.svg`. |
| `badge-markdown` | Ready-to-paste README snippet. |

## What the seal proves

- **Existence and time.** A file with exactly this SHA-256 existed no later than the time of the block that contains the seal.
- **Origin.** The job sent a GitHub OIDC token. The seal service verifies the token (signature, issuer, audience, expiry) and writes repository, ref and commit into the name value. The proof page marks such seals as verified origin.
- **Independence.** The proof lives on a public blockchain and does not depend on this action or the seal service.

What it does not prove: who holds the signing keys of your project, or that the file is free of defects. Pair it with [Sigstore](https://www.sigstore.dev/) or GPG signatures if you need identity-bound signatures. The seal answers *when* and *what*, a signature answers *who*.

Names on the Doichain expire after 36,000 blocks (about 250 days). The timestamp stays in the chain history forever, the proof page always shows the first anchoring. Repository, tag, commit and file name are public on the chain. The file itself never leaves the runner, only its hash is sent.

## Verify a release by hand

```bash
sha256sum app-1.2.3.tar.gz
# compare with the proof page:
curl https://doi-api.sendlabs.de/v1/poe/<sha256>
```

Or open `https://doi-api.sendlabs.de/seal/<sha256>`, or drop the file into [Verifile](https://verifile.it/). The API also provides a Merkle inclusion proof (`GET /v1/tx/<txid>/proof`) for a check against a block header.

## Self-hosting

The seal service is part of the open [Doichain API](https://doi-api.sendlabs.de/docs). Run your own node and API, set `DOI_SEAL_AUDIENCE` if you want a different token audience, and point the action to it with `api-url`.

## License

MIT, DOI Labs AG. Doichain is a public blockchain, see [doilabs.org](https://doilabs.org/).
