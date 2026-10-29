#!/usr/bin/env python3
"""把 generate_speech 生成的整段配音按静音切分成单句，输出到 assets/voice/。

输入：tools/voice_raw/{wan,tong,tiao,characters}.wav（每段由若干句用句号连接）
输出：assets/voice/{w1..w9, t1..t9, s1..s9, peng, gang, hu, zimo, angang, buggang}.wav
"""
import os
import wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "voice_raw")
OUT = os.path.join(HERE, "..", "assets", "voice")


def read_wav(path):
    with wave.open(path, "rb") as w:
        rate = w.getframerate()
        ch = w.getnchannels()
        width = w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dtype = {1: np.int8, 2: np.int16, 4: np.int32}[width]
    x = np.frombuffer(raw, dtype=dtype).astype(np.float32)
    x /= float(np.iinfo(dtype).max)
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, rate


def write_wav(path, x, rate):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data.tobytes())


def segments(x, rate, min_gap=0.12, frame=0.01):
    """返回 [(start, end)] 样本索引区间，静音间隔 >= min_gap 秒视为句间停顿"""
    n = int(rate * frame)
    frames = len(x) // n
    rms = np.sqrt(np.mean(x[: frames * n].reshape(frames, n) ** 2, axis=1))
    thr = max(rms.max() * 0.06, 1e-4)
    active = rms > thr
    segs = []
    start = None
    silent = 0
    for i, a in enumerate(active):
        if a:
            if start is None:
                start = i
            silent = 0
            last = i
        elif start is not None:
            silent += 1
            if silent * frame >= min_gap:
                segs.append((start, last))
                start = None
    if start is not None:
        segs.append((start, last))
    pad = int(0.03 / frame)
    return [(max(0, s - pad) * n, min(frames, e + pad + 1) * n) for s, e in segs]


def cut(name, names, expected):
    x, rate = read_wav(os.path.join(RAW, name + ".wav"))
    segs = None
    for gap in [0.12, 0.16, 0.2, 0.25, 0.3, 0.35, 0.4, 0.5]:  # 自适应停顿阈值
        cand = segments(x, rate, min_gap=gap)
        if len(cand) == expected:
            segs = cand
            print(name, "matched with min_gap=%.2f" % gap)
            break
    if segs is None:
        raise SystemExit("段数不匹配，请重新生成 %s" % name)
    for (s, e), out in zip(segs, names):
        clip = x[s:e]
        clip = clip / (np.max(np.abs(clip)) + 1e-9) * 0.9
        write_wav(os.path.join(OUT, out + ".wav"), clip, rate)
        print("  ", out, "%.2fs" % ((e - s) / rate))


def main():
    os.makedirs(OUT, exist_ok=True)
    cut("characters", ["peng", "gang", "hu", "zimo", "angang", "buggang"], 6)
    cut("wan", ["w%d" % i for i in range(1, 10)], 9)
    cut("tong", ["t%d" % i for i in range(1, 10)], 9)
    cut("tiao", ["s%d" % i for i in range(1, 10)], 9)


if __name__ == "__main__":
    main()
