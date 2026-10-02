// Executes the real capture bridge and installed model-viewer sceneSize method.
// Cases match the device-observed scene/global scale mismatch, without device IO.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

const dart = fs.readFileSync('lib/features/share/share_controller.dart', 'utf8');
const capture = dart.match(/static const String _captureScript = r'''([\s\S]*?)''';/)[1];
const bundlePath = process.argv[2] || path.join(
  process.env.PUB_CACHE || path.join(os.homedir(), '.pub-cache'),
  'hosted/pub.dev/model_viewer_plus-1.10.0/assets/model-viewer.min.js',
);
const bundle = fs.readFileSync(bundlePath, 'utf8');
const scales = bundle.match(/const Lf=\[([^\]]+)\]/)[1].split(',').map(Number);
const nextTurn = () => new Promise(resolve => setImmediate(resolve));

function method(start, stop) {
  const a = bundle.indexOf(start);
  const b = bundle.indexOf(stop, a);
  assert.ok(a >= 0 && b > a, 'installed implementation exists');
  return bundle.slice(a, b);
}

function fixture(sceneStep, {defer = false} = {}) {
  const draws = [];
  const outputs = [];
  const pending = [];
  const source = {width: 859, height: 903};
  const symbols = {wy: Symbol('scene'), Ry: Symbol('renderer'), dy: Symbol('resize')};
  class FileReader {
    readAsDataURL(blob) {
      queueMicrotask(() => {
        this.result = blob.dataUrl;
        this.onload();
      });
    }
  }
  const ctx = vm.createContext({window: {}, FileReader, Lf: scales});
  const renderer = {
    dpr: 2.625,
    scaleStep: 3,
    scaleFactor: 0.5,
    canvas3D: source,
    displayCanvas: () => source,
    sceneSize: vm.runInContext(
      `({${method('sceneSize(e){', 'copyPixels(e,')}})`, ctx,
    ).sceneSize,
  };
  const prototype = {};
  Object.defineProperty(prototype, symbols.Ry, {get: () => renderer});
  const viewer = Object.create(prototype);
  const scene = {width: 327.234375, height: 344, scaleStep: sceneStep};
  viewer[symbols.wy] = scene;
  viewer.toDataURL = () => assert.fail('must not export the shared canvas');
  viewer.toBlob = () => assert.fail('must not use the unrelated global scale');
  ctx.document = {
    querySelector: () => viewer,
    createElement(name) {
      assert.equal(name, 'canvas');
      const output = {
        width: 0,
        height: 0,
        getContext: () => ({drawImage: (...args) => draws.push(args)}),
        toBlob(callback, type) {
          assert.equal(type, 'image/png');
          if (defer) pending.push(callback);
          else queueMicrotask(() => callback({dataUrl: 'data:image/png;base64,Q1JPUA=='}));
        },
      };
      outputs.push(output);
      return output;
    },
  };
  return {ctx, renderer, scene, viewer, source, symbols, outputs, draws, pending};
}

function start(f, id) {
  vm.runInContext(capture.replaceAll('__CAPTURE_ID__', JSON.stringify(id)), f.ctx);
}

async function main() {
  const cases = [];
  for (const [step, dimensions] of [[0, [859, 903]], [3, [430, 452]]]) {
    const f = fixture(step);
    start(f, `scene-${step}`);
    await nextTurn();
    const output = f.outputs[0];
    assert.deepEqual([output.width, output.height], dimensions);
    assert.deepEqual(
      f.draws[0].slice(1),
      [0, 0, ...dimensions, 0, 0, ...dimensions],
    );
    assert.equal(f.ctx.window.__humanTwinSnapshot.result, 'data:image/png;base64,Q1JPUA==');
    assert.equal(f.ctx.window.__humanTwinSnapshot.error, false);
    cases.push({sceneScaleStep: step, globalScaleStep: 3, viewport: dimensions});
  }

  // Reproduce why the public toBlob method failed on the paused device: it crops
  // at global .5 even when the actual rendered scene is back at full resolution.
  const old = fixture(0);
  const publicCanvas = {
    width: 0,
    height: 0,
    getContext: () => ({drawImage() {}}),
    toBlob: callback => queueMicrotask(() => callback({})),
  };
  Object.assign(old.ctx, old.symbols, {iy: publicCanvas});
  const publicCapture = vm.runInContext(
    `({${method('async toBlob(e){const t=e?e.mimeType', 'registerEffectComposer')}})`,
    old.ctx,
  );
  publicCapture[old.symbols.wy] = old.scene;
  publicCapture[old.symbols.Ry] = old.renderer;
  publicCapture[old.symbols.dy] = () => {};
  await publicCapture.toBlob({mimeType: 'image/png', idealAspect: false});
  assert.ok(publicCanvas.width < old.renderer.sceneSize(old.scene).width);
  assert.ok(publicCanvas.height < old.renderer.sceneSize(old.scene).height);

  const concurrent = fixture(0, {defer: true});
  start(concurrent, 'old');
  start(concurrent, 'new');
  concurrent.pending[0]({dataUrl: 'data:image/png;base64,T0xE'});
  await nextTurn();
  assert.equal(concurrent.ctx.window.__humanTwinSnapshot.id, 'new');
  assert.equal(concurrent.ctx.window.__humanTwinSnapshot.result, '');
  concurrent.pending[1]({dataUrl: 'data:image/png;base64,TkVX'});
  await nextTurn();
  assert.equal(concurrent.ctx.window.__humanTwinSnapshot.result, 'data:image/png;base64,TkVX');

  const failed = fixture(0, {defer: true});
  start(failed, 'failure');
  failed.pending[0](null);
  assert.equal(failed.ctx.window.__humanTwinSnapshot.error, true);
  const unavailable = fixture(0);
  unavailable.ctx.document.querySelector = () => null;
  start(unavailable, 'missing-viewer');
  assert.equal(unavailable.ctx.window.__humanTwinSnapshot.error, true);
  const invalid = fixture(0);
  invalid.renderer.sceneSize = () => ({width: Infinity, height: 903});
  start(invalid, 'invalid-size');
  assert.equal(invalid.ctx.window.__humanTwinSnapshot.error, true);
  assert.equal(invalid.outputs.length, 0);
  console.log(JSON.stringify({passed: 7, cases, oldPublicCropMismatchReproduced: true}));
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
