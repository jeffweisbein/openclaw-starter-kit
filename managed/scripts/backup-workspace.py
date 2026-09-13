#!/usr/bin/env python3
"""Opt-in Git backup. Explicit files only; failed pushes never refresh receipts."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from lib.reliability import atomic_json, locked, workspace


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workspace')
    args = p.parse_args()
    root = workspace(args.workspace)
    config = json.loads((root / 'ops/backup.json').read_text())
    if config.get('reviewedPrivateRemote') is not True:
        raise ValueError('review the remote visibility and repository history before opting in')
    files = config.get('files')
    if not isinstance(files, list) or not files or not all(isinstance(x, str) for x in files):
        raise ValueError('files must be an explicit nonempty list of regular files')
    for name in files:
        path = root / name
        if Path(name).is_absolute() or '..' in Path(name).parts or not path.is_file():
            raise ValueError('backup selection must contain existing workspace-relative files')
        if not path.resolve().is_relative_to(root) or any((root / Path(*Path(name).parts[:i])).is_symlink() for i in range(1, len(Path(name).parts) + 1)):
            raise ValueError('symlinks are not backup inputs')
        if any(part.startswith('.') or part.lower().endswith(('.key', '.pem', '.p12', '.sqlite', '.db')) for part in Path(name).parts):
            raise ValueError('hidden files, credentials and live databases are not Git backup inputs')
    remote = config.get('remote', 'origin')
    branch = config.get('branch', 'main')
    if not isinstance(remote, str) or not isinstance(branch, str) or remote.startswith('-') or branch.startswith('-'):
        raise ValueError('invalid remote or branch')

    def git(*argv):
        # Do not relay git stderr: remote URLs and hook output may contain secrets.
        result = subprocess.run(['git', '--literal-pathspecs', '-C', str(root), *argv], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError('Git operation failed; inspect locally (diagnostics withheld)')
        return result.stdout.strip()

    with locked(root / 'state/backup.lock'):
        if Path(git('rev-parse', '--show-toplevel')).resolve() != root:
            raise ValueError('workspace must be the repository root')
        if git('branch', '--show-current') != branch:
            raise ValueError('checkout is not on the configured backup branch')
        git('remote', 'get-url', remote)
        if git('diff', '--cached', '--name-only'):
            raise ValueError('existing staged changes: refusing to include or unstage user work')
        git('add', '--', *files)
        if git('diff', '--cached', '--name-only'):
            git('commit', '-m', 'backup: reviewed workspace files')
        # Always push, including a retry after a previous push failed after commit.
        git('push', remote, 'HEAD:refs/heads/' + branch)
        atomic_json(root / 'state/last-backup.json', {
            'status': 'ok', 'completedAt': time.time(), 'commit': git('rev-parse', 'HEAD'),
            'scope': 'selected Git files; not runtime/database recovery',
        })
    print('BACKUP_OK: selected files pushed; success receipt refreshed')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('BACKUP_FAILED: ' + (str(error) if isinstance(error, (ValueError, RuntimeError)) else type(error).__name__), file=sys.stderr)
        sys.exit(1)
