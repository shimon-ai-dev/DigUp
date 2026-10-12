#!/usr/bin/env python3
"""macOS-only public/generated content, with transcripts kept OUTSIDE the indexed inputs."""
import argparse
from array import array
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import random
import re
import subprocess
import sys
import wave

TOPICS = [
    ('shopping', "Please stop at the supermarket on your way home. We need milk, eggs and bread for breakfast tomorrow.",
     '回家路上请去超市购物。明天早餐需要牛奶、鸡蛋和面包。', 'buy milk and eggs at the supermarket', '去超市买牛奶和鸡蛋'),
    ('flight', "Attention passengers. The flight to Tokyo is delayed by two hours because of a severe storm.",
     '旅客请注意。由于强烈暴风雨，飞往东京的航班延误了两个小时。', 'flight delayed because of a storm', '暴风雨导致航班延误'),
    ('revenue', "Our quarterly revenue increased by twenty percent. Strong sales in Europe helped the business grow.",
     '本季度营业收入增长百分之二十。欧洲市场销售强劲，帮助业务增长。', 'quarterly revenue grew twenty percent', '季度营业收入增长百分之二十'),
    ('cake', "We are baking a chocolate cake. Mix flour, sugar, cocoa and butter. Put the batter in a round pan and bake it.",
     '我们正在烤巧克力蛋糕。混合面粉、糖、可可和黄油。把面糊放入圆形烤盘烘烤。', 'baking a chocolate cake', '烘烤巧克力蛋糕'),
]
DISTRACTORS = [
    'The gardener planted red roses next to the wooden fence. Water the flowers every morning.',
    'The museum opens at nine in the morning. Visitors can see ancient pottery and marble statues.',
    'The bicycle has a flat tire. Replace the inner tube and tighten the wheel before riding.',
    'A small dog chased a ball across the park. Its owner called it back to the bench.',
    'The piano teacher showed us how to play a gentle melody using both hands.',
    'The library has a quiet reading room upstairs. Return the borrowed novels before Friday.',
    'We will repair the bathroom sink tomorrow. The plumber will replace the leaking pipe.',
    'The astronomy club watched the moon through a telescope. Saturn was visible in the night sky.',
    'A mountain trail passes through a pine forest and ends at a beautiful waterfall.',
    'The photographer adjusted the camera lens to take a portrait in soft afternoon light.',
    'The sewing machine is ready. Measure the fabric and stitch the blue dress carefully.',
    'The basketball team practiced passing and shooting. The next game is on Saturday.',
    'The software installer displayed an error. Restart the computer and check the disk space.',
    'We cleaned the kitchen cabinets and organized the plates, spoons and cups on the shelf.',
    'The train arrives at the city station at noon. Platform three is near the main entrance.',
    'The swimming pool is open today. Bring a towel and goggles for the swimming lesson.',
]
LATE = 'Prepare the frosting by whipping cream with vanilla. Decorate the finished dessert with fresh strawberries and spread the frosting on top.'


def command(args, timeout=60):
    return subprocess.run(args, check=True, timeout=timeout, text=True, capture_output=True)


def read_wav(path):
    with wave.open(str(path), 'rb') as wav:
        if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, 16000):
            raise RuntimeError(f'Invalid WAV format: {path}')
        data = wav.readframes(wav.getnframes())
    values = array('h'); values.frombytes(data)
    if sys.byteorder != 'little':
        values.byteswap()
    if not values or math.sqrt(sum(v*v for v in values) / len(values)) / 32768 < 0.003:
        raise RuntimeError(f'TTS produced silence: {path}')
    return data


def write_wav(path, data):
    with wave.open(str(path), 'wb') as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(16000); wav.writeframes(data)


def say_wav(voice, text, path, scratch):
    aiff = scratch / 'tts.aiff'
    command(['say', '-v', voice, '-o', str(aiff), text], timeout=45)
    command(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(aiff), str(path)], timeout=45)
    aiff.unlink()
    return read_wav(path)


