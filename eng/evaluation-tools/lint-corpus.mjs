import { readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ansiPattern = /\u001b\[[0-?]*[ -/]*[@-~]/g;

function normalizePath(path) {
  return path.replaceAll('\\', '/').replace(/^\.\//, '');
}

export function discoverEvalSpecs(root, cwd = process.cwd()) {
  const specs = [];

  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = resolve(directory, entry.name);
      if (entry.isDirectory()) {
        visit(path);
      } else if (entry.isFile() && entry.name === 'eval.yaml') {
        specs.push(normalizePath(relative(cwd, path)));
      }
    }
  }

  visit(resolve(cwd, root));
  return specs.sort();
}

export function reportedEvalSpecs(output) {
  const specs = new Set();
  const cleanOutput = output.replace(ansiPattern, '');
  for (const match of cleanOutput.matchAll(/^Eval:\s+(.+?eval\.yaml)\s*$/gmi)) {
    specs.add(normalizePath(match[1].trim()));
  }
  return [...specs].sort();
}

export function validateCorpusLint({
  root = 'tests',
  cwd = process.cwd(),
  vallyScript = fileURLToPath(new URL('./vally.mjs', import.meta.url)),
} = {}) {
  const expected = discoverEvalSpecs(root, cwd);
  const result = spawnSync(
    process.execPath,
    [vallyScript, 'lint', '--eval-spec', root],
    {
      cwd,
      encoding: 'utf8',
      maxBuffer: 16 * 1024 * 1024,
    },
  );

  process.stdout.write(result.stdout ?? '');
  process.stderr.write(result.stderr ?? '');

  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`Vally corpus lint failed with exit code ${result.status}.`);
  }

  const reported = reportedEvalSpecs(`${result.stdout ?? ''}\n${result.stderr ?? ''}`);
  const expectedSet = new Set(expected);
  const reportedSet = new Set(reported);
  const missing = expected.filter(path => !reportedSet.has(path));
  const unexpected = reported.filter(path => !expectedSet.has(path));

  if (missing.length > 0 || unexpected.length > 0) {
    const details = [
      missing.length > 0 ? `Missing (${missing.length}): ${missing.join(', ')}` : null,
      unexpected.length > 0 ? `Unexpected (${unexpected.length}): ${unexpected.join(', ')}` : null,
    ].filter(Boolean).join('\n');
    throw new Error(
      `Vally reported ${reported.length}/${expected.length} discovered eval specs.\n${details}`,
    );
  }

  console.log(`Validated ${reported.length}/${expected.length} eval specs with Vally.`);
  return { expected, reported };
}

const invokedPath = process.argv[1] ? resolve(process.argv[1]) : null;
if (invokedPath === fileURLToPath(import.meta.url)) {
  try {
    validateCorpusLint({ root: process.argv[2] ?? 'tests' });
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}
