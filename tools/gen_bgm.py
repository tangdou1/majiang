#!/usr/bin/env python3
"""生成牌桌背景音乐 assets/bgm/table.ogg。

纯程序合成，无需采样。两种风格：
    cheerful（默认）— D 大调五声音阶：欢快的拨弦主旋律 + 轻打击乐（鼓/踩镲/木鱼）
                     + 柔和垫乐 + 行走贝斯，适合长时间游戏循环
    ambient（旧版）— 舒缓的 D 五声音阶环境垫乐
首尾做等功率交叉淡化，可以无缝循环。

依赖：numpy、soundfile
    pip install numpy soundfile
用法：
    python3 tools/gen_bgm.py                  # 欢快版 → assets/bgm/table.ogg
    python3 tools/gen_bgm.py --style ambient  # 旧版环境垫乐 → assets/bgm/table_ambient.ogg
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 44100
BPM = 100
BEAT = 60.0 / BPM            # 一拍 0.6 秒
BAR = BEAT * 4               # 一小节 2.4 秒
BARS = 16
LOOP_SECONDS = BAR * BARS    # 38.4 秒一个完整循环
XFADE_SECONDS = 2.0
CHORD_SECONDS_OLD = 12.0          # 旧版环境垫乐每段和弦的时长（4 段 × 12s = 48s 循环）
OUT = Path(__file__).resolve().parent.parent / "assets" / "bgm" / "table.ogg"


def midi_hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


# ============================ 合成基础 ============================

def pluck(freq: float, seconds: float, decay: float = 1.3) -> np.ndarray:
    """明亮拨弦音：1/2/3/4 次泛音 + 指数衰减，类似古筝/马林巴的质感。"""
    t = np.arange(int(seconds * SR)) / SR
    env = np.exp(-t / decay) * (1.0 - np.exp(-t / 0.004))
    wave = np.zeros_like(t)
    for partial, amp in ((1, 1.0), (2.0, 0.45), (3.01, 0.20), (4.2, 0.09)):
        wave += amp * np.sin(2 * np.pi * (freq * partial) * t)
    return wave * env


def bass_note(freq: float, seconds: float) -> np.ndarray:
    """柔和贝斯：正弦 + 少量三次泛音，带一点击弦的 attack。"""
    t = np.arange(int(seconds * SR)) / SR
    env = np.exp(-t / 0.45) * (1.0 - np.exp(-t / 0.004))
    wave = np.sin(2 * np.pi * freq * t) + 0.18 * np.sin(2 * np.pi * 3 * freq * t)
    return wave * env


def pad_voice(freq: float, seconds: float, detune: float = 0.0,
              tremolo_hz: float = 1 / 8) -> np.ndarray:
    """柔和的持续音：1/2/3 次泛音 + 轻微失谐 + 慢速颤音。"""
    t = np.arange(int(seconds * SR)) / SR
    f = freq * (1.0 + detune)
    wave = np.zeros_like(t)
    for partial, amp, spread in ((1, 1.0, 0.0), (2, 0.30, 0.6), (3, 0.12, -0.8)):
        wave += amp * np.sin(2 * np.pi * (f * partial + spread) * t + 0.7 * partial)
    wave *= 0.82 + 0.18 * np.sin(2 * np.pi * tremolo_hz * t)
    return wave


def kick(seconds: float = 0.22) -> np.ndarray:
    """底鼓：正弦扫频 90→50 Hz，短衰减。"""
    t = np.arange(int(seconds * SR)) / SR
    f = 90.0 * np.exp(-t / 0.055) + 50.0
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.exp(-t / 0.11)


def hat(seconds: float = 0.06) -> np.ndarray:
    """闭镲：白噪声经一阶高通（差分）+ 短衰减。"""
    rng = np.random.default_rng(7)
    x = rng.normal(0.0, 1.0, int(seconds * SR))
    y = np.diff(x, prepend=0.0)
    t = np.arange(y.size) / SR
    return y * np.exp(-t / 0.022) * 0.6


def woodblock(seconds: float = 0.10) -> np.ndarray:
    """木鱼：噪声 + 1.7 kHz 共振音，短衰减。"""
    rng = np.random.default_rng(11)
    t = np.arange(int(seconds * SR)) / SR
    x = rng.normal(0.0, 1.0, t.size) * np.exp(-t / 0.03)
    tone = np.sin(2 * np.pi * 1700.0 * t) * np.exp(-t / 0.022)
    return (0.6 * x + 0.8 * tone) * 0.5


def chord_envelope(seconds: float, fade: float = 1.4) -> np.ndarray:
    """垫乐的进场/退场包络（余弦形），相邻和弦自然交叠。"""
    n = int(seconds * SR)
    env = np.ones(n)
    f = int(fade * SR)
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, f))
    env[:f] = ramp
    env[-f:] = ramp[::-1]
    return env


def place(buffer: np.ndarray, sample: np.ndarray, start_seconds: float, gain: float,
          pan: float = 0.0) -> None:
    """把一段单声道素材以指定音量和声像叠加进立体声缓冲区。"""
    start = int(round(start_seconds * SR))
    offset = 0
    if start < 0:                      # 第一段提前进场，丢掉越界的开头
        offset = -start
        start = 0
    end = min(start + sample.size - offset, buffer.shape[1])
    if end <= start:
        return
    chunk = sample[offset: offset + (end - start)] * gain
    left = math.sqrt(max(0.0, 0.5 * (1.0 - pan)))
    right = math.sqrt(max(0.0, 0.5 * (1.0 + pan)))
    buffer[0, start:end] += chunk * left
    buffer[1, start:end] += chunk * right


def crossfade_loop(mix: np.ndarray) -> np.ndarray:
    """首尾等功率交叉淡化，形成无缝循环。"""
    fade = int(XFADE_SECONDS * SR)
    head = mix[:, :fade].copy()
    tail = mix[:, -fade:]
    ramp = np.linspace(0.0, 1.0, fade)
    eq_in = np.sin(ramp * math.pi / 2)
    eq_out = np.cos(ramp * math.pi / 2)
    mix[:, :fade] = head * eq_in + tail * eq_out
    return mix[:, :-fade]


def master(mix: np.ndarray, peak: float = 0.6) -> np.ndarray:
    """去直流 → tanh 软削波 → 归一化到目标峰值。"""
    mix = mix.copy()
    mix[0] = np.diff(mix[0], prepend=0.0)
    mix[1] = np.diff(mix[1], prepend=0.0)
    mix = np.tanh(mix * 1.2) / 1.2          # 软削波，避免拨弦瞬态过载
    p = np.max(np.abs(mix))
    if p > 0:
        mix *= peak / p
    return mix


# ============================ 欢快版 ============================

## 和声进行：D – G – A – Bm（4 小节一块），全部在 D 大调五声音阶氛围内
_CHORD_NOTES = [  # 每块三个和弦音（低八度铺底）
    (50, 54, 57),    # D3 F#3 A3  → D 大三和弦
    (55, 59, 62),    # G3  B3  D4  → G 大三和弦
    (57, 61, 64),    # A3  C#4 E4  → A 大三和弦
    (59, 62, 66),    # B3  D4  F#4 → B 小三和弦
]
_BASS_ROOTS = [38, 43, 45, 47]              # D2 G2 A2 B1
_ARP_NOTES = [                              # 每块的琶音（高八度，明亮）
    (62, 66, 69, 74),   # D4 F#4 A4 D5
    (67, 71, 74, 79),   # G4  B4  D5 G5
    (69, 73, 76, 81),   # A4  C#5 E5 A5
    (71, 74, 78, 83),   # B4  D5  F#5 B5
]

## 主旋律：16 小节 × 8 个八分音符的 D 大调五声音阶（D E F# A B），
## (小节, 八分位, MIDI 音高)。结尾停在 D5，与开头衔接。
_MELODY = [
    # 第 1–4 小节（D）
    (0, 0, 74), (0, 1, 76), (0, 2, 78), (0, 3, 81), (0, 5, 83), (0, 6, 81), (0, 7, 78),
    (1, 0, 76), (1, 1, 74), (1, 2, 78), (1, 3, 74), (1, 4, 76), (1, 5, 78), (1, 6, 76), (1, 7, 74),
    (2, 0, 78), (2, 1, 81), (2, 2, 83), (2, 3, 86), (2, 5, 83), (2, 6, 81), (2, 7, 78),
    (3, 0, 76), (3, 1, 78), (3, 2, 76), (3, 3, 74), (3, 4, 71), (3, 5, 69), (3, 6, 71), (3, 7, 74),
    # 第 5–8 小节（G）
    (4, 0, 81), (4, 1, 78), (4, 2, 76), (4, 3, 74), (4, 4, 76), (4, 5, 78), (4, 6, 81), (4, 7, 83),
    (5, 1, 83), (5, 2, 86), (5, 4, 83), (5, 5, 81), (5, 6, 78), (5, 7, 76),
    (6, 0, 78), (6, 1, 81), (6, 2, 83), (6, 3, 86), (6, 4, 83), (6, 5, 81), (6, 6, 83), (6, 7, 86),
    (7, 0, 76), (7, 1, 74), (7, 2, 78), (7, 3, 76), (7, 4, 74), (7, 5, 76), (7, 6, 78), (7, 7, 74),
    # 第 9–12 小节（A）
    (8, 0, 78), (8, 1, 81), (8, 2, 83), (8, 3, 81), (8, 4, 76), (8, 5, 78), (8, 6, 81), (8, 7, 83),
    (9, 0, 81), (9, 1, 83), (9, 2, 86), (9, 3, 83), (9, 5, 81), (9, 6, 78), (9, 7, 76),
    (10, 0, 74), (10, 1, 76), (10, 2, 78), (10, 3, 81), (10, 4, 83), (10, 5, 81), (10, 6, 78), (10, 7, 76),
    (11, 0, 74), (11, 1, 76), (11, 2, 78), (11, 3, 74), (11, 5, 76), (11, 6, 78), (11, 7, 74),
    # 第 13–16 小节（Bm）→ 收束回 D
    (12, 0, 71), (12, 1, 69), (12, 2, 71), (12, 3, 74), (12, 4, 78), (12, 5, 76), (12, 6, 74),
    (13, 0, 76), (13, 1, 78), (13, 2, 76), (13, 3, 74), (13, 4, 71), (13, 5, 69), (13, 6, 71), (13, 7, 74),
    (14, 0, 81), (14, 1, 78), (14, 2, 76), (14, 3, 74), (14, 4, 76), (14, 5, 78), (14, 6, 81), (14, 7, 83),
    (15, 0, 86), (15, 1, 83), (15, 2, 81), (15, 3, 78), (15, 4, 76), (15, 5, 74), (15, 7, 74),
]


def build_cheerful() -> np.ndarray:
    total = int(LOOP_SECONDS * SR)
    mix = np.zeros((2, total))
    eight = BEAT / 2.0

    # ---- 垫乐：4 小节一个和弦，首尾交叠，铺满整个循环 ----
    for block in range(4):
        start = block * 4 * BAR - 1.0
        secs = 4 * BAR + 2.0
        env = chord_envelope(secs)
        for j, note in enumerate(_CHORD_NOTES[block]):
            freq = midi_hz(note)
            for detune, pan in ((-0.0015, -0.3), (0.0015, 0.3)):
                place(mix, pad_voice(freq, secs, detune) * env,
                      start, 0.055, pan)

    # ---- 主旋律：明亮的拨弦，略带声像摆动 ----
    for k, (bar, pos, note) in enumerate(_MELODY):
        pan = 0.15 if k % 4 < 2 else -0.15
        place(mix, pluck(midi_hz(note), 2.6), bar * BAR + pos * eight, 0.30, pan)

    # ---- 琶音伴奏：每小节四个四分音符，轻轻垫底 ----
    for block in range(4):
        for bar in range(4):
            b = block * 4 + bar
            notes = _ARP_NOTES[block]
            for beat in range(4):
                note = notes[(0, 2, 3, 2)[beat]]
                pan = 0.2 if beat % 2 == 0 else -0.2
                place(mix, pluck(midi_hz(note), 0.9, decay=0.5),
                      b * BAR + beat * BEAT, 0.11, pan)

    # ---- 行走贝斯：第 1、3 拍根音，第 4 拍五度 ----
    for block in range(4):
        for bar in range(4):
            b = block * 4 + bar
            root = _BASS_ROOTS[block]
            for pos, note in ((0, root), (2, root), (4, root + 7), (6, root)):
                place(mix, bass_note(midi_hz(note), 0.9),
                      b * BAR + pos * eight, 0.20, 0.0)

    # ---- 轻打击乐：底鼓（1、3 拍）+ 闭镲（八分音符）+ 木鱼（2、4 拍）----
    for bar in range(BARS):
        t0 = bar * BAR
        place(mix, kick(), t0, 0.30, 0.0)
        place(mix, kick(), t0 + 2 * BEAT, 0.26, 0.0)
        for pos in range(8):
            v = 0.035 if pos % 2 == 0 else 0.028
            place(mix, hat(), t0 + pos * eight, v, 0.05 * (1 if pos % 2 else -1))
        place(mix, woodblock(), t0 + BEAT, 0.06, -0.1)
        place(mix, woodblock(), t0 + 3 * BEAT, 0.06, 0.1)

    return master(crossfade_loop(mix))


# ============================ 旧版环境垫乐 ============================

def build_ambient() -> np.ndarray:
    loop_old = CHORD_SECONDS_OLD * 4     # 48 秒缓冲区；crossfade_loop 去掉尾部 2 秒 → 46 秒循环
    total = int(loop_old * SR)
    mix = np.zeros((2, total))
    rng = np.random.default_rng(20261101)

    voicings = [
        (38, 45, 50, 54),   # D2 A2 D3 F#3
        (38, 45, 52, 59),   # D2 A2 E3 B3
        (38, 45, 50, 57),   # D2 A2 D3 A3
        (35, 42, 50, 54),   # B1 F#2 D3 F#3
    ]
    for i, notes in enumerate(voicings):
        start = i * CHORD_SECONDS_OLD - 1.3
        env = chord_envelope(CHORD_SECONDS_OLD + 2.6)
        for j, note in enumerate(notes):
            freq = midi_hz(note)
            gain = 0.16 if j > 0 else 0.2
            for detune, pan in ((-0.0015, -0.35), (0.0015, 0.35)):
                voice = pad_voice(freq, CHORD_SECONDS_OLD + 2.6, detune) * env
                place(mix, voice, start, gain * 0.5, pan)

    melody = [
        (0.8, 74), (2.4, 69), (4.1, 81), (6.6, 76),
        (13.0, 81), (14.8, 74), (17.2, 69), (19.0, 76),
        (25.0, 74), (26.8, 81), (29.4, 88), (31.6, 81),
        (37.0, 76), (38.8, 74), (41.2, 69),
    ]
    for k, (when, note) in enumerate(melody):
        pan = 0.25 if k % 2 == 0 else -0.25
        place(mix, pluck(midi_hz(note), 4.5), when, 0.10, pan)

    noise = rng.normal(0.0, 1.0, total)
    kernel = np.ones(64) / 64.0
    noise = np.convolve(noise, kernel, mode="same")
    t = np.arange(total) / SR
    noise *= 0.0028 * (0.7 + 0.3 * np.sin(2 * np.pi * t / loop_old * 2 - math.pi / 2))
    mix[0] += noise
    mix[1] += np.roll(noise, 911)

    return master(crossfade_loop(mix))


CHORD_SECONDS_OLD = 12.0


# ============================ 入口 ============================

def main() -> None:
    parser = argparse.ArgumentParser(description="生成牌桌背景音乐")
    parser.add_argument("--style", choices=["cheerful", "ambient"], default="cheerful")
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    out = args.out
    if out is None:
        out = OUT if args.style == "cheerful" else \
            OUT.parent / "table_ambient.ogg"
    out.parent.mkdir(parents=True, exist_ok=True)
    audio = build_cheerful() if args.style == "cheerful" else build_ambient()
    sf.write(out, audio.T, SR, format="OGG", subtype="VORBIS")
    print(f"写入 {out}  ({out.stat().st_size / 1024:.0f} KB, "
          f"{audio.shape[1] / SR:.1f} 秒, 风格={args.style})")


if __name__ == "__main__":
    main()
