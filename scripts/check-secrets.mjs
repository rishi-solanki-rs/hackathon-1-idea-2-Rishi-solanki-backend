// Fallback secret scan for tracked and untracked (non-ignored) files. gitleaks (Docker) is the primary scan.
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const patterns = [
  ['Duffel token', /duffel_(test|live)_[A-Za-z0-9_-]{16,}/],
  ['Supabase secret key', /sb_secret_[A-Za-z0-9_-]{16,}/],
  ['GitHub token', /gh[pousr]_[A-Za-z0-9]{30,}/],
  ['AWS access key', /AKIA[0-9A-Z]{16}/],
  ['OpenAI-style key', /sk-[A-Za-z0-9]{32,}/],
  ['JWT', /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}/],
  ['Private key', /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
];

const files = execSync('git ls-files --cached --others --exclude-standard', { encoding: 'utf8' })
  .split('\n')
  .filter((f) => f && !f.endsWith('pnpm-lock.yaml') && !/\.(png|jpe?g|webp|ico|woff2?)$/i.test(f));

const findings = [];
for (const file of files) {
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    continue;
  }
  for (const [name, re] of patterns) {
    if (re.test(text)) findings.push(`${file}: ${name}`);
  }
}

if (findings.length) {
  console.error(`Secret scan FAILED (${findings.length}):\n${findings.join('\n')}`);
  process.exit(1);
}
console.log(`Secret scan passed: ${files.length} files, 0 findings.`);
