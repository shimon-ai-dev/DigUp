"""Pure report/math checks; native inference is intentionally only run on macOS."""
import importlib.util
import math
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('probe', Path(__file__).with_name('run_probe.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbeTests(unittest.TestCase):
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
