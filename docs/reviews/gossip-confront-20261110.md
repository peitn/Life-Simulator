# Review: gossip confrontation and denial (10 November 2026)

Run `main-claude-1794338540-311463` completed the feature started by the crashed run `main-claude-1794295321-304122`.

## Independent findings
- Gemini (flash-lite; flash overloaded; output truncated twice, so the audit is partial):
  - rejected: missing suspect guard (exists), non-deterministic RNG (member RNG with saved state), client-supplied rumour id (not sent), client-side double application (clients receive no events), "cryptographically secure" selection (determinism on the authority is intended);
  - accepted: denying a witnessed panic attack must not be punished as a lie. Now only a stigmatising witness cools (−4 × stigma), no trust breach, kind reply.
- Grok (#430): retraction cap, social proof for denial, damped escalation spiral (+ 5-day soak), sensitive kinds — all addressed.
- Own testing found that AI never chose to confront (base appeal 0); fixed in the utility planner.

## Verification
`test_gossip_confront` 97/97, `test_gossip` 116/116, 25 regression suites pass (see AUDIT.md).
