Pod::Spec.new do |s|
  s.name           = 'AppGroup'
  s.version        = '1.0.0'
  s.summary        = 'Resolves the App Group ID after free-account re-signing (SideStore/AltStore).'
  s.author         = 'Paisa Pulse'
  s.homepage       = 'https://github.com/PoRiFiRo123/paisa-pulse'
  s.platforms      = { :ios => '15.1' }
  s.source         = { git: '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.source_files = '**/*.{h,m,swift}'
end
