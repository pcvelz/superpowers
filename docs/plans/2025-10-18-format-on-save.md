# Format on Save Feature

**Date:** 2025-10-18
**Status:** Approved for Implementation

## Problem Statement

Users want files to be automatically formatted when Claude writes or modifies them, respecting project-specific formatters (Prettier, Black, gofmt, etc.). Currently, files written by Claude may not match the project's formatting standards, requiring manual formatting afterward.

## Goals

- Automatically format files when Claude saves them (via Write/Edit tools)
- Detect formatters from project configuration files
- Support common formatters: Prettier, Black, gofmt, rustfmt
- Make formatting opt-in via `.claude/settings.json`
- Gracefully handle missing formatters or formatting failures

## Non-Goals

- Real-time formatting during editing
- Custom formatter configuration beyond project defaults
- Formatting validation or enforcement
- Integration with LSP/language servers

## Design

### Architecture

```
User enables formatOnSave in settings
         ↓
Claude uses Write/Edit tool
         ↓
File is written to disk
         ↓
Format detector checks for formatter config
         ↓
If formatter found and formatOnSave enabled:
  Run formatter on file
         ↓
Return success/failure to Claude
```

### Components

1. **Settings Schema** (`.claude/settings.schema.json`)
   - Add `formatOnSave: boolean` option (default: false)

2. **Format Detector** (`src/utils/formatDetector.ts`)
   - Scans for config files: `.prettierrc`, `pyproject.toml`, etc.
   - Returns formatter command based on file extension and detected config
   - Caches detection results per session

3. **Format Executor** (`src/utils/formatExecutor.ts`)
   - Executes formatter command on file path
   - Handles timeouts (5 second max)
   - Returns success/failure without blocking

4. **Integration Point**
   - Modify Write/Edit tools to call formatter after file write
   - Only format if `formatOnSave` is enabled
   - Log formatting results but don't fail on formatting errors

### Format Detection Rules

| File Extension | Config Files to Check | Formatter Command |
|----------------|----------------------|-------------------|
| `.js`, `.ts`, `.jsx`, `.tsx`, `.json`, `.md` | `.prettierrc*`, `prettier.config.*` | `prettier --write <file>` |
| `.py` | `pyproject.toml` (with `[tool.black]`), `.black` | `black <file>` |
| `.go` | (always available in Go projects) | `gofmt -w <file>` |
| `.rs` | `rustfmt.toml`, `.rustfmt.toml` | `rustfmt <file>` |

### Error Handling

- If formatter not found: silently skip formatting
- If formatter fails: log error but return success for file write
- If formatter times out: kill process and log warning
- Never fail a Write/Edit operation due to formatting issues

## Implementation Plan

1. Add `formatOnSave` setting to schema and types
2. Implement format detector with tests
3. Implement format executor with tests
4. Hook into Write/Edit tools
5. Add integration tests
6. Update documentation

## Testing Strategy

- Unit tests for format detection logic
- Unit tests for format execution with mock formatters
- Integration tests with real formatter tools
- Test error cases: missing formatter, timeout, failed formatting
- Test that formatOnSave=false skips formatting

## Open Questions

None - ready for implementation.

## Alternatives Considered

1. **LSP Integration**: Too complex, requires language server setup
2. **Pre-commit hooks**: Only works on git commits, not all file writes
3. **Manual formatting command**: Requires user to remember to run it
