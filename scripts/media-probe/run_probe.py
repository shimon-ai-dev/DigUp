#!/usr/bin/env python3
"""Opt-in, throwaway content diagnostic. The unmodified CLI's search results are authoritative."""
import argparse
import base64
from collections import Counter
from datetime import datetime, timezone
import json
import math
import os
import signal
from pathlib import Path
import sqlite3
import struct
import subprocess
import time


def now():
    return datetime.now(timezone.utc).isoformat()


def read_progress(path):
    if not path.exists():
        return {'status': 'DATABASE_NOT_CREATED'}
    with sqlite3.connect('file:' + str(path) + '?mode=ro', uri=True, timeout=1) as db:
        db.row_factory = sqlite3.Row
        return {'states': dict(db.execute('SELECT state,count(*) FROM files GROUP BY state')),
                'vectors': db.execute('SELECT count(*) FROM segments WHERE vec IS NOT NULL').fetchone()[0],
                'files': [dict(row) for row in db.execute('SELECT id,path,state FROM files ORDER BY id')]}


def decode_half(blob):
    return list(struct.unpack('<' + str(len(blob) // 2) + 'e', blob))


def meaning(scores, modalities):
    """Read-only diagnostic reproduction of Searcher.meaning, cross-checked with CLI z."""
    counts = Counter(modalities)
    total = sum(scores) / max(len(scores), 1)
    means = {kind: sum(s for s, k in zip(scores, modalities) if k == kind) / counts[kind]
             if counts[kind] >= 20 else total for kind in counts}
    centered = [s - means[k] for s, k in zip(scores, modalities)]
    average = sum(centered) / max(len(centered), 1)
    deviation = max(math.sqrt(sum((s - average) ** 2 for s in centered) / max(len(scores), 1)), 0.02)
    return [(s - average) / deviation for s in centered]


def expected_rank(hits, query):
    for rank, hit in enumerate(hits, 1):
        if not any(hit['path'].endswith('/' + name) or hit['path'] == name for name in query['expect']):
            continue
        if query.get('segment') and hit.get('segment') != query['segment']:
            continue
        if query.get('minimum_loc') is not None and (hit.get('loc') is None or hit['loc'] < query['minimum_loc']):
            continue
        if query.get('target_start') is not None and (hit.get('loc_end') is None or hit['loc_end'] <= query['target_start']):
            continue
        return rank
    return None


def quality(raw, default, keyword, query):
    raw_rank = expected_rank(raw, query)
    default_rank = expected_rank(default, query)
    keyword_rank = expected_rank(keyword, query)
    return {'raw_rank': raw_rank, 'default_rank': default_rank, 'keyword_rank': keyword_rank,
            'raw_top1': raw_rank == 1, 'raw_top5': raw_rank is not None and raw_rank <= 5,
            'default_top1': default_rank == 1, 'default_top5': default_rank is not None and default_rank <= 5,
            'status': 'PASS' if default_rank == 1 else 'FAIL'}


class Probe:
    def __init__(self, cli, output, budget_seconds=1320):
        self.deadline = time.monotonic() + budget_seconds
        self.cli = str(Path(cli).resolve())
        self.output = Path(output).resolve()
        self.manifest = json.loads((self.output / 'manifest.json').read_text())
        self.root = self.output / 'inputs'
        self.index = self.output / 'indices' / 'main'
        self.logs = self.output / 'logs'
        self.logs.mkdir(exist_ok=True)
        self.report = {'schema_version': 1, 'started_at': now(), 'status': 'RUNNING',
                       'source_sha': os.environ.get('GITHUB_SHA'), 'coverage': self.manifest['coverage'],
                       'fixtures': self.manifest['fixtures'], 'phases': [], 'queries': [], 'small_samples': [],
                       'progress': [], 'optional_errors': [], 'untested_queries': [], 'phase_audits': [],
                       'limitations': ['Generated TTS measures intelligible synthetic speech, not live microphone speech.',
                           'Synthetic rain-like noise and system alerts do not validate real-world environmental recordings.',
                           'Math-derived raw segment z is diagnostic; CLI wide/default search is authoritative.',
                           'Wide search still applies modality normalization, nonnegative z scores and kind hints.',
                           'Keyword-candidate-only search still computes vectors and semantic weights for keyword candidates.',
                           'Hosted VM reported unsupported Metal operations in the previous run; full-model ready does not prove an input completed.',
                           'No thresholds, model pins, application source, or user indexes are changed.']}
        self.save()

    def save(self):
        temporary = self.output / 'results.json.tmp'
        temporary.write_text(json.dumps(self.report, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
        temporary.replace(self.output / 'results.json')
        lines = ['DigUp multilingual media diagnostic', f"State: {self.report['status']}",
                 f"Source: {self.report['source_sha']}", '', 'Coverage:']
        lines.extend(f'- {k}: {v}' for k, v in self.report['coverage'].items())
        lines += ['', 'Observed retrieval (PASS requires expected default top-1 including requested location):']
        for q in self.report['queries']:
            if 'quality' in q:
                r = q['quality']
                lines.append(f"- {q['id']} [{q['language']}]: {r['status']}; raw rank={r['raw_rank']}, "
                             f"wide rank={r['wide_rank']}, default rank={r['default_rank']}, keyword-candidate rank={r['keyword_rank']}")
            else:
                lines.append(f"- {q['id']}: ERROR {q.get('error')}")
        lines += ['', 'Small isolated audio-vector samples:']
        lines.extend(f"- {s['vectors']} vectors, {s['language']}: wide={len(s.get('wide', []))}, "
                     f"default={len(s.get('default', []))}, max z={s.get('max_z')}" for s in self.report['small_samples'])
        lines += ['', 'Limits:'] + ['- ' + x for x in self.report['limitations']]
        if self.report.get('optional_errors'):
            lines += ['', 'Optional phases incomplete:'] + ['- ' + x for x in self.report['optional_errors']]
        if self.report.get('untested_queries'):
            lines += ['', 'Untested queries:'] + ['- ' + str(q) for q in self.report['untested_queries']]
        if self.report.get('infrastructure_errors'):
            lines += ['', 'Infrastructure errors:'] + ['- ' + x for x in self.report['infrastructure_errors']]
        (self.output / 'summary.txt').write_text('\n'.join(lines) + '\n')

    def snapshot(self, name):
        source_path = self.index / 'index.sqlite'
        if not source_path.exists():
            return
        snapshots = self.output / 'snapshots'
        snapshots.mkdir(exist_ok=True)
        source = sqlite3.connect('file:' + str(source_path) + '?mode=ro', uri=True, timeout=1)
        destination = sqlite3.connect(snapshots / (name + '.sqlite'))
        try:
            source.backup(destination)
        finally:
            destination.close(); source.close()

    def command(self, name, args, timeout=180, stdin=None):
        remaining = int(self.deadline - time.monotonic())
        if remaining <= 15:
            raise RuntimeError('Global probe time budget exhausted; remaining cases are UNTESTED')
        timeout = min(timeout, remaining - 10)
        started = now(); clock = time.monotonic()
        indexing = bool(args and args[0] == 'index')
        stdout_path = self.logs / (name + '.stdout.log')
        status = None
        print(f'{started} START {name}, budget={timeout}s', flush=True)
        with stdout_path.open('w') as output, (self.logs / (name + '.stderr.log')).open('w') as errors:
            process = subprocess.Popen([self.cli] + args, stdin=subprocess.PIPE if stdin else subprocess.DEVNULL,
                text=True, stdout=output, stderr=errors, start_new_session=True)
            if stdin:
                try:
                    process.stdin.write(stdin); process.stdin.close()
                except BrokenPipeError:
                    pass
            next_progress = 0
            while process.poll() is None:
                elapsed = time.monotonic() - clock
                if indexing and elapsed >= next_progress:
                    try:
                        progress = read_progress(self.index / 'index.sqlite')
                    except sqlite3.Error as error:
                        progress = {'read_error': str(error)}
                    entry = {'phase': name, 'at': now(), 'seconds': elapsed, **progress}
                    self.report['progress'].append(entry); self.save()
                    print(f'{entry["at"]} {name} {elapsed:.0f}s: states={progress.get("states")}, '
                          f'vectors={progress.get("vectors")}', flush=True)
                    next_progress = elapsed + 15
                if elapsed >= timeout:
                    status = 'TIMEOUT'
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=5)
                    break
                time.sleep(0.25)
            returncode = process.wait()
        self.report['phases'].append({'name': name, 'started_at': started, 'ended_at': now(),
            'seconds': time.monotonic() - clock, 'returncode': returncode, 'status': status or 'EXITED', 'args': args})
        if indexing:
            self.snapshot(name)
        self.save()
        print(f'{now()} END {name}, status={status or returncode}, seconds={time.monotonic()-clock:.1f}', flush=True)
        if status:
            raise RuntimeError(f'{name} exceeded {timeout}s; partial database snapshot retained')
        if returncode:
            raise RuntimeError(f'{name} exited {returncode}; see logs/{name}.stderr.log')
        return stdout_path.read_text()

    def search(self, query, mode, index=None, label=None):
        args = ['search', query['q'], '--index', str(index or self.index), '--json', '-n', '100']
        if query.get('kind'):
            args += ['--kind', query['kind']]
        if mode == 'wide':
            args += ['--zgate', '-1000000', '--word-weight', '0']
        elif mode == 'keyword':
            args += ['--zgate', '1000000']
        return json.loads(self.command((label or query['id']) + '-' + mode, args, timeout=120))

    def vector_rows(self):
        db = sqlite3.connect('file:' + str(self.index / 'index.sqlite') + '?mode=ro', uri=True)
        db.row_factory = sqlite3.Row
        files = [dict(row) for row in db.execute('SELECT id,path,kind,state,detail,info FROM files ORDER BY id')]
        rows = []
        for row in db.execute('SELECT s.id,s.file,f.path,f.kind AS file_kind,s.kind AS segment,s.modality,s.loc,s.loc_end,s.vec '
                              'FROM segments s JOIN files f ON f.id=s.file ORDER BY s.id'):
            item = dict(row)
            blob = item.pop('vec')
            item['vector_present'] = blob is not None
            item['vector_bytes'] = len(blob) if blob is not None else 0
            item['vector'] = decode_half(blob) if blob is not None and len(blob) == 1536 else None
            item['valid_vector'] = item['vector'] is not None and all(math.isfinite(v) for v in item['vector']) \
                and 0.95 <= math.sqrt(sum(v * v for v in item['vector'])) <= 1.05
            rows.append(item)
        ocr = [dict(row) for row in db.execute("SELECT f.path,fts.body,fts.original FROM fts JOIN segments s "
                    "ON s.id=fts.rowid JOIN files f ON f.id=s.file WHERE s.kind='ocr'")]
        db.close()
        self.report['indexed_files'] = files
        self.report['indexed_segments'] = [{k: v for k, v in row.items() if k != 'vector'} for row in rows]
        self.report['ocr'] = ocr
        self.report['vector_counts'] = dict(Counter(row['modality'] for row in rows if row['valid_vector']))
        self.save()
        return rows

    def query_vectors(self, queries, label):
        request = json.dumps({'id': 1, 'op': 'text', 'inputs': ['task: search result | query: ' + q['q'] for q in queries]},
                             ensure_ascii=False) + '\n' + '{"id":2,"op":"quit"}\n'
        messages = [json.loads(line) for line in self.command(label + '-query-vectors', ['worker', '--text-only'],
                                                             timeout=180, stdin=request).splitlines()]
        ready = next((m for m in messages if m.get('ready')), None)
        result = next((m for m in messages if m.get('id') == 1), {})
        if not ready or not result.get('ok') or result.get('dim') != 768 or result.get('count') != len(queries) \
                or any(result.get('errors', [])):
            raise RuntimeError(f'{label}: invalid worker response: {str(result)[:200]}')
        floats = struct.unpack('<' + str(768 * len(queries)) + 'f', base64.b64decode(result['vectors']))
        vectors = [list(floats[i * 768:(i + 1) * 768]) for i in range(len(queries))]
        if not all(all(math.isfinite(v) for v in vector) and 0.95 <= math.sqrt(sum(v*v for v in vector)) <= 1.05
                   for vector in vectors):
            raise RuntimeError('Invalid query vector norm/non-finite value')
        self.report['query_worker_info'] = ready['info']
        return vectors

    def evaluate(self, queries, rows, label, required=True):
        if not queries:
            return
        vectors = self.query_vectors(queries, label)
        valid = [row for row in rows if row['valid_vector']]
        for query, vector in zip(queries, vectors):
            result = dict(query)
            result['started_at'] = now()
            result['index_directory'] = str(self.index)
            try:
                scores = [sum(a*b for a, b in zip(row['vector'], vector)) for row in valid]
                z = meaning(scores, [row['modality'] for row in valid])
                raw = [{**{k: v for k, v in row.items() if k != 'vector'}, 'cosine': score, 'diagnostic_z': stand}
                       for row, score, stand in zip(valid, scores, z)]
                # All fixture docs are short; no later long-document vectors are present, so all rows set the scale.
                result['raw_segments'] = sorted(raw, key=lambda r: (-r['cosine'], r['id']))
                filtered = [r for r in result['raw_segments'] if not query.get('kind') or r['file_kind'] == query['kind']]
                raw_files, seen = [], set()
                for row in filtered:
                    if row['path'] not in seen:
                        raw_files.append(row)
                        seen.add(row['path'])
                wide = self.search(query, 'wide')
                default = self.search(query, 'default')
                keyword = self.search(query, 'keyword')
                result.update(wide=wide, default=default, keyword_candidate_only=keyword,
                              raw_files=raw_files, query_vector_valid=True)
                result['quality'] = quality(raw_files, default, keyword, query)
                result['quality']['wide_rank'] = expected_rank(wide, query)
                differences = []
                for hit in wide:
                    candidates = [r for r in raw if r['path'] == hit['path']]
                    if candidates and hit.get('cosine') is not None:
                        best = max(candidates, key=lambda r: r['diagnostic_z'])
                        differences.append({'path': hit['path'], 'cosine_delta': abs(hit['cosine'] - best['cosine']),
                                            'z_delta': abs(hit['z'] - best['diagnostic_z'])})
                result['cli_math_crosscheck'] = differences
                if any(r['cosine_delta'] > 0.001 or r['z_delta'] > 0.01 for r in differences):
                    raise RuntimeError('Raw diagnostic does not agree with authoritative CLI; see crosscheck')
            except Exception as error:
                result['error'] = str(error)
                self.report.setdefault('infrastructure_errors' if required else 'optional_errors', []).append(f"{query['id']}: {error}")
            result['ended_at'] = now()
            self.report['queries'].append(result)
            self.save()

    def small_samples(self, queries):
        # Copy the fixture-only DB, then retain exactly 1..4 existing real audio vectors (no generated vectors).
        source = sqlite3.connect(self.index / 'index.sqlite')
        primary = [str(self.root / f'a/f{i:03d}.wav') for i in range(1, 5)]
        for count in range(1, 5):
            folder = self.output / 'indices' / f'small-{count}'
            folder.mkdir(parents=True, exist_ok=True)
            destination = sqlite3.connect(folder / 'index.sqlite')
            source.backup(destination)
            names = primary[:count]
            destination.execute('PRAGMA foreign_keys=ON')
            destination.execute('DELETE FROM files WHERE path NOT IN (' + ','.join('?' for _ in names) + ')', names)
            destination.commit()
            actual = destination.execute('SELECT count(*) FROM segments WHERE vec IS NOT NULL').fetchone()[0]
            destination.close()
            if actual != count:
                raise RuntimeError(f'Expected {count} audio vectors in small sample, got {actual}')
            for query in queries:
                item = {'vectors': actual, 'language': query['language'], 'q': query['q']}
                item['wide'] = self.search(query, 'wide', folder, f'small-{count}-{query["language"]}')
                item['default'] = self.search(query, 'default', folder, f'small-{count}-{query["language"]}')
                item['max_z'] = max((h['z'] for h in item['wide']), default=None)
                self.report['small_samples'].append(item)
                self.save()
        source.close()

    def copy_index(self, source_folder, destination_folder):
        destination_folder.mkdir(parents=True, exist_ok=False)
        source = sqlite3.connect('file:' + str(source_folder / 'index.sqlite') + '?mode=ro', uri=True)
        destination = sqlite3.connect(destination_folder / 'index.sqlite')
        try:
            source.backup(destination)
        finally:
            destination.close(); source.close()

    def audit(self, rows, fixtures):
        problems = []
        for fixture in fixtures:
            path = str(self.root / fixture['path'])
            segments = [r for r in rows if r['path'] == path]
            missing = [kind for kind in fixture['expected_segments'] if not any(r['segment'] == kind and
                       (r['valid_vector'] if kind != 'ocr' else True) for r in segments)]
            if missing:
                problems.append(f"{fixture['path']}: missing/invalid {missing}")
        return problems

    def run(self):
        if (self.index / 'index.sqlite').exists():
            raise RuntimeError('Use a fresh output directory: an existing diagnostic index is not overwritten')
        core = [q for q in self.manifest['queries'] if q['group'] == 'core_audio']
        # Newest of the four core files is the cake clip, known from fixture creation order.
        # A single real input is bounded before committing to the other three.
        try:
            self.command('index-core-pilot', ['index', str(self.root / 'a'), '--limit', '1',
                         '--index', str(self.index)], timeout=180)
        except Exception as pilot_error:
            # Same newest fixture, bypassing AVFoundation/indexing, unchanged native worker protocol.
            request = json.dumps({'id': 1, 'op': 'audio', 'inputs': [str(self.root / 'a/f004.wav')]}) + '\n' \
                + '{"id":2,"op":"quit"}\n'
            try:
                result = self.command('pilot-direct-native-audio', ['worker'], timeout=180, stdin=request)
                messages = [json.loads(line) for line in result.splitlines()]
                # Keep responses/ready/error metadata in the report, raw vector payload in the command log.
                self.report['pilot_direct_audio'] = [{k:v for k,v in m.items() if k != 'vectors'} for m in messages]
            except Exception as direct_error:
                self.report['pilot_direct_audio'] = {'error': str(direct_error)}
            self.save()
            raise pilot_error
        rows = self.vector_rows()
        available = {r['path'] for r in rows if r['valid_vector']}
        pilot = [q for q in core if any(str(self.root / p) in available for p in q['expect'])]
        if not pilot:
            raise RuntimeError('First core pilot completed without a valid vector')
        self.evaluate([{**q, 'id': q['id'] + '-pilot', 'group': 'pilot_audio'} for q in pilot], rows, 'pilot')
        self.command('index-core-four', ['index', str(self.root / 'a'), '--index', str(self.index)], timeout=300)
        rows = self.vector_rows()
        errors = self.audit(rows, [f for f in self.manifest['fixtures'] if f['path'].startswith('a/')])
        if errors:
            raise RuntimeError('; '.join(errors))
        self.evaluate(core, rows, 'core-four')
        self.small_samples([q for q in core if q['id'] in ('en-shopping', 'zh-shopping')])
        # Cheap short-text interference comes before any additional media inference.
        baseline = self.index
        plans = [('d', 'text', 120), ('g', 'other_audio', 180), ('b', 'visual', 180),
                 ('c', 'visual', 180), ('e', 'visual', 180), ('f', 'other_audio', 180), ('h', 'late_audio', 240)]
        for folder, group, timeout in plans:
            fixtures = [f for f in self.manifest['fixtures'] if f['path'].startswith(folder + '/')]
            queries = [q for q in self.manifest['queries'] if q['group'] == group and
                       any(p.startswith(folder + '/') for p in q['expect'])]
            if not fixtures:
                continue
            phase_index = self.output / 'indices' / ('phase-' + folder)
            self.copy_index(baseline, phase_index)
            self.index = phase_index
            try:
                self.command('index-phase-' + folder, ['index', str(self.root / folder), '--index', str(self.index)], timeout=timeout)
                rows = self.vector_rows()
                self.report['phase_audits'].append({'phase': folder, 'index_directory': str(self.index),
                    'files': self.report['indexed_files'], 'segments': self.report['indexed_segments'],
                    'ocr': self.report['ocr'], 'vector_counts': self.report['vector_counts']})
                problems = self.audit(rows, fixtures)
                if problems:
                    raise RuntimeError('; '.join(problems))
                self.evaluate(queries, rows, 'phase-' + folder, required=False)
                if folder == 'd':
                    baseline = self.index
                    self.evaluate([{**q, 'id': q['id'] + '-text-interference', 'group': 'mixed_core_audio'}
                                   for q in core], rows, 'text-interference', required=False)
            except Exception as error:
                try:
                    self.vector_rows()
                    self.report['phase_audits'].append({'phase': folder, 'index_directory': str(self.index),
                        'error': str(error), 'files': self.report['indexed_files'], 'segments': self.report['indexed_segments'],
                        'ocr': self.report['ocr'], 'vector_counts': self.report['vector_counts']})
                except Exception as audit_error:
                    self.report['optional_errors'].append(f'phase {folder} state audit: {audit_error}')
                self.report['optional_errors'].append(f'phase {folder}: {error}')
                self.report['untested_queries'] += [{'id': q['id'], 'reason': str(error)} for q in queries]
                self.save()
        # Each optional modality uses an isolated core+text baseline, so a stalled pending row is never retried
        # by an unrelated phase. There is intentionally no claimed all-media combined-corpus result.
        self.report['limitations'].append('Optional modalities are isolated core+text index copies; no all-media merged ranking is claimed.')
        self.report['status'] = 'PARTIAL' if self.report['optional_errors'] else 'COMPLETED'
        if self.report.get('infrastructure_errors'):
            self.report['status'] = 'INFRASTRUCTURE_FAILED'
        self.report['ended_at'] = now(); self.save()
        return 1 if self.report.get('infrastructure_errors') else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cli', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--budget-seconds', type=int, default=1320)
    args = parser.parse_args()
    probe = Probe(args.cli, args.output, args.budget_seconds)
    try:
        return probe.run()
    except Exception as error:
        try:
            probe.vector_rows(); probe.snapshot('terminal-core-failure')
        except Exception as audit_error:
            probe.report['final_audit_error'] = str(audit_error)
        probe.report['status'] = 'INFRASTRUCTURE_FAILED'
        probe.report.setdefault('infrastructure_errors', []).append(str(error))
        probe.report['ended_at'] = now()
        probe.save()
        print(str(error), flush=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
