#!/usr/bin/env python3
"""Headless check of a project's F5 debug setup, the way VS Code runs it.

Runs the launch config's preLaunchTask command, then drives the C++ extension's
debug adapter (OpenDebugAD7) over the Debug Adapter Protocol: set a breakpoint,
launch, check it stops and variables are readable, step, continue, check exit code.

usage: python3 -I tools/test-f5.py <project-dir> [file:line]
       (default breakpoint: the line after rte_eal_init in src/main.c)
"""
import glob, json, os, queue, re, subprocess, sys, threading, time

ws = os.path.abspath(sys.argv[1])
home = os.environ["HOME"]


def jsonc(path):
    return json.loads(re.sub(r"^\s*//.*$", "", open(path).read(), flags=re.M))


def subst(obj):
    s = json.dumps(obj).replace("${workspaceFolder}", ws).replace("${env:HOME}", home)
    return json.loads(s)


if len(sys.argv) > 2:
    bp_file, bp_line = sys.argv[2].rsplit(":", 1)
    bp_file, bp_line = os.path.join(ws, bp_file), int(bp_line)
else:
    bp_file = os.path.join(ws, "src/main.c")
    lines = open(bp_file).read().splitlines()
    bp_line = next(i for i, l in enumerate(lines, 1) if "rte_eal_init" in l) + 1

cfg = subst(jsonc(os.path.join(ws, ".vscode/launch.json"))["configurations"][0])
task_label = cfg.pop("preLaunchTask", None)
if task_label:
    tasks = jsonc(os.path.join(ws, ".vscode/tasks.json"))["tasks"]
    cmd = next(t["command"] for t in tasks if t["label"] == task_label)
    r = subprocess.run(["bash", "-c", cmd], cwd=ws, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"FAIL preLaunchTask '{task_label}':\n{r.stdout}{r.stderr}")
    print(f"ok   preLaunchTask '{task_label}'")

adapters = sorted(glob.glob(f"{home}/.vscode/extensions/ms-vscode.cpptools-*/debugAdapters/bin/OpenDebugAD7"))
if not adapters:
    sys.exit("FAIL C++ extension (ms-vscode.cpptools) debug adapter not found")
p = subprocess.Popen([adapters[-1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

msgs, backlog, output = queue.Queue(), [], []


def reader():
    while True:
        hdr = b""
        while not hdr.endswith(b"\r\n\r\n"):
            c = p.stdout.read(1)
            if not c:
                return
            hdr += c
        n = int(re.search(rb"Content-Length: (\d+)", hdr).group(1))
        msgs.put(json.loads(p.stdout.read(n)))


threading.Thread(target=reader, daemon=True).start()
seq = 0


def send(cmd, args=None):
    global seq
    seq += 1
    body = json.dumps({"seq": seq, "type": "request", "command": cmd, "arguments": args or {}}).encode()
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    p.stdin.flush()
    return seq


def fail(msg):
    p.kill()
    sys.exit("FAIL " + msg + "\nprogram output:\n" + "".join(output)[-2000:])


def wait(pred, what, timeout=60, required=True):
    # Messages can arrive in any order (e.g. the launch response before 'initialized'),
    # so keep unmatched responses/events instead of dropping them.
    for m in backlog:
        if pred(m):
            backlog.remove(m)
            return m
    deadline = time.time() + timeout
    while True:
        try:
            m = msgs.get(timeout=max(0.1, deadline - time.time()))
        except queue.Empty:
            if not required:
                return None
            fail(f"timeout waiting for {what}")
        if m.get("event") == "output":
            output.append(m["body"].get("output", ""))
        if pred(m):
            return m
        if m.get("type") == "response" or m.get("event") in ("stopped", "exited", "terminated"):
            backlog.append(m)


def request(cmd, args=None):
    s = send(cmd, args)
    r = wait(lambda m: m.get("type") == "response" and m.get("request_seq") == s, cmd)
    if not r.get("success"):
        fail(f"{cmd}: {r.get('message')}")
    return r.get("body", {})


request("initialize", {"adapterID": "cppdbg", "clientID": "vscode", "linesStartAt1": True,
                       "columnsStartAt1": True, "pathFormat": "path"})
launch = send("launch", cfg)
wait(lambda m: m.get("event") == "initialized", "initialized")
bp = request("setBreakpoints", {"source": {"path": bp_file}, "breakpoints": [{"line": bp_line}]})["breakpoints"][0]
if not bp.get("verified"):
    fail(f"breakpoint {bp_file}:{bp_line} not verified")
request("configurationDone")
wait(lambda m: m.get("type") == "response" and m.get("request_seq") == launch, "launch response")

stop = wait(lambda m: m.get("event") == "stopped", "breakpoint hit")
tid = stop["body"]["threadId"]
frame = request("stackTrace", {"threadId": tid})["stackFrames"][0]
print(f"ok   stopped at {os.path.basename(frame['source']['path'])}:{frame['line']} in {frame['name']}")
argc = request("evaluate", {"expression": "argc", "frameId": frame["id"], "context": "watch"})["result"]
print(f"ok   variables readable (argc = {argc})")
request("next", {"threadId": tid})
wait(lambda m: m.get("event") == "stopped", "step")
print(f"ok   step (now line {request('stackTrace', {'threadId': tid})['stackFrames'][0]['line']})")
request("setBreakpoints", {"source": {"path": bp_file}, "breakpoints": []})
request("continue", {"threadId": tid})
code = wait(lambda m: m.get("event") == "exited", "program exit")["body"]["exitCode"]
# Program output can still arrive after the 'exited' event; collect it until 'terminated'
wait(lambda m: m.get("event") == "terminated", "terminated", timeout=5, required=False)
send("disconnect", {"terminateDebuggee": True})
time.sleep(0.5)
p.kill()

out = "".join(output)
if code != 0 or re.search(r"DevX create TIS failed|cannot be used", out):
    fail(f"program exited with code {code}")
# not anchored: the adapter can glue its own text in front of the first program line
ports = re.findall(r"port \d+: \S+", out)
print(f"ok   program exited 0" + (f"; {len(ports)} port(s) probed" if ports else ""))
print("PASS F5 debug setup works")
