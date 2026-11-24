'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const moduleDir = path.join(root, 'modules');
const domainDir = path.join(root, 'domain');
const files = [
  path.join(root, 'base.js'),
  ...fs.readdirSync(domainDir)
    .filter(name => name.endsWith('.js'))
    .sort()
    .map(name => path.join(domainDir, name)),
  ...fs.readdirSync(moduleDir)
    .filter(name => name.endsWith('.js'))
    .sort()
    .map(name => path.join(moduleDir, name))
];

function check(file, label = path.relative(root, file)) {
  const result = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8' });
  if (result.status !== 0) {
    process.stderr.write(result.stderr || result.stdout);
    throw new Error('Error de sintaxis JavaScript: ' + label);
  }
  process.stdout.write('OK JavaScript: ' + label + '\n');
}

for (const file of files) {
  if (!fs.existsSync(file)) throw new Error('No existe el archivo esperado: ' + file);
  check(file);
}

// También valida el JavaScript inline de index.html sin ejecutarlo en Node.
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const inlineScripts = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
if (!inlineScripts.length) throw new Error('No se encontraron scripts inline en index.html');
for (let i = 0; i < inlineScripts.length; i++) {
  const temp = path.join(os.tmpdir(), 'drosalud-inline-' + process.pid + '-' + i + '.js');
  try {
    fs.writeFileSync(temp, inlineScripts[i][1], 'utf8');
    check(temp, 'index.html inline #' + (i + 1));
  } finally {
    try { fs.unlinkSync(temp); } catch {}
  }
}
