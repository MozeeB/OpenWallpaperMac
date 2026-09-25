# Contributing

1. Read the [clean-room policy](docs/CLEANROOM.md) — mandatory for scene/format work.
2. Tests first: add a failing test in the matching `Tests/<Module>Tests` target, then implement.
3. Before opening a PR:

```bash
swiftlint lint --strict
```

```bash
swift test --enable-code-coverage && scripts/coverage-gate.sh
```

4. Keep files focused (≤ 400 lines typical, 800 max), functions under ~50 lines, models immutable
   (`let` properties + `with…` copies), and treat every imported file as untrusted.
5. Performance-sensitive changes: include `owctl bench` numbers before/after (see
   [docs/performance.md](docs/performance.md)).

Commit messages: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`, `ci:`.
