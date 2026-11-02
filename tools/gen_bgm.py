#!/usr/bin/env python3
"""生成牌桌背景音乐 assets/bgm/table.ogg。

纯程序合成，无需采样：D 五声音阶的持续音垫 + 少量泛音拨奏 + 极轻的房间底噪，
首尾做等功率交叉淡化，可以无缝循环。

依赖：numpy、soundfile
    pip install numpy soundfile
用法：
    python3 tools/gen_bgm.py            # 写入 assets/bgm/table.ogg
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 32000
CHORD_SECONDS = 12.0
CHORDS = 4
LOOP_SECONDS = CHORD_SECONDS * CHORDS      # 48 秒一个完整循环
XFADE_SECONDS = 2.0
OUT = Path(__file__).resolve().parent.parent / "assets" / "bgm" / "table.ogg"


def midi_hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def pad_voice(freq: float, seconds: float, detune: float = 0.0, tremolo_hz: float = 1 / 16) -> np.ndarray:
    """柔和的持续音：1/2/3 次泛音 + 轻微失谐 + 慢速颤音。"""
    t = np.arange(int(seconds * SR)) / SR
    f = freq * (1.0 + detune)
    wave = np.zeros_like(t)
    for partial, amp, spread in ((1, 1.0, 0.0), (2, 0.32, 0.6), (3, 0.14, -0.8), (4, 0.06, 1.4)):
        wave += amp * np.sin(2 * np.pi * (f * partial + spread) * t + 0.7 * partial)
    # 两个周期的颤音，正好整除循环长度，保证首尾可拼接
    wave *= 0.82 + 0.18 * np.sin(2 * np.pi * tremolo_hz * t)
    return wave


def chord_envelope(seconds: float, fade: float = 2.6) -> np.ndarray:
    """每段和弦的进场/退场包络（余弦形），相邻和弦自然交叠。"""
    n = int(seconds * SR)
    env = np.ones(n)
    f = int(fade * SR)
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, f))
    env[:f] = ramp
    env[-f:] = ramp[::-1]
    return env


def pluck(freq: float, seconds: float, decay: float = 1.6) -> np.ndarray:
    """拨奏音：泛音叠加 + 指数衰减，尾音会自然消失。"""
    t = np.arange(int(seconds * SR)) / SR
    env = np.exp(-t / decay) * (1.0 - np.exp(-t / 0.006))
    wave = np.zeros_like(t)
    for partial, amp, detune in ((1, 1.0, 0.0), (2, 0.42, 0.9), (3, 0.22, -1.3), (4.2, 0.10, 2.1)):
        wave += amp * np.sin(2 * np.pi * (freq * partial + detune) * t)
    return wave * env


def place(buffer: np.ndarray, sample: np.ndarray, start_seconds: float, gain: float,
          pan: float = 0.0) -> None:
    """把一段单声道素材以指定音量和声像叠加进立体声缓冲区。"""
    start = int(round(start_seconds * SR))
    offset = 0
    if start < 0:                      # 第一段和弦提前进场，丢掉越界的开头
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


def build() -> np.ndarray:
    rng = np.random.default_rng(20261101)
    total = int(LOOP_SECONDS * SR)
    mix = np.zeros((2, total))

    # ---- 持续音垫：D 五声音阶的四个和声色彩，每 12 秒换一次 ----
    voicings = [
        (38, 45, 50, 54),   # D2 A2 D3 F#3
        (38, 45, 52, 59),   # D2 A2 E3 B3
        (38, 45, 50, 57),   # D2 A2 D3 A3
        (35, 42, 50, 54),   # B1 F#2 D3 F#3
    ]
    for i, notes in enumerate(voicings):
        start = i * CHORD_SECONDS - 1.3          # 稍早进场，和上一段交叠
        env = chord_envelope(CHORD_SECONDS + 2.6)
        for j, note in enumerate(notes):
            freq = midi_hz(note)
            gain = 0.16 if j > 0 else 0.2
            for detune, pan in ((-0.0015, -0.35), (0.0015, 0.35)):
                voice = pad_voice(freq, CHORD_SECONDS + 2.6, detune) * env
                place(mix, voice, start, gain * 0.5, pan)

    # ---- 拨奏：稀疏的五声音阶短句，最后 4 秒不放，便于循环 ----
    melody = [
        (0.8, 74), (2.4, 69), (4.1, 81), (6.6, 76),
        (13.0, 81), (14.8, 74), (17.2, 69), (19.0, 76),
        (25.0, 74), (26.8, 81), (29.4, 88), (31.6, 81),
        (37.0, 76), (38.8, 74), (41.2, 69),
    ]
    for k, (when, note) in enumerate(melody):
        pan = 0.25 if k % 2 == 0 else -0.25
        place(mix, pluck(midi_hz(note), 4.5), when, 0.10, pan)

    # ---- 房间底噪：低通过的噪声，慢速起伏 ----
    noise = rng.normal(0.0, 1.0, total)
    kernel = np.ones(64) / 64.0
    noise = np.convolve(noise, kernel, mode="same")
    t = np.arange(total) / SR
    noise *= 0.0028 * (0.7 + 0.3 * np.sin(2 * np.pi * t / LOOP_SECONDS * 2 - math.pi / 2))
    mix[0] += noise
    mix[1] += np.roll(noise, 911)

    # ---- 首尾等功率交叉淡化，形成无缝循环 ----
    fade = int(XFADE_SECONDS * SR)
    head = mix[:, :fade].copy()
    tail = mix[:, -fade:]
    ramp = np.linspace(0.0, 1.0, fade)
    eq_in = np.sin(ramp * math.pi / 2)
    eq_out = np.cos(ramp * math.pi / 2)
    mix[:, :fade] = head * eq_in + tail * eq_out
    mix = mix[:, :-fade]

    peak = np.max(np.abs(mix))
    if peak > 0:
        mix *= 0.55 / peak
    return mix


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    audio = build()
    sf.write(OUT, audio.T, SR, format="OGG", subtype="VORBIS")
    print(f"写入 {OUT}  ({OUT.stat().st_size / 1024:.0f} KB, {audio.shape[1] / SR:.1f} 秒)")


if __name__ == "__main__":
    main()
