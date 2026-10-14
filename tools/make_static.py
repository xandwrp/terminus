# Writes sound/terminus/static.wav: a burst of TV static that matches the screen effect's timing.
import random
import struct
import wave
from pathlib import Path

RATE = 44100
ATTACK, HOLD, FADE = 0.03, 0.55, 1.2
PEAK = 0.5
SOFTEN = 0.35  # one-pole lowpass, takes the hard edge off the hiss
CRACKLE_CHANCE, CRACKLE_GAIN = 0.0015, 2.5
CRACKLE_LENGTH = (60, 400)
OUT = Path(__file__).resolve().parent.parent / "sound" / "terminus" / "static.wav"

random.seed(7)
total = int((ATTACK + HOLD + FADE) * RATE)
low, crackle = 0.0, 0
frames = bytearray()
for i in range(total):
	t = i / RATE
	if t < ATTACK:
		env = t / ATTACK
	elif t < ATTACK + HOLD:
		env = 1
	else:
		env = (1 - (t - ATTACK - HOLD) / FADE) ** 2
	low += SOFTEN * (random.uniform(-1, 1) - low)
	if crackle == 0 and random.random() < CRACKLE_CHANCE:
		crackle = random.randint(*CRACKLE_LENGTH)
	gain = CRACKLE_GAIN if crackle > 0 else 1
	crackle = max(crackle - 1, 0)
	s = max(-1, min(1, low * gain * PEAK * env * 2))
	frames += struct.pack("<h", int(s * 32767))

with wave.open(str(OUT), "wb") as w:
	w.setnchannels(1)
	w.setsampwidth(2)
	w.setframerate(RATE)
	w.writeframes(bytes(frames))
print(OUT, f"{total / RATE:.2f}s")
