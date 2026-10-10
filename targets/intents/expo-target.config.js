/** App Intents extension: Siri phrases, Shortcuts actions and Wallet (Apple Pay) automations. */
/** @type {import('@bacons/apple-targets/app.plugin').ConfigFunction} */
module.exports = (config) => ({
  type: 'app-intent',
  name: 'PaisaPulseIntents',
  bundleIdentifier: '.intents',
  deploymentTarget: '17.0',
  entitlements: {
    'com.apple.security.application-groups': config.ios.entitlements['com.apple.security.application-groups'],
  },
});
