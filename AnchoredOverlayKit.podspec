Pod::Spec.new do |s|
  s.name = 'AnchoredOverlayKit'
  s.version = '0.1.0'
  s.summary = 'Anchored UIKit overlays that preserve editor focus.'
  s.homepage = 'https://github.com/rien7'
  s.authors = 'rien7'
  s.license = { type: 'AGPL-3.0-only', file: 'LICENSE' }
  s.source = { git: 'https://github.com/rien7/anchored-overlay-kit.git', tag: s.version.to_s }
  s.platform = :ios, '16.0'
  s.swift_version = '6.0'
  s.source_files = 'Sources/AnchoredOverlayKit/*.swift'
  s.frameworks = 'UIKit'
end
