# Python CLI Timer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a simple command-line timer that counts down from user-specified duration and beeps when complete.

**Architecture:** Single Python module with CLI argument parsing, countdown display with live updates, and cross-platform audio alert using system beep.

**Tech Stack:** Python 3.8+, argparse (stdlib), time (stdlib), sys (stdlib)

---

## Project Setup

This is a **new standalone project**. Create it in a fresh directory (e.g., `~/projects/pytimer` or wherever you prefer).

---

### Task 1: Initialize Project Structure

**Files:**
- Create: `pytimer/` (project root)
- Create: `pytimer/__init__.py`
- Create: `pytimer/timer.py`
- Create: `tests/__init__.py`
- Create: `tests/test_timer.py`
- Create: `pyproject.toml`

**Step 1: Create project directory and structure**

```bash
mkdir -p pytimer tests
touch pytimer/__init__.py tests/__init__.py
```

**Step 2: Create pyproject.toml**

Create file `pyproject.toml`:

```toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "pytimer"
version = "0.1.0"
description = "Simple CLI countdown timer"
requires-python = ">=3.8"

[project.scripts]
pytimer = "pytimer.timer:main"
```

**Step 3: Commit initial structure**

```bash
git init
git add .
git commit -m "chore: initialize project structure"
```

---

### Task 2: Parse Duration Input

**Files:**
- Create: `pytimer/timer.py`
- Create: `tests/test_timer.py`

**Step 1: Write the failing test for duration parsing**

Create file `tests/test_timer.py`:

```python
from pytimer.timer import parse_duration


def test_parse_duration_seconds_only():
    assert parse_duration("30") == 30


def test_parse_duration_minutes_and_seconds():
    assert parse_duration("1:30") == 90


def test_parse_duration_hours_minutes_seconds():
    assert parse_duration("1:05:30") == 3930
```

**Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_timer.py -v`
Expected: FAIL with "cannot import name 'parse_duration'"

**Step 3: Write minimal implementation**

Create file `pytimer/timer.py`:

```python
def parse_duration(duration_str: str) -> int:
    """Parse duration string to seconds.

    Formats: "30" (seconds), "1:30" (min:sec), "1:05:30" (hr:min:sec)
    """
    parts = duration_str.split(":")
    if len(parts) == 1:
        return int(parts[0])
    elif len(parts) == 2:
        minutes, seconds = int(parts[0]), int(parts[1])
        return minutes * 60 + seconds
    elif len(parts) == 3:
        hours, minutes, seconds = int(parts[0]), int(parts[1]), int(parts[2])
        return hours * 3600 + minutes * 60 + seconds
    else:
        raise ValueError(f"Invalid duration format: {duration_str}")
```

**Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_timer.py -v`
Expected: PASS (3 tests)

**Step 5: Commit**

```bash
git add pytimer/timer.py tests/test_timer.py
git commit -m "feat: add duration parsing (seconds, min:sec, hr:min:sec)"
```

---

### Task 3: Format Remaining Time for Display

**Files:**
- Modify: `pytimer/timer.py`
- Modify: `tests/test_timer.py`

**Step 1: Write the failing test for time formatting**

Append to `tests/test_timer.py`:

```python
from pytimer.timer import parse_duration, format_time


def test_format_time_seconds_only():
    assert format_time(45) == "00:45"


def test_format_time_minutes_and_seconds():
    assert format_time(90) == "01:30"


def test_format_time_hours():
    assert format_time(3661) == "01:01:01"
```

**Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_timer.py::test_format_time_seconds_only -v`
Expected: FAIL with "cannot import name 'format_time'"

**Step 3: Write minimal implementation**

Append to `pytimer/timer.py`:

```python
def format_time(seconds: int) -> str:
    """Format seconds as MM:SS or HH:MM:SS if hours present."""
    hours, remainder = divmod(seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours > 0:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"
```

**Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_timer.py -v`
Expected: PASS (6 tests)

**Step 5: Commit**

```bash
git add pytimer/timer.py tests/test_timer.py
git commit -m "feat: add time formatting for display"
```

---

### Task 4: Implement Beep Function

**Files:**
- Modify: `pytimer/timer.py`
- Modify: `tests/test_timer.py`

**Step 1: Write the failing test for beep**

Append to `tests/test_timer.py`:

```python
from pytimer.timer import parse_duration, format_time, beep


def test_beep_executes_without_error():
    # Just verify it doesn't raise an exception
    beep()  # Should complete without error
```

**Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_timer.py::test_beep_executes_without_error -v`
Expected: FAIL with "cannot import name 'beep'"

**Step 3: Write minimal implementation**

Append to `pytimer/timer.py`:

```python
import sys


def beep(count: int = 3) -> None:
    """Emit system beep sound."""
    for _ in range(count):
        sys.stdout.write("\a")
        sys.stdout.flush()
```

**Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_timer.py -v`
Expected: PASS (7 tests)

**Step 5: Commit**

```bash
git add pytimer/timer.py tests/test_timer.py
git commit -m "feat: add beep function for timer completion alert"
```

---

### Task 5: Implement Countdown Display

**Files:**
- Modify: `pytimer/timer.py`
- Modify: `tests/test_timer.py`

**Step 1: Write the failing test for countdown**

Append to `tests/test_timer.py`:

```python
from unittest.mock import patch
from pytimer.timer import parse_duration, format_time, beep, countdown


def test_countdown_calls_beep_when_done():
    with patch("pytimer.timer.beep") as mock_beep:
        with patch("pytimer.timer.time.sleep"):  # Skip actual sleeping
            countdown(1)
        mock_beep.assert_called_once()


def test_countdown_zero_seconds_beeps_immediately():
    with patch("pytimer.timer.beep") as mock_beep:
        countdown(0)
        mock_beep.assert_called_once()
```

**Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_timer.py::test_countdown_calls_beep_when_done -v`
Expected: FAIL with "cannot import name 'countdown'"

**Step 3: Write minimal implementation**

Add import at top of `pytimer/timer.py`:

```python
import time
```

Append to `pytimer/timer.py`:

```python
def countdown(seconds: int) -> None:
    """Count down from seconds, updating display, then beep."""
    while seconds > 0:
        sys.stdout.write(f"\r{format_time(seconds)} ")
        sys.stdout.flush()
        time.sleep(1)
        seconds -= 1
    sys.stdout.write(f"\r{format_time(0)} \n")
    sys.stdout.write("Time's up!\n")
    beep()
```

**Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_timer.py -v`
Expected: PASS (9 tests)

**Step 5: Commit**

```bash
git add pytimer/timer.py tests/test_timer.py
git commit -m "feat: add countdown display with live updates"
```

---

### Task 6: Add CLI Entry Point

**Files:**
- Modify: `pytimer/timer.py`
- Modify: `tests/test_timer.py`

**Step 1: Write the failing test for CLI parsing**

Append to `tests/test_timer.py`:

```python
from pytimer.timer import parse_args


def test_parse_args_duration():
    args = parse_args(["5:00"])
    assert args.duration == "5:00"


def test_parse_args_message():
    args = parse_args(["1:00", "-m", "Break time"])
    assert args.duration == "1:00"
    assert args.message == "Break time"
```

**Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_timer.py::test_parse_args_duration -v`
Expected: FAIL with "cannot import name 'parse_args'"

**Step 3: Write minimal implementation**

Add import at top of `pytimer/timer.py`:

```python
import argparse
```

Append to `pytimer/timer.py`:

```python
def parse_args(args: list[str] | None = None) -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Simple countdown timer",
        epilog="Examples: pytimer 30 | pytimer 5:00 | pytimer 1:30:00",
    )
    parser.add_argument(
        "duration",
        help="Duration (seconds, MM:SS, or HH:MM:SS)",
    )
    parser.add_argument(
        "-m", "--message",
        default="Time's up!",
        help="Message to display when timer completes",
    )
    return parser.parse_args(args)


def main() -> None:
    """Main entry point."""
    args = parse_args()
    try:
        seconds = parse_duration(args.duration)
    except ValueError as e:
        sys.stderr.write(f"Error: {e}\n")
        sys.exit(1)

    print(f"Timer set for {format_time(seconds)}")
    countdown(seconds)
    if args.message != "Time's up!":
        print(args.message)


