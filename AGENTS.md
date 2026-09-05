# NETRA — Multi-Agent Context & Guidelines (`AGENTS.md`)

This repository follows the unified AI context specification. All agents (Antigravity, Cursor, Windsurf, Copilot, and Claude) should refer to [`CLAUDE.md`](./CLAUDE.md) for project architecture, roadmap status, clinical constraints, and data contracts.

### Quick Reference:
- **Project Goal:** Automated Diabetic Retinopathy (DR) triage & decision support.
- **Config Path:** `configs/default_config.yaml` (Never hardcode clinical thresholds).
- **Core Pipeline Contract:** Output of enhancement must be `(512, 512, 3)` `float32` in `[0.0, 1.0]`.
- **Active Branch:** `mayank-Krrish`.
- **Run Tests:** `pytest tests/ -v` or `python tests/test_quality_gate.py`.

See full technical details and architectural constraints in [CLAUDE.md](./CLAUDE.md).
