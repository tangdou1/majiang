#!/usr/bin/env python3
"""程序化生成游戏音效（炉石传说式的出牌挥击 + 落地撞击 + 闪光余韵）。

运行：python3 tools/gen_sounds.py  → 输出到 assets/sfx/*.wav
不依赖任何外部素材，所有声音都由正弦波、噪声与简单包络合成。
"""
import os
import numpy as np
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
rng = np.random.default_rng(7)


def t_axis(dur):
    return np.arange(int(RATE * dur)) / RATE


def env(n, attack=0.005, decay=0.2, curve=2.0):
    t = np.arange(n) / RATE
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-curve * t / max(decay, 1e-4))
    return a * d


def sine(freq, dur, phase=0.0):
    t = t_axis(dur)
    if np.isscalar(freq):
        return np.sin(2 * np.pi * freq * t + phase)
    # 频率随时间变化（freq 为数组）
    f = np.interp(np.linspace(0, 1, len(t)), np.linspace(0, 1, len(freq)), freq)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE + phase)


def noise(dur):
    return rng.uniform(-1, 1, int(RATE * dur))


def lowpass(x, alpha):
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, alpha):
    return x - lowpass(x, alpha)


def delay_mix(x, delay_s, gain, taps=3):
    out = x.copy()
    d = int(RATE * delay_s)
    for k in range(1, taps + 1):
        off = d * k
        if off < len(x):
            out[off:] += x[: len(x) - off] * (gain ** k)
    return out


def fit(x, n):
    """裁剪或补零到长度 n"""
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def normalize(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def save(name, x):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print("wrote", path, "%.2fs" % (len(x) / RATE))


# ---------- 出牌挥击：带通噪声扫频 + 低频拖尾 ----------
def whoosh():
    dur = 0.32
    n = noise(dur)
    n = lowpass(n, 0.25) - lowpass(n, 0.04)  # 粗略带通
    sweep = np.linspace(0.05, 0.35, len(n))
    y = np.zeros_like(n)
    acc = 0.0
    for i in range(len(n)):
        acc += sweep[i] * (n[i] - acc)
        y[i] = acc
    y *= np.sin(np.linspace(0, np.pi, len(n))) ** 1.5
    return normalize(y, 0.55)


# ---------- 落地撞击：三种材质（万=石 筒=玻璃 条=木）+ 字牌=玉 ----------
def impact_stone():
    dur = 0.45
    body = sine(np.linspace(140, 45, int(RATE * dur)), dur) * env(int(RATE * dur), 0.002, 0.18)
    click = highpass(noise(0.03), 0.5) * np.exp(-np.arange(int(RATE * 0.03)) / (RATE * 0.004))
    y = body * 0.9
    y[: len(click)] += click * 0.7
    return normalize(delay_mix(y, 0.05, 0.25, 2), 0.95)


def impact_glass():
    dur = 0.7
    n = int(RATE * dur)
    y = np.zeros(n)
    for f, a, dcy in [(2100, 0.9, 0.18), (3150, 0.6, 0.12), (4620, 0.35, 0.08), (6100, 0.2, 0.05)]:
        y += a * sine(f, dur) * env(n, 0.001, dcy)
    return normalize(delay_mix(y, 0.07, 0.3, 3), 0.8)


def impact_wood():
    dur = 0.3
    n = int(RATE * dur)
    body = sine(np.linspace(430, 210, n), dur) * env(n, 0.001, 0.05)
    knock = highpass(noise(0.02), 0.3) * np.exp(-np.arange(int(RATE * 0.02)) / (RATE * 0.002))
    y = body * 0.9
    y[: len(knock)] += knock * 0.9
    return normalize(y, 0.9)


def impact_jade():
    dur = 0.9
    n = int(RATE * dur)
    y = np.zeros(n)
    for f, a in [(880, 0.8), (1320, 0.4), (1760, 0.25)]:
        y += a * sine(f, dur) * env(n, 0.002, 0.35)
    return normalize(delay_mix(y, 0.11, 0.35, 3), 0.85)


# ---------- 闪光余韵：快速上行的高音琶音 ----------
def shimmer():
    dur = 1.1
    n = int(RATE * dur)
    y = np.zeros(n)
    notes = [1046, 1318, 1568, 2093, 2637, 3136]
    for i, f in enumerate(notes):
        start = int(RATE * 0.05 * i)
        seg_n = n - start
        if seg_n <= 0:
            break
        seg = sine(f, seg_n / RATE) * env(seg_n, 0.003, 0.22)
        y[start:] += seg * 0.28
    return normalize(delay_mix(y, 0.09, 0.35, 3), 0.7)


def select_tick():
    dur = 0.06
    n = int(RATE * dur)
    y = sine(1760, dur) * env(n, 0.001, 0.02)
    return normalize(y, 0.5)


def draw_slide():
    dur = 0.18
    n = int(RATE * dur)
    y = highpass(noise(dur), 0.2) * env(n, 0.02, 0.07)
    return normalize(y, 0.4)


# ---------- 碰/杠：铜管号角式上扬和弦 ----------
def claim_fanfare(kong=False):
    dur = 0.9 if not kong else 1.3
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    base = 330 if not kong else 262
    y = np.zeros(n)
    for ratio in [1.0, 1.25, 1.5, 2.0]:
        f = base * ratio * (1 + 0.02 * np.sin(2 * np.pi * 5 * t))
        saw = np.zeros(n)
        for h in range(1, 7):
            saw += np.sin(2 * np.pi * np.cumsum(f * h) / RATE) / h
        y += saw * 0.18
    y = lowpass(y, 0.08) * env(n, 0.05, dur * 0.6, 1.5)
    if kong:
        y += fit(impact_stone(), n) * 0.8
    y += fit(shimmer(), n) * 0.5
    return normalize(y, 0.9)


# ---------- 胡牌：大号和弦 + 闪光 ----------
def hu_fanfare():
    dur = 2.2
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    y = np.zeros(n)
    chord = [(523, 0.0), (659, 0.12), (784, 0.24), (1046, 0.36)]
    for f, start in chord:
        s = int(RATE * start)
        seg = np.zeros(n)
        for h in range(1, 5):
            seg += np.sin(2 * np.pi * f * h * t) / h
        seg *= env(n, 0.01, 1.4, 1.2)
        seg[:s] = 0
        y += seg * 0.25
    y += fit(shimmer(), n) * 0.9
    y += fit(impact_glass(), n) * 0.6
    return normalize(delay_mix(y, 0.13, 0.3, 3), 0.95)


def main():
    os.makedirs(OUT, exist_ok=True)
    save("whoosh", whoosh())
    save("impact_stone", impact_stone())
    save("impact_glass", impact_glass())
    save("impact_wood", impact_wood())
    save("impact_jade", impact_jade())
    save("shimmer", shimmer())
    save("select", select_tick())
    save("draw", draw_slide())
    save("claim", claim_fanfare(False))
    save("kong", claim_fanfare(True))
    save("hu", hu_fanfare())


if __name__ == "__main__":
    main()
