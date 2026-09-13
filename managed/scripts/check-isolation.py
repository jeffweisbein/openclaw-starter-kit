#!/usr/bin/env python3
"""Check an existing Docker/Colima builder; never creates containers or changes context."""
import argparse
import json
from pathlib import PurePosixPath
import subprocess
import sys


def validate(info, workspace, readonly):
    errors = []
    host = info['HostConfig']
    if host.get('NetworkMode') != 'none': errors.append('network is not none')
    if host.get('ReadonlyRootfs') is not True: errors.append('root filesystem is writable')
    if host.get('Privileged'): errors.append('privileged container')
    if host.get('CapAdd'): errors.append('added capabilities')
    if 'ALL' not in [x.upper() for x in host.get('CapDrop') or []]: errors.append('capabilities not fully dropped')
    if not any(x in ('no-new-privileges', 'no-new-privileges:true') for x in host.get('SecurityOpt') or []): errors.append('no-new-privileges missing')
    if host.get('PidMode') == 'host' or host.get('IpcMode') == 'host' or host.get('Devices'): errors.append('host namespaces or devices exposed')
    mounts = info.get('Mounts', [])
    if not any(m['Destination'] == workspace and m['RW'] for m in mounts): errors.append('task workspace mount missing')
    for m in mounts:
        if m['Destination'] == workspace: continue
        if m['Destination'] not in readonly or m['RW']: errors.append('unexpected mount')
    return errors


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--context', required=True)
    p.add_argument('--container', required=True)
    p.add_argument('--task-path', default='/workspace')
    p.add_argument('--allow-readonly', action='append', default=[])
    args = p.parse_args()
    if not PurePosixPath(args.task_path).is_absolute() or args.task_path == '/':
        raise ValueError('explicit absolute task path required')
    base = ['docker', '--context', args.context]
    def run(*argv):
        return subprocess.run([*base, *argv], capture_output=True, text=True, timeout=30, check=True).stdout
    info = json.loads(run('inspect', '--type', 'container', args.container))[0]
    errors = validate(info, args.task_path, args.allow_readonly)
    # Refuse to run write probes unless container policy passed first.
    if not errors:
        if run('exec', args.container, 'id', '-u').strip() == '0': errors.append('root user')
        run('exec', args.container, 'sh', '-ec', 'test ! -S /var/run/docker.sock')
        run('exec', '-w', args.task_path, args.container, 'sh', '-ec',
            'p=$(mktemp ./kit-probe.XXXXXX); trap \'rm -f "$p"\' EXIT; printf probe > "$p"; test "$(cat "$p")" = probe')
    print(json.dumps({'status': 'failed' if errors else 'passed', 'problems': errors,
                      'limit': 'inspect and task-write checks; does not prove runtime routing, arbitrary network reachability or VM escape resistance'}))
    return bool(errors)


if __name__ == '__main__':
    try: sys.exit(main())
    except Exception as error:
        print(json.dumps({'status': 'error', 'kind': type(error).__name__}))
        sys.exit(2)
