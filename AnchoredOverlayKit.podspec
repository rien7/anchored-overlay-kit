require 'json'
metadata = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'AnchoredOverlayKit'
  s.version = metadata.fetch('version')
  s.summary = 'Anchored UIKit overlays that preserve editor focus.'
  s.homepage = metadata.fetch('homepage')
  s.authors = 'rien7'
  s.license = { type: metadata.fetch('license'), file: 'LICENSE' }
  s.source = { git: 'https://github.com/rien7/anchored-overlay-kit.git', tag: s.version.to_s }
  s.platform = :ios, '16.0'
  s.swift_version = '6.0'
  s.source_files = 'Sources/AnchoredOverlayKit/*.swift'
  s.frameworks = 'UIKit'
end