def make(output, renderer):
    if sys.platform != 'darwin':
        raise RuntimeError('Fixture generation requires macOS; no substitute media will be used')
    output.mkdir(parents=True, exist_ok=False)
    root = output / 'inputs'
    for folder in ('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'):
        (root / folder).mkdir(parents=True)
    scratch = output / 'generation-scratch'; scratch.mkdir()
    manifest = {'schema_version': 1, 'generated_at': datetime.now(timezone.utc).isoformat(),
                'coverage': {}, 'fixtures': [], 'queries': [], 'generation_errors': []}

    def save():
        (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')

    def fixture(path, source, transcript, expected, **extra):
        meta = {'path': str(path.relative_to(root)), 'source': source, 'transcript': transcript,
                'expected_segments': expected, 'bytes': path.stat().st_size,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), **extra}
        if path.suffix == '.wav':
            with wave.open(str(path), 'rb') as wav:
                meta['duration'] = wav.getnframes() / wav.getframerate()
        manifest['fixtures'].append(meta); save()

    def pair(name, text_en, text_zh, expect, kind, group, **extra):
        for language, q in [('en', text_en), ('zh', text_zh)]:
            manifest['queries'].append({'id': language + '-' + name, 'language': language,
                                       'q': q, 'expect': expect, 'kind': kind, 'group': group, **extra})
        save()

    voices = command(['say', '-v', '?']).stdout
    (output / 'available-voices.txt').write_text(voices)
    installed = [(match[1].strip(), match[2]) for line in voices.splitlines()
                 if (match := re.match(r'^(.+?)\s+([a-z]{2}_[A-Z]{2})\s+#', line))]
    if not any(name == 'Samantha' for name, _ in installed):
        raise RuntimeError('Samantha is unavailable; required intelligible English speech is untested')
    for index, (topic, en, zh, query_en, query_zh) in enumerate(TOPICS, 1):
        path = root / 'a' / f'f{index:03d}.wav'
        say_wav('Samantha', en, path, scratch)
        fixture(path, 'Locally generated macOS Samantha TTS', en, ['audio'])
        pair(topic, query_en, query_zh, [str(path.relative_to(root))], 'audio', 'core_audio', segment='audio')
    for index, text in enumerate(DISTRACTORS, 105):
        path = root / 'd' / f'f{index:03d}.txt'
        path.write_text(text + '\n')
        fixture(path, 'Locally generated short fictional text distractor', text, ['chunk'])
    manifest['coverage']['english_speech'] = 'GENERATED: Samantha, 4 required topics; isolated before extra media'
    manifest['coverage']['interference'] = 'GENERATED: 16 short text distractors; no 16-clip audio upfront cost'
    # Exact 90 seconds. Target is completely absent in the first 65 seconds.
    prefix = say_wav('Samantha', DISTRACTORS[0], scratch / 'prefix.wav', scratch)
    target_path = scratch / 'late.wav'
    late = say_wav('Samantha', LATE, target_path, scratch)
    prefix_samples = 65 * 16000 * 2
    target_samples = 25 * 16000 * 2
    prefix = (prefix * (prefix_samples // len(prefix) + 1))[:prefix_samples]
    late = (late * (target_samples // len(late) + 1))[:target_samples]
    path = root / 'h' / 'f021.wav'; write_wav(path, prefix + late)
    fixture(path, 'Locally generated Samantha TTS concatenation, 90s',
            {'0-65s': DISTRACTORS[0], '65-90s': LATE}, ['audio'], target_interval=[65, 90])
    pair('late-frosting', 'vanilla cream frosting and fresh strawberries', '香草奶油糖霜和新鲜草莓',
         ['h/f021.wav'], 'audio', 'late_audio', segment='audio', minimum_loc=50, target_start=65)
    chinese = [name for name, locale in installed if locale == 'zh_CN']
    manifest['coverage']['chinese_spoken_content'] = 'UNTESTED: no usable installed zh_CN voice'
    for voice in chinese[:1]:
        try:
            for index, (topic, en, zh, query_en, query_zh) in enumerate(TOPICS[:1], 25):
                path = root / 'g' / f'f{index:03d}.wav'
                say_wav(voice, zh, path, scratch)
                fixture(path, f'Locally generated installed macOS voice {voice}', zh, ['audio'])
                pair('chinese-speech-' + topic, query_en, query_zh, [str(path.relative_to(root))],
                     'audio', 'other_audio', segment='audio')
            manifest['coverage']['chinese_spoken_content'] = f'GENERATED: one shopping clip, installed {voice}; no voice installation attempted'
        except Exception as error:
            manifest['generation_errors'].append(f'Chinese voice {voice}: {error}')
            # Successfully generated cases remain available; ungenerated cases are never marked pass.
    # Synthetic signal, deliberately not represented as a recording of real weather.
    rng = random.Random(20261012)
    values = array('h', (int(rng.uniform(-1, 1) * 2600 * (0.8 + 0.2*math.sin(i/16000))) for i in range(8*16000)))
    if sys.byteorder != 'little': values.byteswap()
    path = root / 'f' / 'f023.wav'; write_wav(path, values.tobytes())
    fixture(path, 'Locally generated deterministic noise, synthetic rain-like approximation', None, ['audio'])
    manifest['coverage']['environment_sound'] = 'SYNTHETIC ONLY: generated noise and optional macOS Glass alert'
    pair('synthetic-noise', 'steady rain noise', '持续的雨声', ['f/f023.wav'], 'audio', 'other_audio', segment='audio')
    system_sound = Path('/System/Library/Sounds/Glass.aiff')
    if system_sound.exists():
        converted = scratch / 'glass.wav'
        command(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(system_sound), str(converted)])
        sound = read_wav(converted)
        path = root / 'f' / 'f024.wav'; write_wav(path, (sound + b'\0' * 16000) * 3)
        fixture(path, str(system_sound) + ' repeated with half-second gaps', None, ['audio'])
        pair('system-chime', 'glass bell chime', '玻璃铃铛提示音', ['f/f024.wav'], 'audio', 'other_audio', segment='audio')
    # Readable bilingual screenshots, no transcripts stored alongside the indexed inputs.
    try:
        command([str(renderer), 'screenshots', str(root / 'c')], timeout=90)
        fixture(root / 'c' / 'Screenshot-f031.png', 'Locally rendered fictional English airport UI',
                ['Flight to Tokyo delayed by two hours', 'Reason: storm and severe weather'], ['image', 'ocr'])
        fixture(root / 'c' / 'Screenshot-f032.png', 'Locally rendered fictional Chinese report UI',
                ['本季度营业收入增长百分之二十', '欧洲市场销售表现强劲'], ['image', 'ocr'])
        pair('screen-flight', TOPICS[1][3], TOPICS[1][4], ['c/Screenshot-f031.png'], 'screenshot', 'visual')
        pair('screen-revenue', TOPICS[2][3], TOPICS[2][4], ['c/Screenshot-f032.png'], 'screenshot', 'visual')
        manifest['coverage']['screenshots'] = 'GENERATED: readable English airport and Chinese revenue UI'
    except Exception as error:
        manifest['coverage']['screenshots'] = 'UNTESTED: ' + str(error)
        manifest['generation_errors'].append(str(error))
    for index, text in [(41, TOPICS[0][1]), (42, TOPICS[3][2])]:
        path = root / 'd' / f'f{index:03d}.txt'; path.write_text(text + '\n')
        fixture(path, 'Locally generated public fictional text', text, ['chunk'])
    pair('text-shopping', TOPICS[0][3], TOPICS[0][4], ['d/f041.txt'], 'doc', 'text')
    pair('text-cake', TOPICS[3][3], TOPICS[3][4], ['d/f042.txt'], 'doc', 'text')
    manifest['coverage']['text'] = 'GENERATED: English shopping and Chinese cake text'
    photos = list(Path('/Library/User Pictures/Animals').glob('*'))
    chosen = [p for p in photos if p.stem.lower() in ('penguin', 'zebra')]
    if not chosen: chosen = sorted(p for p in photos if p.suffix.lower() in ('.heic', '.jpg', '.jpeg', '.png'))[:2]
    manifest['coverage']['ordinary_images'] = 'UNTESTED: no bundled macOS animal pictures'
    for index, source in enumerate(chosen[:2], 50):
        try:
            path = root / 'b' / f'f{index:03d}.jpg'
            command(['sips', '-s', 'format', 'jpeg', '-Z', '768', str(source), '--out', str(path)])
            fixture(path, str(source), None, ['image'], depicted_subject=source.stem)
            subjects = {'penguin': '企鹅', 'zebra': '斑马', 'cat': '猫', 'dog': '狗', 'parrot': '鹦鹉'}
            if source.stem.lower() in subjects:
                pair('photo-' + str(index), 'a ' + source.stem.lower(), subjects[source.stem.lower()],
                     [str(path.relative_to(root))], 'image', 'visual')
            else:
                manifest['generation_errors'].append(f'{source}: no verified Chinese animal label; query omitted')
            manifest['coverage']['ordinary_images'] = 'GENERATED from documented bundled macOS pictures'
        except Exception as error:
            manifest['generation_errors'].append(str(error))
    # Video's visual subject and spoken topic differ, so both paths can be distinguished.
    frame = root / 'b' / 'f050.jpg'
    frame_source = next((f for f in manifest['fixtures'] if f['path'] == 'b/f050.jpg'), None)
    if not frame.exists():
        frame = root / 'c' / 'Screenshot-f032.png'
    try:
        path = root / 'e' / 'f061.mp4'
        command([str(renderer), 'video', str(frame), str(root / 'a' / 'f002.wav'), str(path)], timeout=120)
        fixture(path, 'Locally muxed still image + Samantha flight announcement', TOPICS[1][1], ['frame', 'audio'],
                visual_source=str(frame.relative_to(root)))
        pair('video-sound', TOPICS[1][3], TOPICS[1][4], ['e/f061.mp4'], 'video', 'visual', segment='audio')
        if frame_source and frame_source.get('depicted_subject', '').lower() in ('penguin', 'zebra'):
            subject = frame_source['depicted_subject'].lower()
            pair('video-frame', 'a ' + subject, {'penguin': '企鹅', 'zebra': '斑马'}[subject],
                 ['e/f061.mp4'], 'video', 'visual', segment='frame')
        elif not frame_source:
            pair('video-frame', TOPICS[2][3], TOPICS[2][4], ['e/f061.mp4'], 'video', 'visual', segment='frame')
        manifest['coverage']['video'] = 'GENERATED: local frame + English speech; separate frame/audio expectations'
    except Exception as error:
        manifest['coverage']['video'] = 'UNTESTED: ' + str(error)
        manifest['generation_errors'].append(str(error))
    save()
    # Generated inputs stay available for listening. Temporary synthesis intermediates are not indexed or uploaded.
    import shutil
    shutil.rmtree(scratch)
    print(json.dumps(manifest['coverage'], ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--output', required=True); parser.add_argument('--renderer', required=True)
    args = parser.parse_args(); make(Path(args.output).resolve(), Path(args.renderer).resolve())


if __name__ == '__main__':
    main()
