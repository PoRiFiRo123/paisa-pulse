// Builds assets/pdf/extractor.html: a self-contained page that runs pdf.js (from the
// pdfjs-dist devDependency) and returns positioned text for a statement PDF.
// The app loads it in a hidden WebView, so PDFs are read on-device with no network.
// Run: node scripts/build-pdf-extractor.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const lib = readFileSync('node_modules/pdfjs-dist/legacy/build/pdf.min.mjs', 'utf8');
const worker = readFileSync('node_modules/pdfjs-dist/legacy/build/pdf.worker.min.mjs', 'utf8');
const version = JSON.parse(readFileSync('node_modules/pdfjs-dist/package.json', 'utf8')).version;
// JSON-encode the code and keep "</script>" from closing our tag.
const embed = (code) => JSON.stringify(code).replace(/<\//g, '<\\/');

const html = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="pdfjs-version" content="${version}"></head><body>
<script>
(function () {
  var LIB = ${embed(lib)};
  var WORKER = ${embed(worker)};
  var url = function (code) { return URL.createObjectURL(new Blob([code], { type: 'text/javascript' })); };
  var ready = null;
  function load() {
    if (!ready) {
      ready = import(url(LIB)).then(function (pdfjs) {
        pdfjs.GlobalWorkerOptions.workerSrc = url(WORKER);
        return pdfjs;
      });
    }
    return ready;
  }
  function toBytes(base64) {
    var bin = atob(base64);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  // Returns { ok: true, pages, items: [{ str, x, y, w, h, page }] } with y measured from the top,
  // or { ok: false, error: 'password' | 'incorrect-password' | message }.
  window.extractPdf = async function (base64, password) {
    try {
      var pdfjs = await load();
      var doc = await pdfjs.getDocument({ data: toBytes(base64), password: password || undefined, isEvalSupported: false }).promise;
      var items = [];
      for (var p = 1; p <= doc.numPages; p++) {
        var page = await doc.getPage(p);
        var viewport = page.getViewport({ scale: 1 });
        var content = await page.getTextContent();
        content.items.forEach(function (it) {
          if (!it.str || !it.str.trim()) return;
          var t = it.transform;
          var h = it.height || Math.hypot(t[2], t[3]);
          items.push({ str: it.str, x: t[4], y: viewport.height - t[5] - h, w: it.width, h: h, page: p });
        });
      }
      return { ok: true, pages: doc.numPages, items: items };
    } catch (e) {
      var name = e && e.name;
      if (name === 'PasswordException') return { ok: false, error: e.code === 2 ? 'incorrect-password' : 'password' };
      return { ok: false, error: String((e && e.message) || e) };
    }
  };
  // React Native bridge: { id, base64, password } in → { id, ...result } out.
  function onMessage(event) {
    var msg;
    try { msg = JSON.parse(event.data); } catch (e) { return; }
    if (!msg || !msg.id) return;
    window.extractPdf(msg.base64, msg.password).then(function (result) {
      result.id = msg.id;
      window.ReactNativeWebView && window.ReactNativeWebView.postMessage(JSON.stringify(result));
    });
  }
  window.addEventListener('message', onMessage);
  document.addEventListener('message', onMessage);
  window.ReactNativeWebView && window.ReactNativeWebView.postMessage(JSON.stringify({ ready: true }));
})();
</script>
</body></html>
`;
writeFileSync('assets/pdf/extractor.html', html);
console.log(`assets/pdf/extractor.html (${(html.length / 1024).toFixed(0)} KB, pdf.js ${version})`);
