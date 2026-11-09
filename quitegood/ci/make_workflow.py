#!/usr/bin/env python3
"""Derive .github/workflows/quitegood-flutter-build.yml from upstream flutter-build.yml.

Keeps only the Windows x86_64 and macOS (x86_64 + aarch64) Flutter builds, injects the
Quitegood server key into quitegood/settings.json right after checkout, and drops every
other platform. Re-run after each upstream sync:  python3 quitegood/ci/make_workflow.py
Text-based on purpose (no YAML library needed) so upstream comments and layout survive.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / ".github/workflows/flutter-build.yml"
DST = ROOT / ".github/workflows/quitegood-flutter-build.yml"

KEEP = {"validate-update-metadata-keys", "generate-bridge", "build-RustDeskTempTopMostWindow",
        "build-for-windows-flutter", "build-for-macOS"}

INJECT = """      - name: Quitegood - inject server key
        shell: bash
        env:
          QG_SERVER_KEY: ${{ vars.QG_SERVER_KEY }}
        run: |
          # Optional override of the key committed in quitegood/settings.json (repository variable)
          if [ -n "$QG_SERVER_KEY" ]; then
            python3 -c "import json,os,pathlib;p=pathlib.Path('quitegood/settings.json');d=json.loads(p.read_text());d['override-settings']['key']=os.environ['QG_SERVER_KEY'].strip();p.write_text(json.dumps(d,indent=2))"
          fi
          if grep -q "__QG_SERVER_KEY__" quitegood/settings.json; then echo "::error::server key missing"; exit 1; fi
          python3 -c "import json;print('server key:', json.load(open('quitegood/settings.json'))['override-settings']['key'])"

"""

text = SRC.read_text()
lines = text.split("\n")
out, i, job = [], 0, None
jobs_started = False
while i < len(lines):
    l = lines[i]
    if l.startswith("jobs:"):
        jobs_started = True; out.append(l); i += 1; continue
    m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", l) if jobs_started else None
    if m:
        job = m.group(1)
        out.append(l)
        if job not in KEEP:
            out.append("    if: false  # quitegood: platform not built")
            # drop an existing job-level `if:` (YAML forbids duplicate keys)
            j = i + 1
            while j < len(lines) and not re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[j]):
                if re.match(r"^    if:", lines[j]):
                    lines[j] = "    # (upstream) " + lines[j].strip()
                j += 1
        i += 1; continue
    out.append(l)
    # inject after checkout in the two build jobs
    if job in ("build-for-windows-flutter", "build-for-macOS") and l.strip() == "submodules: recursive":
        out.append("")
        out.extend(INJECT.rstrip("\n").split("\n"))
    i += 1

res = "\n".join(out)
res = res.replace("name: Build the flutter version of the RustDesk",
                  "name: Quitegood - build Windows/macOS clients", 1)
# Windows: x86_64 only (drop the windows-11-arm matrix entry)
res, n = re.subn(r"\n          - \{\n              target: aarch64-pc-windows-msvc,.*?\n            \}", "",
                 res, count=1, flags=re.S)
assert n == 1, "windows arm64 matrix entry not found"
# publish_unsigned expects the sciter build: it is disabled anyway (if: false above)
assert res.count("Quitegood - inject server key") == 2, "checkout anchor changed upstream"
DST.write_text(res)
print("wrote", DST.relative_to(ROOT))
