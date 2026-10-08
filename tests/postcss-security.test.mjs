import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {createRequire} from 'node:module';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

// Exercise the dependency resolved by Next's CSS pipeline, including overrides.
const require = createRequire(import.meta.url);
const postcss = createRequire(require.resolve('next/package.json'))('postcss');
const marker = 'SYNTHETIC_OUT_OF_TREE_SOURCE';
const previousMap = content => ({version: 3, sources: ['synthetic-source.css'],
  sourcesContent: [content], names: [], mappings: 'AAAA'});
// Next runs plugins; force the parsing path rather than the empty-plugin fast path.
const parsePlugin = {postcssPlugin: 'synthetic-parse', Once() {}};

async function fixture(t) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'eventcore-postcss-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const styles = path.join(root, 'styles');
  await mkdir(styles);
  await writeFile(path.join(root, 'outside.map'), JSON.stringify(previousMap(marker)));
  await writeFile(path.join(root, 'outside.txt'), 'SYNTHETIC_NON_JSON_CONTENT');
  return {root, styles, from: path.join(styles, 'input.css')};
}

test('Next CSS processing does not disclose a source map outside the from directory', async t => {
  const {from} = await fixture(t);
  const result = await postcss([parsePlugin]).process('a{color:red}\n/*# sourceMappingURL=../outside.map */',
    {from, map: {inline: false}});
  assert.ok(!JSON.stringify(result.map?.toJSON()).includes(marker), 'outside source content was disclosed');
});

test('Next CSS processing ignores an absolute source map URI when from is unset', async t => {
  const {root} = await fixture(t);
  const result = await postcss([parsePlugin]).process(`a{color:red}\n/*# sourceMappingURL=${path.join(root, 'outside.map')} */`,
    {from: undefined, map: {inline: false}});
  assert.ok(!JSON.stringify(result.map?.toJSON()).includes(marker), 'absolute source content was disclosed');
});

test('Next CSS processing does not surface out-of-tree non-JSON file bytes', async t => {
  const {from} = await fixture(t);
  await assert.doesNotReject(async () => {
    await postcss([parsePlugin]).process('a{color:red}\n/*# sourceMappingURL=../outside.txt */',
      {from, map: {inline: false}});
  });
});

test('CSS AST stringify cannot close an embedding HTML style element', () => {
  const root = postcss.parse('body { content: "</style><script>synthetic()</script><style>"; }');
  assert.doesNotMatch(root.toResult({map: false}).css, /<\/style[\s>]/i);
});

test('Next CSS processing preserves ordinary declarations and plugin transforms', async t => {
  const {from} = await fixture(t);
  const plugin = {postcssPlugin: 'synthetic-transform', Declaration(decl) {
    if (decl.prop === 'color' && decl.value === 'red') decl.value = 'blue';
  }};
  const result = await postcss([plugin]).process('a { color: red; display: flex; }', {from, map: false});
  assert.equal(result.css, 'a { color: blue; display: flex; }');
  assert.equal(result.warnings().length, 0);
});

test('Next CSS processing preserves a legitimate adjacent source map', async t => {
  const {styles, from} = await fixture(t);
  await writeFile(path.join(styles, 'input.css.map'), JSON.stringify(previousMap('LEGITIMATE_ADJACENT_SOURCE')));
  const result = await postcss([parsePlugin]).process('a{color:red}\n/*# sourceMappingURL=input.css.map */',
    {from, map: {inline: false}});
  assert.ok(result.map.toJSON().sourcesContent.includes('LEGITIMATE_ADJACENT_SOURCE'));
});

test('Next CSS processing preserves an inline source map without a from option', async () => {
  const inline = Buffer.from(JSON.stringify(previousMap('LEGITIMATE_INLINE_SOURCE'))).toString('base64');
  const result = await postcss([parsePlugin]).process(`a{color:red}\n/*# sourceMappingURL=data:application/json;base64,${inline} */`,
    {from: undefined, map: {inline: false}});
  assert.ok(result.map.toJSON().sourcesContent.includes('LEGITIMATE_INLINE_SOURCE'));
});
