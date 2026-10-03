require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'Examples/OverlayDemo.xcodeproj'))
target = project.new_target(:application, 'OverlayDemo', :ios, '16.0')
group = project.main_group.new_group('OverlayDemo', 'OverlayDemo')
Dir.glob(File.join(root, 'Examples/OverlayDemo/*.swift')).sort.each do |path|
  target.source_build_phase.add_file_reference(group.new_file(File.basename(path)))
end
photos = group.new_file('Photos')
photos.last_known_file_type = 'folder'
target.resources_build_phase.add_file_reference(photos)
package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = '..'
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package = package
product.product_name = 'AnchoredOverlayKit'
target.package_product_dependencies << product
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product
target.frameworks_build_phase.files << build_file
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'dev.rien7.AnchoredOverlayDemo',
    'SWIFT_VERSION' => '6.0',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'CODE_SIGN_STYLE' => 'Automatic',
  })
end
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project.path, 'OverlayDemo', true)
project.save
