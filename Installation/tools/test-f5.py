#!/usr/bin/env python3
"""Headless check of a project's F5 debug setup, the way VS Code runs it.

Runs the launch config's preLaunchTask command, then drives the C++ extension's
debug adapter (OpenDebugAD7) over the Debug Adapter Protocol: set a breakpoint,
launch, check it stops and variables are readable, step, continue, check exit code.

usage: python3 -I tools/test-f5.py <project-dir> [file:line]
       (default breakpoint: the line after rte_eal_init in src/main.c)
"""
import glob, json, os, queue, re, subprocess, sys, threading, time

HOME = os.environ["HOME"]


class DapClient:
    """A minimal Debug Adapter Protocol client for one OpenDebugAD7 session."""

    def __init__(self, adapter):
        """Start the adapter process and a thread that reads its messages."""
        self.proc = subprocess.Popen([adapter], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.msgs, self.backlog, self.output, self.seq = queue.Queue(), [], [], 0
        threading.Thread(target=self._read_loop, daemon=True).start()

    def _read_loop(self):
        """Parse Content-Length framed messages from the adapter into the queue."""
        while True:
            hdr = b""
            while not hdr.endswith(b"\r\n\r\n"):
                c = self.proc.stdout.read(1)
                if not c:
                    return
                hdr += c
            n = int(re.search(rb"Content-Length: (\d+)", hdr).group(1))
            self.msgs.put(json.loads(self.proc.stdout.read(n)))

    def send(self, cmd, args=None):
        """Send a request and return its sequence number."""
        self.seq += 1
        body = json.dumps({"seq": self.seq, "type": "request", "command": cmd, "arguments": args or {}}).encode()
        self.proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.proc.stdin.flush()
        return self.seq

    def fail(self, msg):
        """Stop the adapter and exit with a FAIL line plus the program's recent output."""
        self.proc.kill()
        sys.exit("FAIL " + msg + "\nprogram output:\n" + "".join(self.output)[-2000:])

    def wait(self, pred, what, timeout=60, required=True):
        """Return the next message matching pred, failing (or returning None) on timeout.

        Messages arrive in any order (e.g. the launch response before 'initialized'),
        so unmatched responses and events are kept in a backlog instead of dropped.
        """
        for m in self.backlog:
            if pred(m):
                self.backlog.remove(m)
                return m
        deadline = time.time() + timeout
        while True:
            try:
                m = self.msgs.get(timeout=max(0.1, deadline - time.time()))
            except queue.Empty:
                if not required:
                    return None
                self.fail(f"timeout waiting for {what}")
            if m.get("event") == "output":
                self.output.append(m["body"].get("output", ""))
            if pred(m):
                return m
            if m.get("type") == "response" or m.get("event") in ("stopped", "exited", "terminated"):
                self.backlog.append(m)

    def request(self, cmd, args=None):
        """Send a request, wait for its response, and return the response body."""
        s = self.send(cmd, args)
        r = self.wait(lambda m: m.get("type") == "response" and m.get("request_seq") == s, cmd)
        if not r.get("success"):
            self.fail(f"{cmd}: {r.get('message')}")
        return r.get("body", {})

    def stop(self):
        """Disconnect, terminating the program, and stop the adapter."""
        self.send("disconnect", {"terminateDebuggee": True})
        time.sleep(0.5)
        self.proc.kill()


def load_jsonc(path):
    """Load a VS Code JSON-with-comments file (whole-line // comments)."""
    return json.loads(re.sub(r"^\s*//.*$", "", open(path).read(), flags=re.M))


def load_launch_config(ws):
    """Return the project's first launch configuration with VS Code variables expanded."""
    cfg = load_jsonc(os.path.join(ws, ".vscode/launch.json"))["configurations"][0]
    text = json.dumps(cfg).replace("${workspaceFolder}", ws).replace("${env:HOME}", HOME)
    return json.loads(text)


def run_prelaunch_task(ws, cfg):
    """Run the config's preLaunchTask command like VS Code does, and remove it from cfg."""
    label = cfg.pop("preLaunchTask", None)
    if not label:
        return
    tasks = load_jsonc(os.path.join(ws, ".vscode/tasks.json"))["tasks"]
    cmd = next(t["command"] for t in tasks if t["label"] == label)
    r = subprocess.run(["bash", "-c", cmd], cwd=ws, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"FAIL preLaunchTask '{label}':\n{r.stdout}{r.stderr}")
    print(f"ok   preLaunchTask '{label}'")


def find_adapter():
    """Return the newest installed cpptools OpenDebugAD7 path."""
    adapters = sorted(glob.glob(f"{HOME}/.vscode/extensions/ms-vscode.cpptools-*/debugAdapters/bin/OpenDebugAD7"))
    if not adapters:
        sys.exit("FAIL C++ extension (ms-vscode.cpptools) debug adapter not found")
    return adapters[-1]


def pick_breakpoint(ws, spec):
    """Return (file, line) from 'file:line', or the line after rte_eal_init in main.c."""
    if spec:
        f, line = spec.rsplit(":", 1)
        return os.path.join(ws, f), int(line)
    f = os.path.join(ws, "src/main.c")
    lines = open(f).read().splitlines()
    return f, next(i for i, l in enumerate(lines, 1) if "rte_eal_init" in l) + 1


def launch_to_breakpoint(dap, cfg, bp_file, bp_line):
    """Launch the program with one breakpoint set and return the stopped thread id."""
    dap.request("initialize", {"adapterID": "cppdbg", "clientID": "vscode", "linesStartAt1": True,
                               "columnsStartAt1": True, "pathFormat": "path"})
    launch = dap.send("launch", cfg)
    dap.wait(lambda m: m.get("event") == "initialized", "initialized")
    bp = dap.request("setBreakpoints", {"source": {"path": bp_file}, "breakpoints": [{"line": bp_line}]})
    if not bp["breakpoints"][0].get("verified"):
        dap.fail(f"breakpoint {bp_file}:{bp_line} not verified")
    dap.request("configurationDone")
    dap.wait(lambda m: m.get("type") == "response" and m.get("request_seq") == launch, "launch response")
    return dap.wait(lambda m: m.get("event") == "stopped", "breakpoint hit")["body"]["threadId"]


def check_paused_state(dap, tid):
    """Check the stop location, read a variable, and step one line."""
    frame = dap.request("stackTrace", {"threadId": tid})["stackFrames"][0]
    print(f"ok   stopped at {os.path.basename(frame['source']['path'])}:{frame['line']} in {frame['name']}")
    argc = dap.request("evaluate", {"expression": "argc", "frameId": frame["id"], "context": "watch"})["result"]
    print(f"ok   variables readable (argc = {argc})")
    dap.request("next", {"threadId": tid})
    dap.wait(lambda m: m.get("event") == "stopped", "step")
    print(f"ok   step (now line {dap.request('stackTrace', {'threadId': tid})['stackFrames'][0]['line']})")


def run_to_exit(dap, tid, bp_file):
    """Clear the breakpoint, continue to the end, and fail unless the program exited cleanly."""
    dap.request("setBreakpoints", {"source": {"path": bp_file}, "breakpoints": []})
    dap.request("continue", {"threadId": tid})
    code = dap.wait(lambda m: m.get("event") == "exited", "program exit")["body"]["exitCode"]
    # Program output can still arrive after 'exited'; collect it until 'terminated'
    dap.wait(lambda m: m.get("event") == "terminated", "terminated", timeout=5, required=False)
    out = "".join(dap.output)
    if code != 0 or re.search(r"DevX create TIS failed|cannot be used", out):
        dap.fail(f"program exited with code {code}")
    # Not anchored: the adapter can glue its own text in front of the first program line
    ports = re.findall(r"port \d+: \S+", out)
    print("ok   program exited 0" + (f"; {len(ports)} port(s) probed" if ports else ""))


def main():
    ws = os.path.abspath(sys.argv[1])
    cfg = load_launch_config(ws)
    run_prelaunch_task(ws, cfg)
    bp_file, bp_line = pick_breakpoint(ws, sys.argv[2] if len(sys.argv) > 2 else None)

    dap = DapClient(find_adapter())
    tid = launch_to_breakpoint(dap, cfg, bp_file, bp_line)
    check_paused_state(dap, tid)
    run_to_exit(dap, tid, bp_file)
    dap.stop()
    print("PASS F5 debug setup works")


if __name__ == "__main__":
    main()
