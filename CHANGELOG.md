# Changelog

## 1.0.3 (2026-10-14)

Default of `retry` raised to 2: Doichain blocks are not always 10 minutes apart, one retry often came too early.

## 1.0.2 (2026-10-13)

New input `retry` (default 1): when the seal service answers 503 because too many seals wait for the next Doichain block, the action waits 10 minutes and tries again.

## 1.0.1 (2026-10-13)

README badge and job summary use the large seal (`seal.svg`), the compact badge stays available as `badge.svg`.

## 1.0.0 (2026-10-13)

First release. Composite action that seals release files on the Doichain via `POST /v1/seal/github` of the Doichain API, authenticated with the GitHub OIDC token of the job. Inputs `files`, `api-url`, `note`, `wait`, `fail-on-error`, `summary`. Outputs `results`, `sealed`, `failed`, `repo-page-url`, `badge-url`, `badge-markdown`. Job summary with proof links and README badge.
