# Doichain Seal

[![Doichain Seal](https://doi-api.sendlabs.de/seal/github/neubuot/doichain-seal/seal.svg)](https://doi-api.sendlabs.de/seal/github/neubuot/doichain-seal)

Eine GitHub Action, die jeder Veröffentlichung einen **fälschungssicheren Zeitstempel auf der Doichain** gibt.
Sie berechnet den SHA-256 der Release-Dateien und verankert ihn in der Kette, zusammen mit Repository, Tag und Commit.
Jeder kann später prüfen, dass ein Download genau die veröffentlichte Datei ist und seit wann sie existiert.

- **Kein Konto, kein Wallet, keine Geheimnisse.** Der Job weist sich mit dem GitHub-OIDC-Token aus, das er ohnehin hat.
- **Öffentlicher Beweis.** Das Siegel ist der Name `poe/<sha256>` auf der öffentlichen Doichain. Prüfbar mit jeder Doichain-Node, der [Doichain API](https://doi-api.sendlabs.de/docs), mit [Verifile](https://verifile.it/) oder über den [Doichain-MCP-Server](https://doi-api.sendlabs.de/mcp). Verschwindet dieser Dienst, bleibt der Beweis.
- **Siegel für die README** mit dem neuesten versiegelten Release, Block und Datum (große Karte oder kompaktes Abzeichen), dazu eine Prüfseite je Repository und je Datei.
- **Kostenlos.** DOI Labs trägt die Kettengebühren. 20 Siegel je Repository und Tag, 300 je Tag insgesamt.

[Prüfseite](https://doi-api.sendlabs.de/seal) · [English version](README.md)

## Verwendung

```yaml
name: Release
on:
  release:
    types: [published]

permissions:
  contents: read
  id-token: write      # damit sich der Job beim Siegeldienst ausweisen kann

jobs:
  seal:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./build.sh                      # erzeugt dist/*
      - uses: neubuot/doichain-seal@v1
        with:
          files: |
            dist/*
            SHA256SUMS
```

Danach das Siegel in die README (die Action schreibt den fertigen Schnipsel in die Zusammenfassung des Jobs). Das große Siegel zeigt Tag, Block und Datum, ein kompaktes Abzeichen gibt es unter `badge.svg`:

```markdown
[![Doichain Seal](https://doi-api.sendlabs.de/seal/github/OWNER/REPO/seal.svg)](https://doi-api.sendlabs.de/seal/github/OWNER/REPO)
```

Eingaben und Ausgaben sind in der [englischen README](README.md#inputs) beschrieben.

## Was das Siegel beweist

- **Existenz und Zeitpunkt.** Eine Datei mit genau diesem SHA-256 existierte spätestens zur Zeit des Blocks, der das Siegel enthält.
- **Herkunft.** Der Job hat ein GitHub-OIDC-Token geschickt. Der Siegeldienst prüft Signatur, Aussteller, Zielgruppe und Ablauf und schreibt Repository, Ref und Commit in den Wert des Namens. Die Prüfseite kennzeichnet solche Siegel als geprüfte Herkunft.
- **Unabhängigkeit.** Der Beweis liegt auf einer öffentlichen Blockchain und hängt weder an dieser Action noch am Siegeldienst.

Was es nicht beweist: wer die Signaturschlüssel des Projekts hält oder dass die Datei fehlerfrei ist. Für identitätsgebundene Signaturen bleiben [Sigstore](https://www.sigstore.dev/) oder GPG die richtige Ergänzung. Das Siegel beantwortet *wann* und *was*, eine Signatur beantwortet *wer*.

Namen auf der Doichain laufen nach 36.000 Blöcken ab (rund 250 Tage). Der Zeitstempel bleibt für immer in der Kettenhistorie, die Prüfseite zeigt stets die erste Verankerung. Repository, Tag, Commit und Dateiname sind öffentlich auf der Kette. Die Datei selbst verlässt den Runner nicht, nur ihr Hash wird gesendet.

## Lizenz

MIT, DOI Labs AG. Doichain ist eine öffentliche Blockchain, siehe [doilabs.org](https://doilabs.org/).
