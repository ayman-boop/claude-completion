# Synthesizes drop.wav: a water-drop "bloop" (fast upward pitch sweep, quick decay) plus a softer echo drop.
import math, struct, wave, os, sys

RATE = 44100

def drop(f0, f1, dur, amp):
    out, phase = [], 0.0
    for i in range(int(RATE * dur)):
        t = i / RATE
        freq = f0 + (f1 - f0) * (1 - math.exp(-t / 0.018))   # pitch jumps up fast, then settles
        phase += 2 * math.pi * freq / RATE
        env = min(1.0, t / 0.002) * math.exp(-t / 0.045)    # click-free attack, quick decay
        out.append(amp * env * math.sin(phase))
    return out

samples = [0.0] * int(RATE * 0.45)
for start, s in ((0.0, drop(550, 1500, 0.25, 0.8)), (0.16, drop(700, 1900, 0.2, 0.3))):
    o = int(RATE * start)
    for i, v in enumerate(s):
        samples[o + i] += v

path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/.claude/turn-runner/drop.wav')
with wave.open(path, 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32000)) for v in samples))
print(path)
