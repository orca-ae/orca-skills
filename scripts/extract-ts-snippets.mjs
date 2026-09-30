#!/usr/bin/env node
// Copyright The Orca Authors
// SPDX-License-Identifier: Apache-2.0

// Extract ```ts / ```typescript fences from the skill's markdown into
// scripts/.snippets/ts/*.ts so tsc can typecheck them against the published SDK.
//
// Per markdown file, fences are concatenated in order into one .ts file, so
// variables introduced early ("const session = ...") stay in scope for later
// fences, matching how the prose reads. Directives on the line immediately
// before a fence:
//   <!-- ts-check: skip -->    fence is a fragment; do not typecheck it
//   <!-- ts-check: reset -->   start a fresh scope file at this fence
//
// Duplicate top-level `import` lines are hoisted and deduped per output file,
// and `export {}` is appended (isolatedModules treats importless files as
// global scripts otherwise).
//
// A markdown file may carry one or more hidden context blocks:
//   <!-- ts-check-context
//   declare const orca: import('@runorca/orca-sdk').default;
//   -->
// Their lines are prepended to every scope file generated from that markdown,
// except lines declaring a name the group itself declares (`declare const X`
// is skipped when the group has its own `const X = ...`). Use inline
// import('...') types, not import statements, to avoid binding collisions.
//
// The compiler settings live in scripts/tsconfig.snippets.json. '@runorca/orca-sdk'
// resolves to scripts/node_modules, installed by `npm ci --prefix scripts`.

import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const skillRoot = path.join(repoRoot, 'skills', 'orca-api');
const outDir = path.join(repoRoot, 'scripts', '.snippets', 'ts');

async function mdFiles(dir) {
  const out = [];
  for (const e of await fs.readdir(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...(await mdFiles(p)));
    else if (e.name.endsWith('.md')) out.push(p);
  }
  return out.sort();
}

function extract(markdown) {
  // Returns {fences: [{code, skip, reset}], context: string[]} in document order.
  const lines = markdown.split('\n');
  const fences = [];
  const context = [];
  let i = 0;
  while (i < lines.length) {
    if (lines[i].trim() === '<!-- ts-check-context') {
      i++;
      while (i < lines.length && lines[i].trim() !== '-->') context.push(lines[i++]);
      i++;
      continue;
    }
    const m = lines[i].match(/^```(ts|typescript)\s*$/);
    if (!m) { i++; continue; }
    let directive = '';
    for (let j = i - 1; j >= 0; j--) {
      const t = lines[j].trim();
      if (t === '') continue;
      const d = t.match(/^<!-- ts-check: (skip|reset) -->$/);
      if (d) directive = d[1];
      break;
    }
    const body = [];
    i++;
    while (i < lines.length && !lines[i].startsWith('```')) body.push(lines[i++]);
    i++; // closing fence
    fences.push({ code: body.join('\n'), skip: directive === 'skip', reset: directive === 'reset' });
  }
  return { fences, context };
}

function assemble(fences, context) {
  // Group fences into scope files at reset boundaries; hoist+dedup imports;
  // prepend context declares the group does not shadow with its own bindings.
  const groups = [];
  let current = [];
  for (const f of fences) {
    if (f.skip) continue;
    if (f.reset && current.length) { groups.push(current); current = []; }
    current.push(f.code);
  }
  if (current.length) groups.push(current);
  return groups.map((codes) => {
    const imports = new Set();
    const rest = [];
    for (const code of codes) {
      for (const line of code.split('\n')) {
        if (/^import\s/.test(line)) imports.add(line);
        else rest.push(line);
      }
      rest.push('');
    }
    const body = rest.join('\n');
    const ctx = context.filter((line) => {
      const d = line.match(/^declare\s+(?:const|let|function|class)\s+([A-Za-z_$][\w$]*)/);
      if (!d) return true;
      return !new RegExp(`\\b(const|let|var|function|class)\\s+${d[1]}\\b`).test(body);
    });
    return [...imports, '', ...ctx, '', body, 'export {};', ''].join('\n');
  });
}

const files = await mdFiles(skillRoot);
await fs.rm(outDir, { recursive: true, force: true });
await fs.mkdir(outDir, { recursive: true });

let fenceCount = 0;
let skipCount = 0;
let fileCount = 0;
for (const file of files) {
  const { fences, context } = extract(await fs.readFile(file, 'utf8'));
  fenceCount += fences.length;
  skipCount += fences.filter((f) => f.skip).length;
  const slug = path.relative(skillRoot, file).replace(/\.md$/, '').replace(/[^A-Za-z0-9]+/g, '-');
  const groups = assemble(fences, context);
  for (let g = 0; g < groups.length; g++) {
    const name = groups.length === 1 ? `${slug}.ts` : `${slug}-${g + 1}.ts`;
    await fs.writeFile(path.join(outDir, name), groups[g]);
    fileCount++;
  }
}

console.log(
  `extract-ts-snippets: ${fenceCount} ts fences -> ${fileCount} files (${skipCount} skipped) in ${path.relative(repoRoot, outDir)}`,
);
