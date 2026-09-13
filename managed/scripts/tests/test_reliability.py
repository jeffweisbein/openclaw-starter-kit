#!/usr/bin/env python3
"""Fixture-only integration tests. No real accounts, messages, runtime or private data."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
KIT = SCRIPTS.parents[1]
sys.path.insert(0, str(SCRIPTS))

def load(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod

rel = load('reliability_cli', SCRIPTS / 'reliability.py')
iso = load('isolation_cli', SCRIPTS / 'check-isolation.py')

class Fixtures(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / 'ops').mkdir()
        self.addCleanup(self.tmp.cleanup)

    def write(self, path, value):
        target = self.root / path; target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(value))
        return target

    def cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPTS / 'reliability.py'), *map(str,args)], capture_output=True, text=True)

    def test_memory_missing_and_ambiguous(self):
        self.assertTrue(rel.memory_check(self.root)[1])
        self.write('memory/day.md', {})
        self.assertFalse(rel.memory_check(self.root)[1])
        self.write('user/memory/topic.md', {})
        self.assertTrue(rel.memory_check(self.root)[1])

    def test_memory_custom_and_escape(self):
        self.write('ops/workspace.json', {'memoryRoot':'private-notes'})
        self.write('private-notes/day.md', {})
        self.assertFalse(rel.memory_check(self.root)[1])
        self.write('ops/workspace.json', {'memoryRoot':'../outside'})
        with self.assertRaises(ValueError): rel.memory_check(self.root)

    def test_snapshot_wal_restore_and_no_overwrite(self):
        source = self.root / 'source.db'; dest = self.root / 'snapshot.db'
        with sqlite3.connect(source) as db:
            db.execute('PRAGMA journal_mode=WAL'); db.execute('CREATE TABLE t(value TEXT)')
            db.execute("INSERT INTO t VALUES ('committed')"); db.commit()
            result = rel.snapshot(source, dest)
            self.assertEqual(result['status'], 'verified')
            with sqlite3.connect(dest) as copy:
                self.assertEqual(copy.execute('SELECT * FROM t').fetchall(), [('committed',)])
            self.assertEqual(dest.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(ValueError): rel.snapshot(source,dest)
            self.assertEqual(db.execute('SELECT count(*) FROM t').fetchone()[0],1)

    def test_snapshot_corrupt_source_no_false_artifact(self):
        source = self.root / 'bad.db'; source.write_text('not a database')
        dest = self.root / 'copy.db'
        with self.assertRaises(sqlite3.DatabaseError): rel.snapshot(source,dest)
        self.assertFalse(dest.exists())

    def evidence(self):
        return {'taskId':'test', 'revision':'abc', 'required':['tested'], 'evidence':[
            {'taskId':'test','revision':'abc','stage':'tested','status':'passed','reference':'fixture-log','observedAt':time.time()-10}]}

    def test_evidence_success_missing_and_failed_latest(self):
        e=self.evidence(); self.assertFalse(rel.evidence_check(e)[1])
        e['required'].append('runtime_verified'); self.assertTrue(rel.evidence_check(e)[1])
        e=self.evidence(); e['evidence'].append({**e['evidence'][0], 'status':'failed','observedAt':time.time()})
        self.assertTrue(rel.evidence_check(e)[1])

    def test_evidence_wrong_revision_stale_and_future(self):
        for field,value in [('revision','other'),('taskId','other'),('observedAt',0),('reference','')]:
            with self.subTest(field=field):
                e=self.evidence();e['evidence'][0][field]=value
                self.assertTrue(rel.evidence_check(e)[1])
        e=self.evidence();e['evidence'][0]['observedAt']=time.time()+3600
        with self.assertRaises(ValueError):rel.evidence_check(e)
        e=self.evidence(); e['required']=[]
        with self.assertRaises(ValueError):rel.evidence_check(e)

    def monitor_files(self):
        manifest=self.write('ops/jobs.json',{'outcomes':[{'job':'daily','artifact':'receipt.json','maxAgeH':1,'receiptStatusField':'status'}]})
        scheduler=self.write('scheduler.json',{'observedAt':time.time(),'jobs':[{'job':'daily','enabled':True,'status':'ok'}]})
        return manifest,scheduler

    def test_monitor_disabled_failed_stale_and_unknown(self):
        m,s=self.monitor_files()
        self.assertIn('missing',rel.monitor(self.root,m,s)['states']['daily'])
        self.write('receipt.json',{'status':'ok'})
        self.assertEqual(rel.monitor(self.root,m,s)['states']['daily'],['ok'])
        self.write('receipt.json',{'status':'failed'})
        self.assertIn('outcome_failed',rel.monitor(self.root,m,s)['states']['daily'])
        os.utime(self.root/'receipt.json',(0,0))
        self.assertIn('stale',rel.monitor(self.root,m,s)['states']['daily'])
        self.write('scheduler.json',{'observedAt':time.time(),'jobs':[{'job':'daily','enabled':False,'status':'error'}]})
        states=rel.monitor(self.root,m,s)['states']['daily']
        self.assertIn('scheduler_disabled',states);self.assertIn('scheduler_failed_or_unknown',states)
        self.assertIn('scheduler_unknown',rel.monitor(self.root,m,None)['states']['daily'])

    def test_monitor_ack_recovery_and_no_ack_retries(self):
        m,s=self.monitor_files();state=self.root/'state.json';report=self.root/'report.json'
        args=['monitor','--workspace',self.root,'--manifest',m,'--scheduler',s,'--state',state,'--report',report]
        first=self.cli(*args);self.assertEqual(first.returncode,0);self.assertTrue(first.stdout)
        self.assertTrue(self.cli(*args).stdout) # no delivery acknowledgment: do not suppress
        self.assertEqual(self.cli('ack','--state',state,'--report',report).returncode,0)
        self.assertEqual(self.cli(*args).stdout,'')
        self.write('receipt.json',{'status':'ok'})
        self.assertTrue(self.cli(*args).stdout) # recovery notification
        self.assertEqual(self.cli('ack','--state',state,'--report',report).returncode,0)
        self.assertEqual(self.cli(*args).stdout,'')

    def test_monitor_stale_ack_and_corrupt_state_fail_closed(self):
        report=self.write('report.json',{'states':{'job':['ok']},'fingerprint':rel.digest({'job':['ok']}),'observedAt':1})
        state=self.write('state.json',{'observedAt':2})
        self.assertEqual(self.cli('ack','--state',state,'--report',report).returncode,2)
        m,s=self.monitor_files();state.write_text('broken')
        self.assertEqual(self.cli('monitor','--workspace',self.root,'--manifest',m,'--scheduler',s,'--state',state,'--report',report).returncode,2)

    def test_monitor_stale_export_and_bad_manifest(self):
        m,s=self.monitor_files();self.write('scheduler.json',{'observedAt':0,'jobs':[]})
        with self.assertRaises(ValueError):rel.monitor(self.root,m,s)
        self.write('ops/jobs.json',{'outcomes':[]})
        with self.assertRaises(ValueError):rel.monitor(self.root,m,None)

    def test_isolation_rejects_unsafe_policy(self):
        info={'HostConfig':{'NetworkMode':'none','ReadonlyRootfs':True,'CapDrop':['ALL'],'SecurityOpt':['no-new-privileges:true']},'Mounts':[{'Destination':'/workspace','RW':True}]}
        self.assertEqual(iso.validate(info,'/workspace',[]),[])
        for key,value in [('NetworkMode','host'),('ReadonlyRootfs',False),('Privileged',True),('CapAdd',['SYS_ADMIN']),('SecurityOpt',[])]:
            with self.subTest(key=key):
                bad=json.loads(json.dumps(info));bad['HostConfig'][key]=value
                self.assertTrue(iso.validate(bad,'/workspace',[]))
        info['Mounts'].append({'Destination':'/var/run/docker.sock','RW':True})
        self.assertTrue(iso.validate(info,'/workspace',[]))

class GitBackup(unittest.TestCase):
    write = Fixtures.write
    def setUp(self):
        Fixtures.setUp(self)
        self.git('init','-b','main');self.git('config','user.name','Fixture');self.git('config','user.email','fixture@example.invalid')
        (self.root/'chosen.md').write_text('first');self.git('add','chosen.md');self.git('commit','-m','seed')
        remote=self.root/'remote.git';subprocess.run(['git','init','--bare',str(remote)],capture_output=True,check=True)
        self.git('remote','add','origin',str(remote))
        self.write('ops/backup.json',{'reviewedPrivateRemote':True,'files':['chosen.md']})
        self.remote=remote

    def git(self,*args):
        return subprocess.run(['git','-C',str(self.root),*args],capture_output=True,text=True,check=True).stdout

    def backup(self):
        return subprocess.run([sys.executable,str(SCRIPTS/'backup-workspace.py'),'--workspace',str(self.root)],capture_output=True,text=True)

    def test_selected_files_only_and_idle_receipt(self):
        (self.root/'chosen.md').write_text('changed');(self.root/'private.txt').write_text('not selected')
        self.assertEqual(self.backup().returncode,0)
        self.assertEqual(self.git('show','HEAD:chosen.md').strip(),'changed')
        self.assertNotIn('private.txt',self.git('ls-files'))
        self.assertTrue((self.root/'state/last-backup.json').exists())
        self.assertEqual(self.backup().returncode,0)

    def test_push_failure_then_retry_without_new_commit(self):
        self.git('remote','set-url','origin',str(self.root/'missing.git'))
        (self.root/'chosen.md').write_text('changed')
        result=self.backup();self.assertNotEqual(result.returncode,0);self.assertNotIn('BACKUP_OK',result.stdout)
        self.assertFalse((self.root/'state/last-backup.json').exists())
        commit=self.git('rev-parse','HEAD')
        self.git('remote','set-url','origin',str(self.remote))
        self.assertEqual(self.backup().returncode,0)
        self.assertEqual(self.git('rev-parse','HEAD'),commit)

    def test_preserve_existing_staged_work(self):
        (self.root/'private.txt').write_text('staged');self.git('add','private.txt')
        self.assertNotEqual(self.backup().returncode,0)
        self.assertEqual(self.git('diff','--cached','--name-only').strip(),'private.txt')

    def test_unconfigured_symlink_and_dotenv_refused(self):
        for files in [['.env'],['ops'],['../outside']]:
            with self.subTest(files=files):
                (self.root/'.env').write_text('fixture')
                self.write('ops/backup.json',{'reviewedPrivateRemote':True,'files':files})
                self.assertNotEqual(self.backup().returncode,0)
        (self.root/'link.md').symlink_to(self.root/'chosen.md')
        self.write('ops/backup.json',{'reviewedPrivateRemote':True,'files':['link.md']})
        self.assertNotEqual(self.backup().returncode,0)
        self.write('ops/backup.json',{'reviewedPrivateRemote':False,'files':['chosen.md']})
        self.assertNotEqual(self.backup().returncode,0)

class Upgrade(unittest.TestCase):
    setUp = Fixtures.setUp
    def test_v25_upgrade_preserves_local_and_private_files(self):
        # Export public v2.5 tracked files, then run the real sync against this candidate.
        archive=subprocess.run(['git','-C',str(KIT),'archive','ebb8efdf'],capture_output=True,check=True).stdout
        subprocess.run(['tar','-x','-C',str(self.root)],input=archive,check=True)
        protected={'user/USER.md':'private preference','layers/example/notes.md':'organization note',
                   'managed/TOOLS.md':'local customization'}
        for path,content in protected.items():
            p=self.root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(content)
        before={p:(self.root/p).read_bytes() for p in protected}
        cmd=['bash',str(SCRIPTS/'kit-sync.sh'),'--workspace',str(self.root),'--kit',str(KIT)]
        run=subprocess.run([*cmd,'--dry-run'],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stderr)
        self.assertFalse((self.root/'.kit-baseline').exists())
        run=subprocess.run([*cmd,'--yes'],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stderr)
        for p,content in before.items():self.assertEqual((self.root/p).read_bytes(),content)
        self.assertTrue((self.root/'managed/scripts/reliability.py').exists())
        self.assertEqual((self.root/'managed/VERSION').read_text(),(KIT/'managed/VERSION').read_text())
        self.assertTrue((self.root/'.kit-backups').is_dir())

if __name__=='__main__':unittest.main()
