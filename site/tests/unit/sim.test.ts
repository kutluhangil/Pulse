import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fmtRate, next, sparkPath } from '../../src/scripts/sim.ts';

test('simulated samples stay believable', () => {
  for (let i = 0; i < 500; i++) {
    const s = next();
    assert.ok(s.cpu >= 1 && s.cpu <= 60, `cpu ${s.cpu}`);
    assert.ok(s.temp > 45 && s.temp < 70, `temp ${s.temp}`);
    assert.ok(s.mem > 6 && s.mem < 10);
    assert.ok(s.rx >= 300 && s.tx >= 120);
  }
});

test('rates read like the apps', () => {
  assert.equal(fmtRate(7_400), '7 KB/s');
  assert.equal(fmtRate(3_400_000), '3.4 MB/s');
  assert.equal(fmtRate(240_000_000), '240 MB/s');
});

test('sparkline path spans the width', () => {
  const d = sparkPath([0, 50, 100], 200, 34, 100);
  assert.ok(d.startsWith('M0.0,32.0'));
  assert.ok(d.endsWith('L200.0,2.0'));
});
