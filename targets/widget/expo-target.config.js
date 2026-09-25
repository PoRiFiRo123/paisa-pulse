/** iOS widget extension: Home Screen + Lock Screen widgets and a Control Center control. */
/** @type {import('@bacons/apple-targets/app.plugin').ConfigFunction} */
module.exports = (config) => ({
  type: 'widget',
  name: 'PaisaPulseWidgets',
  icon: '../../assets/icon.png',
  deploymentTarget: '17.0',
  colors: {
    $widgetBackground: { light: '#FFFFFF', dark: '#1C1C1E' },
    $accent: { light: '#5E5CE6', dark: '#7D7AFF' },
    Accent: { light: '#5E5CE6', dark: '#7D7AFF' },
    Expense: { light: '#FF3B30', dark: '#FF453A' },
    Secondary: { light: '#8A8A8E', dark: '#8E8E93' },
  },
  entitlements: {
    'com.apple.security.application-groups': config.ios.entitlements['com.apple.security.application-groups'],
  },
});
