#!/usr/bin/env node
let versions;
try {
  versions = JSON.parse(require('fs').readFileSync(0, 'utf8'));
} catch {
  process.exit(1);
}
if (!Array.isArray(versions) || versions.length === 0) process.exit(1);

const pre = (v) => v.split('+')[0].split('-');
const nums = (v) => pre(v)[0].split('.').map(Number);

function cmp(a, b) {
  const [an, bn] = [nums(a), nums(b)];
  for (let i = 0; i < 3; i++) if (an[i] !== bn[i]) return an[i] - bn[i];
  const [ap, bp] = [pre(a)[1], pre(b)[1]];
  if (ap === undefined || bp === undefined) {
    return ap === bp ? 0 : ap === undefined ? 1 : -1;
  }
  const [A, B] = [ap.split('.'), bp.split('.')];
  for (let i = 0; i < A.length || i < B.length; i++) {
    if (A[i] === undefined) return -1;
    if (B[i] === undefined) return 1;
    const [x, y] = [/^\d+$/.test(A[i]), /^\d+$/.test(B[i])];
    if (x && y) {
      const d = A[i] - B[i];
      if (d) return d;
    } else if (x !== y) {
      return x ? -1 : 1;
    } else if (A[i] !== B[i]) {
      return A[i] < B[i] ? -1 : 1;
    }
  }
  return 0;
}

const channel = (process.argv[2] || process.env.DSH_CHANNEL || 'rc').toLowerCase();

function matchChannel(v, ch) {
  const p = pre(v)[1];
  if (!p) return true;
  const tag = p.split('.')[0].toLowerCase();
  switch (ch) {
    case 'stable':
      return false;
    case 'rc':
      return tag === 'rc';
    case 'beta':
      return tag === 'rc' || tag === 'beta';
    case 'alpha':
    case 'all':
    default:
      return true;
  }
}

const candidates = versions.filter((v) => matchChannel(v, channel));
if (candidates.length === 0) process.exit(1);

console.log(candidates.reduce((max, v) => (cmp(v, max) > 0 ? v : max)));
