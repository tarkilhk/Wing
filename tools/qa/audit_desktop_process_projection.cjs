// Read-only audit of the installed Desktop's real hydration and renderer rules.
// Usage: node tools/qa/audit_desktop_process_projection.cjs <hermes-agent checkout>
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const Module = require('node:module');
const assert = require('node:assert/strict');
const root = path.resolve(process.argv[2]);
const fromDesktop = Module.createRequire(path.join(root, 'apps/desktop/package.json'));
const esbuild = fromDesktop('esbuild');
const ts = fromDesktop('typescript');
const desktop = path.join(root, 'apps/desktop');
const sourcePath = path.join(desktop, 'src/components/assistant-ui/thread/user-message.tsx');
const source = ts.createSourceFile(sourcePath, fs.readFileSync(sourcePath, 'utf8'), ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
let processInitializer;
function visit(node) {
  if (ts.isVariableDeclaration(node) && node.name.getText(source) === 'PROCESS_NOTIFICATION_RE') {
    processInitializer = node.initializer.getText(source);
  }
  ts.forEachChild(node, visit);
}
visit(source);
assert.ok(processInitializer, 'Desktop process rule must exist');
const processRule = vm.runInNewContext(processInitializer);
const compiled = esbuild.buildSync({
  absWorkingDir: desktop,
  entryPoints: ['src/lib/chat-messages/hydration.ts'],
  bundle: true,
  platform: 'node',
  format: 'cjs',
  write: false,
  define: { 'import.meta.hot': 'undefined', 'import.meta.env': '{}' },
  alias: { '@': path.join(desktop, 'src') },
});
const hydration = new Module(path.join(desktop, 'audit-hydration.cjs'));
hydration.filename = path.join(desktop, 'audit-hydration.cjs');
hydration.paths = Module._nodeModulePaths(desktop);
hydration._compile(compiled.outputFiles[0].text, hydration.filename);
const single = '[IMPORTANT: Background process proc_test completed normally (exit code 0).\nCommand: test\nOutput:\nOK\n]';
const batch = '[IMPORTANT: 16 background processes completed. Treat these results as one batch and give one consolidated response; preserve failures and actionable results.]\n\n' + Array(16).fill(single).join('\n\n');
const cases = [
  ['single process', { role: 'user', content: single }],
  ['16-process batch', { role: 'user', content: batch }],
  ['typed hidden batch', { role: 'user', content: batch, display_kind: 'hidden' }],
  ['typed internal_notification batch', { role: 'user', content: batch, display_kind: 'internal_notification' }],
  ['typed delegation', { role: 'user', content: 'private payload', display_kind: 'async_delegation_complete', display_metadata: { task_count: 16 } }],
];
const findings = cases.map(([name, row]) => {
  const messages = hydration.exports.toChatMessages([{ ...row, timestamp: 1 }]);
  const message = messages[0];
  const text = message?.parts.filter(part => part.type === 'text').map(part => part.text).join('') || '';
  const presentation = !message ? 'hidden' : message.role === 'user' ? processRule.test(text.trim()) ? 'process notice' : 'human bubble' : 'system notice';
  return { name, presentation, rawBatchSurvives: text === batch };
});
assert.equal(findings[0].presentation, 'process notice');
assert.equal(findings[1].presentation, 'human bubble');
assert.equal(findings[1].rawBatchSurvives, true);
assert.equal(findings[2].presentation, 'hidden');
assert.equal(findings[3].presentation, 'human bubble');
assert.equal(findings[4].presentation, 'system notice');
console.log(JSON.stringify({ sourcePath, processInitializer, findings }, null, 2));
