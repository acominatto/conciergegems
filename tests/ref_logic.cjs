// Referencia para os testes: roda o logic.js ORIGINAL (public/games/bubble-match/js/logic.js) e as formulas de niveis
// extraidas do main.js ORIGINAL, e imprime JSON. Nao altera nenhum arquivo do jogo HTML.
// Uso: echo '{"op":"resolve", ...}' | node ref_logic.cjs
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..', 'public', 'games', 'bubble-match', 'js');
// o package.json da raiz declara "type": "module", entao require() de logic.js o trataria como ESM e quebraria o UMD.
// Le o texto e executa num escopo CommonJS (o arquivo original nao e alterado).
const logicModule = { exports: {} };
new Function('module', 'exports', fs.readFileSync(path.join(ROOT, 'logic.js'), 'utf8'))(logicModule, logicModule.exports);
const L = logicModule.exports;

// ---- formulas de dificuldade/nivel: copiadas do main.js (mesmo texto, sem DOM) ----
const mainSrc = fs.readFileSync(path.join(ROOT, 'main.js'), 'utf8');
const from = mainSrc.indexOf('const DIFFICULTIES = {');
const to = mainSrc.indexOf('const timeCap = (diff)');
const toEnd = mainSrc.indexOf('\n', to);
const formulas = new Function(`${mainSrc.slice(from, toEnd)}\n return { DIFFICULTIES, levelTarget, levelColors, levelDrain, levelTimeBonus, timeCap };`)();

const SPECIALS = [null, 'bomb', 'star', 'rainbow'];
const enc = (cell) => (cell ? cell.color + 8 * SPECIALS.indexOf(cell.special || null) : -1);

function makeRand(list) {
  let i = 0;
  const f = () => { if (i >= list.length) throw new Error('lista de aleatorios esgotada'); return list[i++]; };
  f.used = () => i;
  return f;
}

function toGrid(vals) {
  const g = L.makeGrid();
  for (let r = 0; r < 8; r += 1) {
    for (let c = 0; c < 8; c += 1) {
      const v = vals[r * 8 + c];
      g[r][c] = v < 0 ? null : L.newCell(v % 8, SPECIALS[Math.floor(v / 8)]);
    }
  }
  return g;
}

function fromGrid(g) { const out = []; for (let r = 0; r < 8; r += 1) for (let c = 0; c < 8; c += 1) out.push(enc(g[r][c])); return out; }
const idx = (rc) => rc[0] * 8 + rc[1];

function waveJson(w, before) {
  const val = (cell) => enc(cell);
  return {
    chain: w.chain, points: w.points, timeBonus: w.timeBonus,
    cleared: w.cleared.map((x) => x.r * 8 + x.c).sort((a, b) => a - b),
    created: w.created.map((x) => [x.r * 8 + x.c, val(x.cell)]).sort((a, b) => a[0] - b[0]),
    falls: w.falls.map((f) => [f.c, f.from, f.to, val(f.cell)]),
    spawns: w.spawns.map((s) => [s.c, s.from, s.to, val(s.cell)]),
  };
}

const input = JSON.parse(fs.readFileSync(0, 'utf8'));
let out;
if (input.op === 'initial') {
  const rand = makeRand(input.rand);
  out = { grid: fromGrid(L.initialBoard(rand, input.colors)), used: rand.used() };
} else if (input.op === 'shuffle') {
  const g = toGrid(input.grid);
  const rand = makeRand(input.rand);
  const ok = L.shuffle(g, rand);
  out = { ok, grid: fromGrid(g), used: rand.used() };
} else if (input.op === 'valid') {
  const g = toGrid(input.grid);
  const res = [];
  for (let r = 0; r < 8; r += 1) {
    for (let c = 0; c < 8; c += 1) {
      if (c + 1 < 8) res.push([r * 8 + c, r * 8 + c + 1, L.isValidSwap(g, [r, c], [r, c + 1])]);
      if (r + 1 < 8) res.push([r * 8 + c, (r + 1) * 8 + c, L.isValidSwap(g, [r, c], [r + 1, c])]);
    }
  }
  const h = L.findHint(g);
  out = { pairs: res, hint: h ? [idx(h[0]), idx(h[1])] : null, hasMoves: L.hasMoves(g) };
} else if (input.op === 'resolve') {
  const g = toGrid(input.grid);
  const a = [Math.floor(input.a / 8), input.a % 8];
  const b = [Math.floor(input.b / 8), input.b % 8];
  const valid = L.isValidSwap(g, a, b);
  if (!valid) {
    out = { valid: false };
  } else {
    L.swapCells(g, a, b);
    const rand = makeRand(input.rand);
    const waves = L.resolve(g, { a, b }, rand, input.colors);
    out = { valid: true, waves: waves.map((w) => waveJson(w)), grid: fromGrid(g), used: rand.used() };
  }
} else if (input.op === 'formulas') {
  const rows = [];
  ['easy', 'normal', 'hard'].forEach((name, di) => {
    const d = formulas.DIFFICULTIES[name];
    for (let level = 1; level <= 40; level += 1) {
      rows.push({ diff: di, level, target: formulas.levelTarget(level, d), colors: formulas.levelColors(level, d),
        drain: formulas.levelDrain(level, d), timeBonus: formulas.levelTimeBonus(level, d), cap: formulas.timeCap(d), start: d.startTime,
        bonus: d.bonus, hintDelay: d.hintDelay });
    }
  });
  out = { rows };
} else {
  throw new Error(`op desconhecida: ${input.op}`);
}
process.stdout.write(JSON.stringify(out));
