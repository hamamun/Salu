// Verification harness — runs the QR encoder that ships inside index.html
// against the Python `qrcode` 8.2 reference.
//
//   node design/remote-preview/qr_test.mjs
//
// Requires: python3 with `qrcode` installed (pip3 install qrcode).
// For every payload it reads the reference's own format bits to learn which
// mask Python chose, then demands a module-for-module identical matrix from
// the JS encoder with that mask pinned. Nothing here re-implements the
// encoder — it imports the exact block that ships in the page.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, 'index.html'), 'utf8');

const start = html.indexOf('/* ==== QR-BLOCK-START ==== */');
const end = html.indexOf('/* ==== QR-BLOCK-END ==== */');
if (start < 0 || end < 0) throw new Error('QR block markers not found in index.html');

const mod = await import('data:text/javascript,' + encodeURIComponent(
  html.slice(start, end) + '\nexport { encodeQr, qrFormatBits };',
));
const { encodeQr, qrFormatBits } = mod;

const rows = (m) => m.map(r => r.map(v => (v ? '#' : '.')).join('')).join('\n');

function pythonQr(text, ecLevel) {
  // QRData(..., mode=MODE_8BIT_BYTE) forces byte mode: left to itself the
  // library picks alphanumeric/numeric for short payloads, which is a
  // different encoder than the one shipping in the page.
  const py = `
import qrcode, sys
from qrcode.constants import ERROR_CORRECT_${ecLevel}
from qrcode.util import QRData, MODE_8BIT_BYTE
q = qrcode.QRCode(error_correction=ERROR_CORRECT_${ecLevel}, box_size=1, border=0)
q.add_data(QRData(sys.argv[1], mode=MODE_8BIT_BYTE))
q.make(fit=True)
print(q.version)
print(len(sys.argv[1].encode('utf-8')))
for r in q.modules:
    print(''.join('#' if v else '.' for v in r))
`;
  const out = execFileSync('python3', ['-c', py, text], { encoding: 'utf8' });
  const lines = out.trim().split('\n');
  return { version: Number(lines[0]), byteLen: Number(lines[1]), rows: lines.slice(2) };
}

/** Read a matrix's format copy 1 (bit i at COPY1[i], LSB first). */
function readFormat(g) {
  const COPY1 = [[0, 8], [1, 8], [2, 8], [3, 8], [4, 8], [5, 8], [7, 8], [8, 8],
                 [8, 7], [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0]];
  let f = 0;
  COPY1.forEach(([r, c], i) => { if (g[r][c]) f |= 1 << i; });
  for (const ec of ['L', 'M', 'Q', 'H']) {
    for (let mask = 0; mask < 8; mask++) {
      if (qrFormatBits(ec, mask) === f) return { ec, mask };
    }
  }
  return null;
}

const cases = [
  ['salu://pair?v=1&n=DESKTOP-ABC&h=192.168.0.12&p=7258&c=7K4MQP2X', 'M'],
  ['salu://pair?v=1&n=PC&h=10.0.0.5&p=7258&c=A1B2C3D4', 'M'],
  ['salu://pair?v=1&n=LIVING-ROOM-PC-2&h=192.168.100.245&p=65535&c=ZZZZZZZZ', 'M'],
  ['salu://pair?v=1&n=A&h=1.1.1.1&p=1&c=12345678', 'M'],
  ['https://example.com/', 'M'],
  ['A', 'M'],
  ['salu://pair?' + 'x'.repeat(60) + '&y=1', 'M'],
  ['salu://pair?' + 'x'.repeat(120) + '&y=1', 'M'],
  ['hello world 0123456789', 'M'],
  ['salu://pair?v=1&n=DESKTOP-ABC&h=192.168.0.12&p=7258&c=7K4MQP2X', 'L'],
  ['salu://pair?v=1&n=DESKTOP-ABC&h=192.168.0.12&p=7258&c=7K4MQP2X', 'Q'],
  ['salu://pair?v=1&n=DESKTOP-ABC&h=192.168.0.12&p=7258&c=7K4MQP2X', 'H'],
];

let pass = 0, fail = 0, maskAgree = 0;
for (const [text, ec] of cases) {
  let ref, mine, auto;
  try {
    ref = pythonQr(text, ec);
    const refGrid = ref.rows.map(r => [...r].map(ch => ch === '#'));
    const fmt = readFormat(refGrid);
    const label = `${text.length > 40 ? text.slice(0, 39) + '…' : text} [${ec}]`;
    if (!fmt || fmt.ec !== ec) {
      fail++;
      console.log(`FAIL  ${label} — could not read the reference's format bits`);
      continue;
    }
    mine = encodeQr(text, ec, { fixedMask: fmt.mask });
    auto = encodeQr(text, ec);
    const exact = mine.version === ref.version && rows(mine.modules) === ref.rows.join('\n');
    if (auto.mask === fmt.mask) maskAgree++;
    if (exact) {
      pass++;
      console.log(`PASS  v${mine.version} ${mine.size}x${mine.size} mask ${fmt.mask}` +
                  `${auto.mask === fmt.mask ? '' : ` (auto picked ${auto.mask})`}  ${label}`);
    } else {
      fail++;
      console.log(`FAIL  v${mine.version}/${ref.version} mask ${fmt.mask}  ${label}`);
      const a = rows(mine.modules).split('\n');
      for (let i = 0; i < Math.max(a.length, ref.rows.length); i++) {
        if (a[i] !== ref.rows[i]) console.log(`  row ${i}\n    mine ${a[i]}\n    ref  ${ref.rows[i]}`);
      }
    }
  } catch (err) {
    fail++;
    console.log(`ERROR ${text.slice(0, 40)}… [${ec}] — ${err.message.split('\n')[0]}`);
  }
}
console.log(`\n${pass} passed, ${fail} failed · mask choice agreed with the reference in ${maskAgree}/${cases.length}`);
process.exit(fail ? 1 : 0);
