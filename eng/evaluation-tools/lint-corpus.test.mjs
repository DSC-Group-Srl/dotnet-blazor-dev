import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { validateCorpusLint } from './lint-corpus.mjs';

function fixture({ reported, exitCode = 0 }) {
  const root = mkdtempSync(join(tmpdir(), 'vally-corpus-lint-'));
  const tests = join(root, 'tests');
  for (const path of ['plugin-a/skill-a', 'plugin-b/skill-b']) {
    const directory = join(tests, path);
    mkdirSync(directory, { recursive: true });
    writeFileSync(join(directory, 'eval.yaml'), 'name: sample\nstimuli: []\n');
  }

  const vally = join(root, 'fake-vally.mjs');
  const output = reported.map(path => `Eval: ${path}`).join('\n');
  writeFileSync(
    vally,
    `process.stdout.write(${JSON.stringify(`${output}\n`)}); process.exitCode = ${exitCode};\n`,
  );

  return {
    root,
    vally,
    cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}

test('accepts a successful lint that reports every discovered eval', () => {
  const item = fixture({
    reported: [
      'tests/plugin-a/skill-a/eval.yaml',
      'tests\\plugin-b\\skill-b\\eval.yaml',
    ],
  });
  try {
    const result = validateCorpusLint({
      root: 'tests',
      cwd: item.root,
      vallyScript: item.vally,
    });
    assert.equal(result.reported.length, 2);
  } finally {
    item.cleanup();
  }
});

test('rejects a successful lint that silently omits an eval', () => {
  const item = fixture({ reported: ['tests/plugin-a/skill-a/eval.yaml'] });
  try {
    assert.throws(
      () => validateCorpusLint({
        root: 'tests',
        cwd: item.root,
        vallyScript: item.vally,
      }),
      /reported 1\/2 discovered eval specs[\s\S]*skill-b/,
    );
  } finally {
    item.cleanup();
  }
});

test('rejects a failed Vally lint before accepting corpus accounting', () => {
  const item = fixture({
    reported: [
      'tests/plugin-a/skill-a/eval.yaml',
      'tests/plugin-b/skill-b/eval.yaml',
    ],
    exitCode: 1,
  });
  try {
    assert.throws(
      () => validateCorpusLint({
        root: 'tests',
        cwd: item.root,
        vallyScript: item.vally,
      }),
      /failed with exit code 1/,
    );
  } finally {
    item.cleanup();
  }
});
