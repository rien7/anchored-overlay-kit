#!/usr/bin/env python3
"""Verify the actual npm artifact through CocoaPods and SPM without publishing."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.artifacts/distribution'
HOST = OUT / 'host'


def run(args, cwd=ROOT, log=None):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    if log:
        (OUT / log).write_text(result.stdout)
        if result.stderr:
            (OUT / (log + ".stderr")).write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}):\n{result.stdout[-6000:]}\n{result.stderr[-2000:]}')
    return result.stdout


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    HOST.mkdir(exist_ok=True)
    packed = json.loads(run(['npm', 'pack', '--json', '--pack-destination', str(OUT)], log='pack.json'))[0]
    allowed = {'package.json', 'Package.swift', 'AnchoredOverlayKit.podspec',
               'README.md', 'README.zh-CN.md', 'docs/API.md', 'docs/API.zh-CN.md',
               'INTEGRATION.md', 'PUBLISHING.md', 'LICENSE'}
    paths = {entry['path'] for entry in packed['files']}
    unexpected = {p for p in paths if p not in allowed and not
                  (p.startswith('Sources/AnchoredOverlayKit/') and p.endswith('.swift'))}
    assert not unexpected, f'Unexpected published files: {unexpected}'
    assert allowed <= paths, f'Missing package files: {allowed - paths}'
    sources = {str(p.relative_to(ROOT)) for p in (ROOT / 'Sources').rglob('*.swift')}
    assert sources <= paths, f'Missing source files: {sources - paths}'
    (HOST / 'package.json').write_text('{"name":"overlay-distribution-host","private":true}')
    run(['npm', 'install', '--ignore-scripts', '--no-audit', '--no-fund',
         str(OUT / packed['filename'])], cwd=HOST, log='install.log')
    manifest = Path(run(['node', '-p',
        'require.resolve("@rien7/anchored-overlay-kit/package.json")'], cwd=HOST).strip())
    package = manifest.parent
    for path in paths:
        assert (package / path).read_bytes() == (ROOT / path).read_bytes(), f'Artifact drift: {path}'
    spec = json.loads(run(['pod', 'ipc', 'spec', str(package / 'AnchoredOverlayKit.podspec')], log='podspec.json'))
    assert spec['version'] == json.loads(manifest.read_text())['version']
    assert spec['source']['tag'] == spec['version']
    (HOST / 'App.swift').write_text('''import UIKit
import AnchoredOverlayKit
@main final class App: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let overlay = AnchoredOverlayController()
    func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        overlay.anchorTransition = .fade
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .systemBackground
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
''')
    (HOST / 'generate.rb').write_text('''require 'xcodeproj'
project = Xcodeproj::Project.new('Distribution.xcodeproj')
source = project.main_group.new_file('App.swift')
%w[PodHost SwiftHost].each do |name|
  target = project.new_target(:application, name, :ios, '16.0')
  target.source_build_phase.add_file_reference(source)
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => "dev.rien7.overlay-distribution.#{name}",
      'SWIFT_VERSION' => '6.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'CODE_SIGN_STYLE' => 'Automatic', 'IPHONEOS_DEPLOYMENT_TARGET' => '16.0'
    })
  end
  if name == 'SwiftHost'
    package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    package.relative_path = 'node_modules/@rien7/anchored-overlay-kit'
    project.root_object.package_references << package
    product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    product.package = package
    product.product_name = 'AnchoredOverlayKit'
    target.package_product_dependencies << product
    file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    file.product_ref = product
    target.frameworks_build_phase.files << file
  end
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.set_launch_target(target)
  scheme.save_as(project.path, name, true)
end
project.save
''')
    run(['ruby', 'generate.rb'], cwd=HOST, log='generate.log')
    (HOST / 'Podfile').write_text('''platform :ios, '16.0'
install! 'cocoapods', :deterministic_uuids => true
project 'Distribution.xcodeproj'
target 'PodHost' do
  package_json = Pod::Executable.execute_command('node', [
    '-p', 'require.resolve("@rien7/anchored-overlay-kit/package.json", { paths: [process.argv[1]] })', __dir__
  ]).strip
  pod 'AnchoredOverlayKit', :path => File.dirname(package_json)
end
''')
    run(['pod', 'install'], cwd=HOST, log='pod-install.log')
    for scheme in ('PodHost', 'SwiftHost'):
        print(f'Building {scheme} from installed npm artifact...', flush=True)
        run(['xcodebuild', '-workspace', 'Distribution.xcworkspace', '-scheme', scheme,
             '-configuration', 'Debug', '-destination', 'generic/platform=iOS Simulator',
             'build'], cwd=HOST, log=f'{scheme}-build.log')
    (OUT / 'result.json').write_text(json.dumps({
        'status': 'passed', 'version': spec['version'], 'tarball': packed['filename'],
        'integrity': packed['integrity'], 'files': sorted(paths),
        'checks': ['file allowlist and source completeness', 'installed artifact byte equality',
                   'podspec version and tag', 'CocoaPods simulator build', 'SPM simulator build']
    }, indent=2) + '\n')
    print(f'Distribution verification passed: {OUT}')


if __name__ == '__main__':
    # Never leave a previous success as the result of an interrupted/failed run.
    (OUT / 'result.json').unlink(missing_ok=True)
    main()