if __name__ == "__main__":
    main()
```

**Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_timer.py -v`
Expected: PASS (11 tests)

**Step 5: Commit**

```bash
git add pytimer/timer.py tests/test_timer.py
git commit -m "feat: add CLI entry point with argparse"
```

---

### Task 7: Manual Integration Test

**Files:**
- None (manual testing)

**Step 1: Install in development mode**

```bash
pip install -e .
```

**Step 2: Test short timer**

```bash
pytimer 3
```

Expected: Counts down 3, 2, 1, 0, displays "Time's up!", beeps 3 times

**Step 3: Test with message**

```bash
pytimer 2 -m "Coffee break over!"
```

Expected: Counts down, then shows custom message

**Step 4: Test minute format**

```bash
pytimer 0:05
```

Expected: 5 second countdown

**Step 5: Commit any fixes if needed, otherwise proceed**

---

### Task 8: Add Error Handling for Invalid Input

**Files:**
- Modify: `pytimer/timer.py`
- Modify: `tests/test_timer.py`

**Step 1: Write the failing test for invalid input**

Append to `tests/test_timer.py`:

```python
import pytest


def test_parse_duration_invalid_format():
    with pytest.raises(ValueError):
        parse_duration("invalid")


def test_parse_duration_negative():
    with pytest.raises(ValueError):
        parse_duration("-5")
```

**Step 2: Run test to verify behavior**

Run: `python -m pytest tests/test_timer.py::test_parse_duration_invalid_format -v`
Expected: Might pass or fail depending on current error handling

**Step 3: Update implementation if needed**

Update `parse_duration` in `pytimer/timer.py`:

```python
def parse_duration(duration_str: str) -> int:
    """Parse duration string to seconds.

    Formats: "30" (seconds), "1:30" (min:sec), "1:05:30" (hr:min:sec)
    """
    try:
        parts = duration_str.split(":")
        if len(parts) == 1:
            seconds = int(parts[0])
        elif len(parts) == 2:
            minutes, seconds = int(parts[0]), int(parts[1])
            seconds = minutes * 60 + seconds
        elif len(parts) == 3:
            hours, minutes, secs = int(parts[0]), int(parts[1]), int(parts[2])
            seconds = hours * 3600 + minutes * 60 + secs
        else:
            raise ValueError(f"Invalid duration format: {duration_str}")

        if seconds < 0:
            raise ValueError("Duration cannot be negative")
        return seconds
    except ValueError as e:
        if "invalid literal" in str(e):
            raise ValueError(f"Invalid duration format: {duration_str}")
        raise
```

**Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_timer.py -v`
Expected: PASS (13 tests)

**Step 5: Commit**

```bash
git add pytimer/timer.py tests/test_timer.py
git commit -m "feat: add error handling for invalid duration input"
```

---

### Task 9: Final Cleanup and README

**Files:**
- Create: `README.md`

**Step 1: Create README**

Create file `README.md`:

```markdown
# pytimer

A simple command-line countdown timer.

## Installation

```bash
pip install -e .
```

## Usage

```bash
# Count down 30 seconds
pytimer 30

# Count down 5 minutes
pytimer 5:00

# Count down 1 hour 30 minutes
pytimer 1:30:00

# Custom message when done
pytimer 25:00 -m "Pomodoro complete!"
```

## Features

- Multiple duration formats (seconds, MM:SS, HH:MM:SS)
- Live countdown display
- Audio beep on completion
- Custom completion messages
```

**Step 2: Run all tests one final time**

```bash
python -m pytest tests/ -v
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage instructions"
```

---

## Summary

After completing all tasks, you will have:

1. A working `pytimer` CLI tool
2. Duration parsing supporting multiple formats
3. Live countdown display
4. System beep on completion
5. Custom message support
6. Full test coverage
7. Clean project structure

Total: ~9 tasks, ~45 bite-sized steps

---

## Execution Handoff

**Plan complete and saved to `docs/plans/2026-01-26-python-cli-timer.md`. Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
