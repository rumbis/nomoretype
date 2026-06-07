// Build configuration for electron-builder
module.exports = {
  appId: 'com.influro.nomoretype',
  productName: 'NoMoreType',
  directories: {
    output: 'dist',
    buildResources: 'build',
  },
  files: [
    'main.js',
    'preload.js',
    'package.json',
  ],
  extraResources: [
    {
      from: '../web-app',
      to: 'web-app',
      filter: ['**/*'],
    },
    {
      from: 'hotkey-helper/hotkey-helper',
      to: 'hotkey-helper',
    },
  ],
  mac: {
    category: 'public.app-category.productivity',
    target: [
      { target: 'dmg', arch: ['x64', 'arm64'] },
      { target: 'zip', arch: ['x64', 'arm64'] },
    ],
    icon: 'build/icon.png',
    entitlements: 'build/entitlements.mac.plist',
    hardenedRuntime: true,
    gatekeeperAssess: false,
  },
  win: {
    target: [
      { target: 'nsis', arch: ['x64'] },
      { target: 'portable', arch: ['x64'] },
    ],
    icon: '../web-app/icons/icon.svg',
  },
  linux: {
    target: [
      { target: 'AppImage', arch: ['x64'] },
      { target: 'deb', arch: ['x64'] },
    ],
    category: 'Office',
    icon: '../web-app/icons/icon.svg',
  },
  nsis: {
    oneClick: false,
    allowToChangeInstallationDirectory: true,
  },
};
