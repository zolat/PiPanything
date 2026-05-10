# Roadmap

**Current:** ✅ Done — ready for review on `feat/multi-overlay`

- [x] Phase 0 — Worktree + ROADMAP
- [x] Phase 0.5 — SCStream same-source spike (✅ both stream concurrently on the same SCWindow → "always add" picker has no special-casing)
- [x] Phase 1 — Extract OverlaySession (pure refactor; still single overlay)
- [x] Phase 2 — Introduce OverlayCoordinator (still single session at runtime)
- [x] Phase 3 — Multi-session menu + pick semantics + cascade (verified: 3 overlays via PIP_AUTO_CAPTURE_COUNT=3, distinct cascade positions, all render)
- [x] Phase 4 — Per-overlay right-click menu (session-scoped: Stop / Crop / Auto-hide / Transparency inline + Other overlays + Pick window)
- [x] Phase 5 — Final verification (single-overlay regression, multi-overlay smoke, dispatch chain, clean SIGINT shutdown)
- [ ] Phase 3 — Multi-session menu + pick semantics + cascade positioning
- [ ] Phase 4 — Per-overlay right-click menu
- [ ] Phase 5 — Soft cap warning + final verification

Plan: `~/.claude/plans/serialized-finding-meadow.md`. Branch: `feat/multi-overlay`.
