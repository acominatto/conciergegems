"""Gera os WAV do Concierge Gems nativo a partir dos MESMOS parametros do js/audio.js.

Reimplementa em Python os blocos do WebAudio usados no jogo (tone com rampa exponencial e glissando,
noise com passa-baixas, shard com passa-banda, bell com parciais inarmonicos 1 / 2,76 / 5,4) e renderiza
cada evento num arquivo pronto para upload no Second Life.

Formato de saida: WAV PCM 16 bits, MONO, 44.100 Hz, <= 10 s (o que o SL aceita).
Uso:  python tools/make_audio.py
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'audio')
MASTER = 1.4          # audio.js: this.master.gain.value = 1.4


class Buf:
    def __init__(self, seconds):
        self.n = int(SR * seconds)
        self.d = [0.0] * self.n

    def add(self, i, v):
        if 0 <= i < self.n:
            self.d[i] += v


def _env(g0, g1, t, dur):
    """rampa exponencial do WebAudio (exponentialRampToValueAtTime), com piso em 1e-4."""
    g0 = max(g0, 1e-4)
    g1 = max(g1, 1e-4)
    return g0 * (g1 / g0) ** (t / dur) if dur > 0 else g0


def tone(buf, freq, ms, kind='sine', gain=0.12, delay=0.0, slide_to=None):
    """oscilador com ataque de 8 ms e queda exponencial; slide_to = glissando (audio.js tone())."""
    dur = ms / 1000.0
    start = int(SR * delay / 1000.0)
    n = int(SR * dur)
    atk = int(SR * 0.008)
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = freq if not slide_to else freq * (slide_to / freq) ** (t / dur)
        phase += 2 * math.pi * f / SR
        if kind == 'sine':
            s = math.sin(phase)
        elif kind == 'triangle':
            s = 2 / math.pi * math.asin(math.sin(phase))
        elif kind == 'square':
            s = 1.0 if math.sin(phase) >= 0 else -1.0
        else:  # sawtooth
            s = 2 * ((phase / (2 * math.pi)) % 1.0) - 1.0
        if i < atk:
            g = _env(1e-4, gain, i / SR, 0.008)
        else:
            g = _env(gain, 1e-4, (i - atk) / SR, max(dur - 0.008, 1e-4))
        buf.add(start + i, s * g)


def _biquad(data, f0, q, kind):
    """biquad do WebAudio (RBJ cookbook), aplicado em serie."""
    w0 = 2 * math.pi * f0 / SR
    alpha = math.sin(w0) / (2 * q)
    cw = math.cos(w0)
    if kind == 'lowpass':
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    else:  # bandpass (ganho de pico = Q, como o WebAudio)
        b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for x in data:
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out.append(y)
        x2, x1 = x1, x
        y2, y1 = y1, y
    return out


def noise(buf, ms, gain=0.2, delay=0.0, lowpass=1800, rng=random):
    """ruido branco com passa-baixas que varre de `lowpass` ate 200 Hz (audio.js noise())."""
    dur = ms / 1000.0
    n = int(SR * dur)
    raw = [rng.random() * 2 - 1 for _ in range(n)]
    # varredura do filtro aproximada em 8 blocos (o WebAudio faz continuo)
    blocks = 8
    per = max(1, n // blocks)
    filt = []
    for b in range(blocks):
        seg = raw[b * per:(b + 1) * per]
        if not seg:
            continue
        f = lowpass * (200.0 / lowpass) ** (b / max(1, blocks - 1))
        filt.extend(_biquad(seg, max(f, 60.0), 0.7071, 'lowpass'))
    start = int(SR * delay / 1000.0)
    for i, s in enumerate(filt):
        buf.add(start + i, s * _env(gain, 1e-4, i / SR, dur))


def shard(buf, ms, gain=0.1, delay=0.0, f=6000, q=1.2, rng=random):
    """estilhaco de vidro: ruido em passa-banda estreito (audio.js shard())."""
    dur = ms / 1000.0
    n = int(SR * dur)
    raw = [rng.random() * 2 - 1 for _ in range(n)]
    filt = _biquad(raw, min(f, SR / 2 - 100), q, 'bandpass')
    start = int(SR * delay / 1000.0)
    for i, s in enumerate(filt):
        buf.add(start + i, s * _env(gain, 1e-4, i / SR, dur))


def bell(buf, freq, ms, gain, delay=0.0):
    """sino de cristal: parciais inarmonicos 1 / 2,76 / 5,4 (audio.js bell())."""
    tone(buf, freq, ms, 'sine', gain, delay)
    tone(buf, freq * 2.76, ms * 0.55, 'sine', gain * 0.35, delay)
    tone(buf, freq * 5.4, ms * 0.3, 'sine', gain * 0.14, delay)


def save(name, buf, peak=0.89):
    """normaliza para um pico fixo (o SL nao tem controle de volume por som) e grava WAV 16 bits mono."""
    mx = max(abs(x) for x in buf.d) or 1.0
    k = peak / mx
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1.0, min(1.0, x * k)) * 32767)) for x in buf.d))
    return path, len(buf.d) / SR


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(7)          # sons identicos a cada execucao
    made = []

    # ---- eventos simples (audio.js) ----
    b = Buf(0.35); bell(b, 1320, 110, 0.06); made.append(save('select', b))
    b = Buf(0.35); shard(b, 90, 0.05, 0, 3200, 0.8, rng); tone(b, 420, 90, 'sine', 0.05, 0, 700); made.append(save('swap', b))
    b = Buf(0.45); tone(b, 190, 130, 'triangle', 0.09, 0, 120); tone(b, 150, 150, 'triangle', 0.08, 100, 95); made.append(save('invalid', b))
    b = Buf(0.30); bell(b, 1760 + 250, 70, 0.028); made.append(save('land', b))
    b = Buf(1.20)
    tone(b, 500, 260, 'sine', 0.06, 0, 2600)
    for i, f in enumerate([1046, 1318, 1568, 2093, 2637]):
        bell(b, f, 320, 0.06, 90 + i * 55)
    made.append(save('created', b))
    b = Buf(0.30); tone(b, 880, 60, 'square', 0.045); made.append(save('tick', b))
    b = Buf(1.50)
    for i, f in enumerate([392, 523, 659, 784]):
        tone(b, f, 180, 'sine', 0.09, i * 60)
    made.append(save('start', b))
    b = Buf(1.00); tone(b, 240, 520, 'sine', 0.07, 0, 720); noise(b, 500, 0.05, 0, 3000, rng); made.append(save('shuffle', b))
    b = Buf(1.60)
    for i, f in enumerate([523, 440, 349, 262]):
        tone(b, f, 320, 'triangle', 0.12, i * 170)
    made.append(save('gameover', b))

    # ---- level up ----
    b = Buf(2.0)
    for i, f in enumerate([523, 659, 784, 1047, 1319, 1568]):
        bell(b, f, 420, 0.08, i * 95)
    bell(b, 2093, 900, 0.06, 560)
    for i in range(6):
        shard(b, 50, 0.05, 500 + i * 70, 7000 + rng.random() * 3000, 2, rng)
    made.append(save('levelup', b))

    # ---- estouro: um arquivo por degrau da cascata (match0..match7), tom subindo na escala maior ----
    scale = [0, 2, 4, 5, 7, 9, 11, 12, 14]
    for chain in range(8):
        base = 523.25 * 2 ** (scale[min(chain, len(scale) - 1)] / 12)
        count = 3 + min(chain, 3)          # cascata maior costuma limpar mais gemas
        n = min(max(count, 3), 8)
        b = Buf(1.4)
        for i in range(n):
            t = i * 32
            shard(b, 70 + rng.random() * 50, 0.09, t, 4500 + rng.random() * 4500, 1.4, rng)
            shard(b, 40, 0.06, t, 9000 + rng.random() * 2500, 2, rng)
            bell(b, base * (1.5 if i % 2 else 1.0), 240, 0.075, t)
        bell(b, base * 2, 420, 0.07, n * 32)
        if count >= 4:
            bell(b, base * 3, 380, 0.045, n * 32 + 60)
        if count >= 5:
            bell(b, base * 4, 520, 0.035, n * 32 + 130)
        tone(b, base / 2, 110, 'sine', 0.08, 0, base / 4)
        made.append(save('match%d' % chain, b))

    # ---- especiais ----
    b = Buf(1.6)                            # bomba
    tone(b, 120, 420, 'sine', 0.24, 0, 38)
    noise(b, 480, 0.24, 0, 2200, rng)
    for i in range(10):
        shard(b, 60, 0.08, 60 + i * 35, 3500 + rng.random() * 6000, 1.5, rng)
    made.append(save('blast_bomb', b))

    b = Buf(1.6)                            # estrela
    noise(b, 520, 0.16, 0, 4500, rng)
    tone(b, 140, 420, 'sawtooth', 0.08, 0, 60)
    for i in range(8):
        shard(b, 35, 0.09, 40 + i * 45, 3000 + rng.random() * 5000, 2, rng)
    bell(b, 880, 400, 0.06, 120)
    made.append(save('blast_star', b))

    b = Buf(2.0)                            # rainbow
    tone(b, 200, 520, 'sawtooth', 0.06, 0, 2400)
    for i in range(10):
        shard(b, 45, 0.09, i * 40, 2500 + rng.random() * 7000, 3, rng)
    for i, f in enumerate([523, 659, 784, 988, 1175, 1568, 1976, 2349]):
        bell(b, f, 300, 0.06, 60 + i * 45)
    made.append(save('blast_rainbow', b))

    total = 0
    print('%-18s %6s %8s' % ('arquivo', 'seg', 'KB'))
    for path, secs in made:
        kb = os.path.getsize(path) / 1024
        total += kb
        flag = '' if secs <= 10 else '  <-- PASSA DE 10 s, O SL RECUSA'
        print('%-18s %6.2f %8.0f%s' % (os.path.basename(path), secs, kb, flag))
    print('\n%d arquivos, %.0f KB no total. Upload no SL: L$ 10 por som.' % (len(made), total))


if __name__ == '__main__':
    main()
