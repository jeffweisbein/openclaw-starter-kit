#!/usr/bin/env python3
"""Read-only diagnostics, acknowledgment-based monitoring and disposable recovery checks."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import time
from lib.reliability import atomic_json, locked, workspace


def read(path):
    return json.loads(Path(path).read_text())


def digest(states):
    return hashlib.sha256(json.dumps(states, sort_keys=True).encode()).hexdigest()


def memory_check(root):
    config = read(root / 'ops/workspace.json') if (root / 'ops/workspace.json').exists() else {}
    rel = config.get('memoryRoot', 'memory')
    target = (root / rel).resolve()
    if Path(rel).is_absolute() or not target.is_relative_to(root):
        raise ValueError('memoryRoot must remain within the workspace')
    populated = [str(p.relative_to(root)) for p in {root / 'memory', root / 'user/memory', target}
                 if p.is_dir() and any(x.is_file() for x in p.rglob('*'))]
    problems = []
    if not target.is_dir():
        problems.append('configured memory root missing')
    if len(populated) > 1:
        problems.append('multiple populated roots; reconcile before consolidation')
    return {'memoryRoot': str(target), 'populatedRoots': sorted(populated), 'problems': problems}, bool(problems)


def file_digest(path):
    checksum = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def snapshot(source, destination):
    source, destination = Path(source).resolve(), Path(destination).absolute()
    if not source.is_file() or destination.exists():
        raise ValueError('source must exist and destination must be new')
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Private per-database backup through SQLite, including committed WAL data.
    fd = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(fd)
    try:
        with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as live:
            with sqlite3.connect(destination) as copy:
                live.backup(copy)
                if copy.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
                    raise ValueError('snapshot integrity failure')
                with tempfile.TemporaryDirectory(prefix='kit-restore-') as tmp:
                    with sqlite3.connect(Path(tmp) / 'restored.sqlite') as restored:
                        copy.backup(restored)
                        if restored.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
                            raise ValueError('disposable restore integrity failure')
        return {'status': 'verified', 'sha256': file_digest(destination),
                'scope': 'single SQLite snapshot and disposable restore; not cross-database consistency or app recovery'}
    except Exception:
        destination.unlink(missing_ok=True)
        raise


def evidence_check(data):
    # This checks receipt structure/freshness, not whether an author told the truth.
    now = time.time()
    required = data['required']
    allowed = {'implemented', 'tested', 'deployed', 'runtime_verified', 'user_confirmed'}
    if not isinstance(required, list) or not required or not set(required) <= allowed:
        raise ValueError('explicit recognized required stages are mandatory')
    if not isinstance(data['taskId'], str) or not data['taskId'] or not isinstance(data['revision'], str) or not data['revision']:
        raise ValueError('taskId and revision are required')
    age = data.get('maxAgeHours', 24)
    if not isinstance(age, (int, float)) or not math.isfinite(age) or age <= 0:
        raise ValueError('maxAgeHours must be positive')
    latest = {}
    for item in data['evidence']:
        stamp = item['observedAt']
        if not isinstance(stamp, (int, float)) or not math.isfinite(stamp) or stamp > now + 60:
            raise ValueError('invalid evidence timestamp')
        if item['taskId'] != data['taskId'] or item['revision'] != data['revision']:
            continue
        stage = item['stage']
        if stage not in latest or stamp >= latest[stage]['observedAt']:
            latest[stage] = item
    missing = [s for s in required if s not in latest or latest[s]['status'] != 'passed'
               or not latest[s].get('reference') or now - latest[s]['observedAt'] > age * 3600]
    return {'status': 'blocked' if missing else 'evidence_present', 'missingOrFailed': missing,
            'limit': 'caller-supplied evidence; use runtime-enforced, independently verified proof for consequential actions'}, bool(missing)


def monitor(root, manifest, scheduler):
    data = read(manifest)
    entries = data['outcomes']
    if not isinstance(entries, list) or not entries:
        raise ValueError('nonempty outcomes required; unconfigured is not healthy')
    jobs = None
    if scheduler:
        export = read(scheduler)
        stamp = export['observedAt']
        if not isinstance(stamp, (int, float)) or not math.isfinite(stamp) or stamp > time.time() + 60 or time.time() - stamp > 3600:
            raise ValueError('scheduler export stale or invalid')
        jobs = {j['job']: j for j in export['jobs']}
        if len(jobs) != len(export['jobs']):
            raise ValueError('duplicate scheduler jobs')
    states = {}
    for e in entries:
        name = e['job']
        if not isinstance(name, str) or not name or name in states:
            raise ValueError('unique nonempty job names required')
        if e.get('disabled'):
            states[name] = ['monitoring_disabled']
            continue
        hours = e['maxAgeH']
        if not isinstance(hours, (int, float)) or not math.isfinite(hours) or hours <= 0:
            raise ValueError('maxAgeH must be positive')
        path = Path(e['artifact']).expanduser()
        path = path if path.is_absolute() else root / path
        state = []
        if not path.is_file():
            state.append('missing')
        elif path.stat().st_mtime > time.time() + 60:
            state.append('future_timestamp')
        elif time.time() - path.stat().st_mtime > hours * 3600:
            state.append('stale')
        elif e.get('receiptStatusField'):
            if read(path).get(e['receiptStatusField']) != 'ok':
                state.append('outcome_failed')
        if not e.get('noOpWritesReceipt', True):
            state.append('idle_receipt_unverified')
        if jobs is None:
            state.append('scheduler_unknown')
        elif name not in jobs:
            state.append('scheduler_missing')
        else:
            job = jobs[name]
            if not isinstance(job.get('enabled'), bool):
                raise ValueError('scheduler enabled must be boolean')
            if not job['enabled']:
                state.append('scheduler_disabled')
            if job.get('status') not in ('ok', 'idle'):
                state.append('scheduler_failed_or_unknown')
        states[name] = state or ['ok']
    return {'states': states, 'fingerprint': digest(states), 'observedAt': time.time()}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='action', required=True)
    m = sub.add_parser('memory-check'); m.add_argument('--workspace')
    s = sub.add_parser('sqlite-snapshot'); s.add_argument('--source', required=True); s.add_argument('--destination', required=True)
    e = sub.add_parser('evidence-check'); e.add_argument('--receipt', required=True)
    o = sub.add_parser('monitor'); o.add_argument('--workspace'); o.add_argument('--manifest', required=True); o.add_argument('--scheduler'); o.add_argument('--state', required=True); o.add_argument('--report', required=True)
    a = sub.add_parser('ack'); a.add_argument('--state', required=True); a.add_argument('--report', required=True)
    args = p.parse_args()
    failed = False
    if args.action == 'memory-check':
        result, failed = memory_check(workspace(args.workspace))
    elif args.action == 'sqlite-snapshot':
        result = snapshot(args.source, args.destination)
    elif args.action == 'evidence-check':
        result, failed = evidence_check(read(args.receipt))
    elif args.action == 'monitor':
        if Path(args.state).resolve() == Path(args.report).resolve():
            raise ValueError('report and acknowledged state must be different files')
        result = monitor(workspace(args.workspace), args.manifest, args.scheduler)
        previous = read(args.state) if Path(args.state).exists() else {}
        atomic_json(args.report, result)
        if previous.get('fingerprint') == result['fingerprint']:
            return 0
    else:
        result = read(args.report)
        if result['fingerprint'] != digest(result['states']):
            raise ValueError('report fingerprint mismatch')
        with locked(str(args.state) + '.lock'):
            previous = read(args.state) if Path(args.state).exists() else {}
            if previous.get('observedAt', 0) > result['observedAt']:
                raise ValueError('refusing stale acknowledgment')
            atomic_json(args.state, result)
        result = {'status': 'acknowledged'}
    print(json.dumps(result, sort_keys=True, allow_nan=False))
    return int(failed)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({'status': 'error', 'kind': type(error).__name__}), file=sys.stderr)
        sys.exit(2)
