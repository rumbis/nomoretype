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
    '../web-app/**/*',
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
    icon: 'build/icon.png',
  },
  linux: {
    target: [
      { target: 'AppImage', arch: ['x64'] },
      { target: 'deb', arch: ['x64'] },
    ],
    category: 'Office',
    icon: 'build/icon.png',
  },
  nsis: {
    oneClick: false,
    allowToChangeInstallationDirectory: true,
  },
};
