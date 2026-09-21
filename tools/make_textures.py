"""Gera as texturas do Concierge Gems nativo, com a MESMA logica visual do Canvas (main.js).

Saidas em /textures (PNG RGBA, prontas para upload no Second Life):
  CG_gems_atlas_1024x512.png  - as 8 gemas originais, pixels intactos (4 colunas x 2 linhas)
  CG_fx_atlas_1024x1024.png   - explosao em 16 quadros (4x4): anel que cresce + 7 particulas + clarao,
                                exatamente o efeito de addPopFx() (raio 10->44 px, alpha 1->0, gravidade 14t^2)
  CG_digits_atlas_512x512.png - digitos 0-9 (4x4) para pontuacao, tempo, nivel e combo

A cor e aplicada no prim (PRIM_COLOR), entao o atlas de FX e branco: um so atlas serve as 7 cores + rainbow.
Uso:  python tools/make_textures.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, '..', 'textures')
SRC = os.path.join(HERE, '..', '..', 'public', 'games', 'bubble-match', 'assets', 'gems')

GEMS = ['gem_0_blue', 'gem_1_green', 'gem_2_red', 'gem_3_gold',
        'gem_4_turquoise', 'gem_5_magenta', 'gem_6_pink', 'gem_rainbow']


def gems_atlas():
    """4 x 2 quadros de 256 px: copia exata dos PNG originais (sem recompressao com perda)."""
    atlas = Image.new('RGBA', (1024, 512), (0, 0, 0, 0))
    for i, name in enumerate(GEMS):
        im = Image.open(os.path.join(SRC, name + '.png')).convert('RGBA')
        atlas.paste(im, ((i % 4) * 256, (i // 4) * 256))
    out = os.path.join(TEX, 'CG_gems_atlas_1024x512.png')
    atlas.save(out, optimize=True)
    # conferencia: cada quadro tem de ser identico ao arquivo de origem
    chk = Image.open(out).convert('RGBA')
    ok = all(chk.crop(((i % 4) * 256, (i // 4) * 256, (i % 4) * 256 + 256, (i // 4) * 256 + 256)).tobytes()
             == Image.open(os.path.join(SRC, n + '.png')).convert('RGBA').tobytes() for i, n in enumerate(GEMS))
    return out, ('identico aos 8 PNG originais' if ok else 'DIFERENTE DOS ORIGINAIS')


def fx_atlas():
    """16 quadros de 256 px com o efeito de addPopFx() do main.js, em branco (a cor vem do prim).

    No original (celula de 62 px): anel de raio 10 -> 44 px com espessura 4 -> 1 e alpha 1 -> 0;
    7 particulas a 22-42 px do centro, com queda 14*t^2. Aqui tudo e reescalado para 256 px (x4,13)
    e desenhado em 4x com reducao no fim (suavizacao: o SL nao tem antialias em textura).
    """
    S = 256
    SS = 4                            # supersampling
    K = S / 62.0                      # px do jogo -> px do quadro
    atlas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    ang = [(i / 7) * math.pi * 2 + ((i * 0.37) % 0.6) for i in range(7)]
    dist = [22 + (i * 7) % 20 for i in range(7)]
    for f in range(16):
        t = (f + 0.5) / 16.0
        big = Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))
        d = ImageDraw.Draw(big)
        cx = cy = S * SS / 2
        u = K * SS
        # brilho central curto (o "flash" do estouro); pequeno, so o nucleo - a GEMA que cresce
        # e some fica por conta do proprio prim, nao do atlas
        if t < 0.30:
            k = t / 0.30
            r = 7 * u * (1 + 0.6 * k)
            for step in range(6):                 # degrade radial manual (Pillow nao tem gradiente)
                rr = r * (1 - step / 6.0)
                aa = int(200 * (1 - k) * (step + 1) / 6.0)
                d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(255, 255, 255, aa))
        # anel que expande (raio 10 -> 44 px e alpha 1 -> 0 do original; espessura enxuta)
        ar = (10 + t * 34) * u
        aw = max(SS, (2.2 * (1 - t) + 0.8) * u)
        alpha = int(255 * (1 - t))
        if alpha > 0:
            d.ellipse([cx - ar, cy - ar, cx + ar, cy + ar], outline=(255, 255, 255, alpha), width=int(aw))
        # 7 particulas com gravidade 14t^2
        for i in range(7):
            px = cx + math.cos(ang[i]) * dist[i] * t * u
            py = cy + math.sin(ang[i]) * dist[i] * t * u + 14 * t * t * u
            pr = max(0.8 * SS, (2.4 * (1 - t) + 0.4) * u)
            pa = int(255 * (1 - t) * 0.95)
            if pa > 0:
                d.ellipse([px - pr, py - pr, px + pr, py + pr], fill=(255, 255, 255, pa))
        atlas.paste(big.resize((S, S), Image.LANCZOS), ((f % 4) * S, (f // 4) * S))
    out = os.path.join(TEX, 'CG_fx_atlas_1024x1024.png')
    atlas.save(out, optimize=True)
    return out, '16 quadros (4x4), branco: a cor da gema vem do PRIM_COLOR'


def digits_atlas():
    """0-9 em 4x4 quadros de 128 px, fonte grossa, branco sobre transparente."""
    S = 128
    atlas = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
    font = None
    for cand in ('arialbd.ttf', 'seguibl.ttf', 'segoeuib.ttf', 'DejaVuSans-Bold.ttf'):
        try:
            font = ImageFont.truetype(cand, 104)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()
    for n in range(10):
        fr = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(fr)
        txt = str(n)
        box = d.textbbox((0, 0), txt, font=font)
        d.text(((S - (box[2] - box[0])) / 2 - box[0], (S - (box[3] - box[1])) / 2 - box[1]),
               txt, font=font, fill=(255, 255, 255, 255))
        atlas.paste(fr, ((n % 4) * S, (n // 4) * S))
    out = os.path.join(TEX, 'CG_digits_atlas_512x512.png')
    atlas.save(out, optimize=True)
    return out, '0-9 em 4x4 (indice = digito)'


def main():
    os.makedirs(TEX, exist_ok=True)
    for fn in (gems_atlas, fx_atlas, digits_atlas):
        path, note = fn()
        print('%-34s %6.0f KB  %s' % (os.path.basename(path), os.path.getsize(path) / 1024, note))
    print('\nUpload no SL: L$ 10 por textura (3 texturas = L$ 30).')


if __name__ == '__main__':
    main()
