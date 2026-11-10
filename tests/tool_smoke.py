"""A few seconds to check process exits and watchdogs; no test framework."""

from contextlib import redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import godot


def main() -> None:
    started = time.monotonic()
    with tempfile.TemporaryDirectory() as directory:
        original = godot.LOG_DIR
        godot.LOG_DIR = Path(directory)
        try:
            with redirect_stdout(io.StringIO()):
                assert godot._run([sys.executable, "-c", "print('ok')"], "clean", timeout=2) == 0
                assert godot._run([sys.executable, "-c", "import sys; sys.exit(7)"], "exit", timeout=2) == 7
                error = "import time; print('SCRIPT ERROR: deliberate smoke',flush=True); time.sleep(10)"
                assert godot._run([sys.executable, "-u", "-c", error], "error", timeout=2) == 1
                assert godot._run([sys.executable, "-c", "import time; time.sleep(10)"], "timeout", timeout=.2) == 124
                assert "timed out" in next(Path(directory).glob("timeout-*.log")).read_text()
        finally:
            godot.LOG_DIR = original
    print(f"Tool smoke passed in {time.monotonic() - started:.3f}s")


if __name__ == "__main__":
    main()
