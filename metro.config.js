const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// Drizzle migrations are bundled as .sql files.
config.resolver.sourceExts.push('sql');
// expo-sqlite on web runs SQLite as WebAssembly.
config.resolver.assetExts.push('wasm');

// expo-sqlite on web needs SharedArrayBuffer, which requires cross-origin isolation.
config.server.enhanceMiddleware = (middleware) => (req, res, next) => {
  res.setHeader('Cross-Origin-Embedder-Policy', 'credentialless');
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  middleware(req, res, next);
};

module.exports = config;
