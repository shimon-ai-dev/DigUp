"""Pure report/math checks; native inference is intentionally only run on macOS."""
import importlib.util
import math
from pathlib import Path
import struct
import json
import base64
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('probe', Path(__file__).with_name('run_probe.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbeTests(unittest.TestCase):
    def test_readonly_progress_reports_committed_file_and_vector_states(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'index.sqlite'
            db = sqlite3.connect(path)
            db.executescript("CREATE TABLE files(id INTEGER,path TEXT,state TEXT); CREATE TABLE segments(vec BLOB);"
                             "INSERT INTO files VALUES(1,'f001.wav','pending'); INSERT INTO files VALUES(2,'f002.wav','done');"
                             "INSERT INTO segments VALUES(X'00');")
            db.commit(); db.close()
            progress = probe.read_progress(path)
            self.assertEqual(progress['states'], {'done': 1, 'pending': 1})
            self.assertEqual(progress['vectors'], 1)
            self.assertEqual(progress['files'][0]['state'], 'pending')

    def test_timeout_retains_real_committed_database_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / 'manifest.json').write_text(json.dumps({'coverage': {}, 'fixtures': [], 'queries': []}))
            fake = output / 'tiny-cli'
            fake.write_text("#!/usr/bin/env python3\nimport sqlite3, sys, time\nfrom pathlib import Path\n"
                            "p=Path(sys.argv[sys.argv.index('--index')+1]);p.mkdir(parents=True,exist_ok=True)\n"
                            "db=sqlite3.connect(p/'index.sqlite')\n"
                            "db.executescript(\"CREATE TABLE files(id INTEGER,path TEXT,state TEXT);"
                            "CREATE TABLE segments(vec BLOB);INSERT INTO files VALUES(1,'f001.wav','done');"
                            "INSERT INTO segments VALUES(X'00');\")\n"
                            "db.commit();db.close();time.sleep(30)\n")
            fake.chmod(0o755)
            runner = probe.Probe(fake, output)
            with self.assertRaisesRegex(RuntimeError, 'partial database snapshot retained'):
                runner.command('bounded-test', ['index', 'unused', '--index', str(runner.index)], timeout=1)
            snapshot = output / 'snapshots' / 'bounded-test.sqlite'
            self.assertTrue(snapshot.exists())
            self.assertEqual(probe.read_progress(snapshot)['states'], {'done': 1})
            self.assertEqual(runner.report['phases'][-1]['status'], 'TIMEOUT')

    def test_worker_response_preserves_request_count_and_valid_vectors(self):
        one = [1.0] + [0.0] * 767
        response = {'ok': True, 'dim': 768, 'count': 2, 'errors': [None, None],
                    'vectors': base64.b64encode(struct.pack('<1536f', *(one + one))).decode()}
        self.assertEqual(probe.decode_response(response, 2), [one, one])
        with self.assertRaisesRegex(RuntimeError, 'Invalid worker vector response'):
            probe.decode_response(response, 1)
        response['errors'] = ['input failed', None]
        with self.assertRaisesRegex(RuntimeError, 'Invalid worker vector response'):
            probe.decode_response(response, 2)

    def test_half_vector_preserves_nonzero_norm(self):
        self.assertEqual(probe.decode_half(struct.pack('<3e', 0.5, -0.25, 0.0)), [0.5, -0.25, 0.0])

    def test_small_sample_cannot_clear_default_gate(self):
        for count in range(1, 5):
            z = probe.meaning([0.9] + [0.1] * (count - 1), ['audio'] * count)
            self.assertLess(max(z), 2)
        self.assertAlmostEqual(max(probe.meaning([0.9] + [0.1] * 3, ['audio'] * 4)), math.sqrt(3))

    def test_modality_means_only_split_at_twenty(self):
        scores = [0.8] * 20 + [0.2] * 20
        self.assertEqual(probe.meaning(scores, ['audio'] * 20 + ['image'] * 20), [0.0] * 40)
        self.assertNotEqual(probe.meaning([0.8, 0.2], ['audio', 'image']), [0.0, 0.0])

    def test_quality_rank_requires_correct_late_segment(self):
        hits = [{'path': '/f/f021.wav', 'segment': 'audio', 'loc': 0, 'loc_end': 30},
                {'path': '/f/f021.wav', 'segment': 'audio', 'loc': 50, 'loc_end': 80}]
        query = {'expect': ['f021.wav'], 'segment': 'audio', 'minimum_loc': 50, 'target_start': 65}
        self.assertEqual(probe.expected_rank(hits, query), 2)
        self.assertIsNone(probe.expected_rank(hits[:1], query))

    def test_report_has_distinct_raw_default_and_keyword_metrics(self):
        query = {'expect': ['f001.wav']}
        rows = [{'path': '/f/f001.wav', 'cosine': 0.8}]
        result = probe.quality(rows, [], [], query)
        self.assertEqual(result['raw_rank'], 1)
        self.assertIsNone(result['default_rank'])
        self.assertIsNone(result['keyword_rank'])
        self.assertEqual(result['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
