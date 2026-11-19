"""Exercise the bundled Cardinal engine, not a mock or Spotlight fallback."""
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time

engine = Path(sys.argv[1]).resolve()
base = Path(sys.argv[2]).resolve()
base.mkdir(parents=True, exist_ok=True)
checks = 0

def check(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1

with tempfile.TemporaryDirectory(prefix="cardinal-integration-", dir=base) as temporary:
    temporary = Path(temporary)
    root = temporary / "corpus with spaces"
    root.mkdir()
    (root / "资料").mkdir()
    (root / "资料" / "项目报告.pdf").write_text("fixture", encoding="utf-8")
    (root / "Budget.xlsx").write_text("fixture", encoding="utf-8")
    (root / "readme.txt").write_text("a unique lunar_archipelago marker", encoding="utf-8")
    (root / ".hidden.txt").write_text("fixture", encoding="utf-8")
    (root / "image.PNG").write_text("fixture", encoding="utf-8")
    for index in range(320):
        (root / f"bounded-{index:03}.txt").write_text("fixture", encoding="utf-8")
    cache = temporary / "cache" / "index.zstd"

    def start():
        process = subprocess.Popen([str(engine), str(root), str(cache)], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        events = queue.Queue()
        def read():
            for line in process.stdout:
                try:
                    events.put(json.loads(line))
                except ValueError:
                    events.put({"event": "invalid", "line": line})
        threading.Thread(target=read, daemon=True).start()
        return process, events

    def wait(events, predicate, timeout=25):
        deadline = time.monotonic() + timeout
        seen = []
        while time.monotonic() < deadline:
            try:
                event = events.get(timeout=max(0.01, deadline-time.monotonic()))
            except queue.Empty:
                break
            seen.append(event)
            if event.get("event") == "error":
                raise AssertionError(event)
            if predicate(event):
                return event
        raise AssertionError(f"Engine timed out, recent events: {seen[-8:]}")

    def send(process, identity, query, **options):
        process.stdin.write(json.dumps({"id": identity, "query": query, **options}, ensure_ascii=False) + "\n")
        process.stdin.flush()

    process, events = start()
    try:
        ready = wait(events, lambda event: event["event"] == "ready")
        check(ready["count"] >= 326 and not ready["restored"], "Real index did not include fixture tree")
        send(process, 1, "报告 ext:pdf")
        result = wait(events, lambda event: event.get("id") == 1)
        check(result["total"] == 1 and result["rows"][0]["path"].endswith("项目报告.pdf"), "Unicode/type query failed")
        send(process, 2, "ext:png")
        result = wait(events, lambda event: event.get("id") == 2)
        check(result["total"] == 1, "Case-insensitive extension search failed")
        send(process, 3, "folder: 资料")
        result = wait(events, lambda event: event.get("id") == 3)
        check(result["total"] == 1 and result["rows"][0]["directory"], "Folder filter failed")
        send(process, 4, "hidden")
        result = wait(events, lambda event: event.get("id") == 4)
        check(result["total"] == 0, "Hidden entries leaked into normal results")
        send(process, 5, "hidden", hidden=True)
        result = wait(events, lambda event: event.get("id") == 5)
        check(result["total"] == 1, "Hidden toggle did not reach the engine")
        send(process, 6, 'content:"lunar_archipelago" ext:txt')
        result = wait(events, lambda event: event.get("id") == 6)
        check(result["total"] == 1 and result["rows"][0]["path"].endswith("readme.txt"), "On-demand text content query failed")
        send(process, 7, "bounded", limit=20)
        result = wait(events, lambda event: event.get("id") == 7)
        check(result["total"] == 320 and len(result["rows"]) == 20, "Result cap confused total with displayed matches")
        check(all(row["size"] is not None and row["modified"] is not None for row in result["rows"]), "Result metadata missing")
        send(process, 8, "(")
        result = wait(events, lambda event: event.get("id") == 8)
        check(result["event"] == "queryError", "Invalid query was silently treated as no matches")
        send(process, 9, "bounded")
        send(process, 10, "", cancel=True)
        send(process, 11, "Budget")
        result = wait(events, lambda event: event.get("id") == 11)
        check(result["total"] == 1 and result["rows"][0]["path"].endswith("Budget.xlsx"), "Latest query did not remain usable after cancellation")
        new_file = root / "realtime-new.txt"
        new_file.write_text("fixture", encoding="utf-8")
        if ready.get("watching"):
            wait(events, lambda event: event["event"] == "updated")
        else:
            print("FSEvents unavailable in this execution sandbox; verifying explicit index refresh instead")
            send(process, 99, "", refresh=True)
            wait(events, lambda event: event["event"] == "ready")
        # FSEvents may deliver an earlier metadata event first; poll until this change is incorporated.
        deadline = time.monotonic() + 12
        identity = 100
        while True:
            send(process, identity, "realtime-new")
            result = wait(events, lambda event: event.get("id") == identity)
            if result["total"] == 1:
                break
            if time.monotonic() > deadline:
                raise AssertionError("FSEvents did not index newly created file")
            identity += 1
            time.sleep(0.15)
        check(True, "New file reconciled")
        new_file.unlink()
        if not ready.get("watching"):
            send(process, 199, "", refresh=True)
            wait(events, lambda event: event["event"] == "ready")
        deadline = time.monotonic() + 12
        while True:
            identity += 1
            send(process, identity, "realtime-new")
            result = wait(events, lambda event: event.get("id") == identity)
            if result["total"] == 0:
                break
            if time.monotonic() > deadline:
                raise AssertionError("FSEvents did not remove a deleted file")
            time.sleep(0.15)
        check(True, "Deleted file reconciled")
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=5)
    check(cache.exists(), "Index cache was not persisted")
    process, events = start()
    try:
        ready = wait(events, lambda event: event["event"] == "ready")
        check(ready["restored"], "Restart did not reuse persistent Cardinal cache")
        send(process, 500, "Budget")
        result = wait(events, lambda event: event.get("id") == 500)
        check(result["total"] == 1, "Restored index could not search")
    finally:
        process.stdin.close()
        process.wait(timeout=8)
print(f"Passed {checks} real Cardinal integration checks")
