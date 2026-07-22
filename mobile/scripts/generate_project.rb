#!/usr/bin/env ruby

require "fileutils"
require "pathname"
require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "Recourse.xcodeproj")
package_resolved_path = File.join(
  project_path,
  "project.xcworkspace",
  "xcshareddata",
  "swiftpm",
  "Package.resolved"
)
package_resolved = File.exist?(package_resolved_path) ? File.read(package_resolved_path) : nil
FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2640"
project.root_object.attributes["LastUpgradeCheck"] = "2640"

app_target = project.new_target(:application, "Recourse", :ios, "17.0")
test_target = project.new_target(:unit_test_bundle, "RecourseTests", :ios, "17.0")
test_target.add_dependency(app_target)

def nested_group(root_group, relative_directory)
  return root_group if relative_directory == "."

  relative_directory.split(File::SEPARATOR).inject(root_group) do |parent, component|
    parent.groups.find { |group| group.display_name == component } || parent.new_group(component, component)
  end
end

def add_sources(target, root_group, directory)
  Dir.glob(File.join(directory, "**", "*.swift")).sort.each do |path|
    relative_path = Pathname.new(path).relative_path_from(Pathname.new(directory)).to_s
    parent = nested_group(root_group, File.dirname(relative_path))
    reference = parent.new_file(File.basename(relative_path))
    target.source_build_phase.add_file_reference(reference)
  end
end

def add_resources(target, root_group, directory)
  Dir.glob(File.join(directory, "**", "*.json")).sort.each do |path|
    relative_path = Pathname.new(path).relative_path_from(Pathname.new(directory)).to_s
    parent = nested_group(root_group, File.dirname(relative_path))
    reference = parent.new_file(File.basename(relative_path))
    target.resources_build_phase.add_file_reference(reference)
  end
end

app_group = project.main_group.new_group("Recourse", "Recourse")
test_group = project.main_group.new_group("RecourseTests", "RecourseTests")
add_sources(app_target, app_group, File.join(root, "Recourse"))
add_sources(test_target, test_group, File.join(root, "RecourseTests"))
app_group.new_file("Recourse.entitlements")

resources_group = nested_group(app_group, "Resources")
abi_group = nested_group(resources_group, "ABI")
add_resources(app_target, abi_group, File.join(root, "Recourse", "Resources", "ABI"))
assets_path = File.join(root, "Recourse", "Resources", "Images.xcassets")
assets_reference = resources_group.new_file("Images.xcassets")
app_target.resources_build_phase.add_file_reference(assets_reference)

web3swift_package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
web3swift_package.repositoryURL = "https://github.com/web3swift-team/web3swift.git"
web3swift_package.requirement = {
  "kind" => "exactVersion",
  "version" => "3.3.2"
}
project.root_object.package_references << web3swift_package

web3swift_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
web3swift_product.package = web3swift_package
web3swift_product.product_name = "web3swift"
app_target.package_product_dependencies << web3swift_product

web3swift_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
web3swift_build_file.product_ref = web3swift_product
app_target.frameworks_build_phase.files << web3swift_build_file

project.build_configurations.each do |configuration|
  configuration.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
  configuration.build_settings["SWIFT_VERSION"] = "6.0"
end

app_target.build_configurations.each do |configuration|
  configuration.build_settings.merge!(
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS" => "YES",
    "CODE_SIGN_STYLE" => "Automatic",
    "CODE_SIGN_ENTITLEMENTS" => "Recourse/Recourse.entitlements",
    "CURRENT_PROJECT_VERSION" => "1",
    "DEVELOPMENT_TEAM" => "",
    "ENABLE_PREVIEWS" => "YES",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "INFOPLIST_KEY_CFBundleDisplayName" => "Recourse",
    "INFOPLIST_KEY_LSApplicationCategoryType" => "public.app-category.finance",
    "INFOPLIST_KEY_NSCameraUsageDescription" => "Scan protected payment requests and capture dispute evidence.",
    "INFOPLIST_KEY_NSFaceIDUsageDescription" => "Confirm protected payment transactions.",
    "INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsLocalNetworking" => "YES",
    "INFOPLIST_KEY_NSLocalNetworkUsageDescription" => "Connect to the Recourse development backend on your local network.",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation" => "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation" => "YES",
    "MARKETING_VERSION" => "0.1.0",
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.recourse.buyer",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "SUPPORTED_PLATFORMS" => "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST" => "NO",
    "SWIFT_EMIT_LOC_STRINGS" => "YES",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "TARGETED_DEVICE_FAMILY" => "1"
  )
end

project.root_object.attributes["TargetAttributes"] ||= {}
project.root_object.attributes["TargetAttributes"][app_target.uuid] ||= {}
project.root_object.attributes["TargetAttributes"][app_target.uuid]["SystemCapabilities"] = {
  "com.apple.SignInWithApple" => { "enabled" => 1 }
}

test_target.build_configurations.each do |configuration|
  configuration.build_settings.merge!(
    "BUNDLE_LOADER" => "$(TEST_HOST)",
    "CODE_SIGN_STYLE" => "Automatic",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.recourse.buyer.tests",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "TARGETED_DEVICE_FAMILY" => "1",
    "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/Recourse.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Recourse"
  )
end

script_phase = app_target.new_shell_script_build_phase("Generate deployment configuration")
script_phase.shell_script = <<~SCRIPT
  set -euo pipefail
  cd "${SRCROOT}/.."
  node ops/codegen.mjs
SCRIPT
script_phase.input_paths = [
  "$(SRCROOT)/../deployments/arc-testnet.json",
  "$(SRCROOT)/../deployments/arc-config.json",
  "$(SRCROOT)/../ops/codegen.mjs"
]
script_phase.output_paths = ["$(SRCROOT)/Recourse/Generated/Deployment.swift"]
app_target.build_phases.delete(script_phase)
app_target.build_phases.unshift(script_phase)

project.predictabilize_uuids
test_dependency = test_target.dependencies.last
test_dependency.instance_variable_set(:@uuid, "D1D1D1D1D1D1D1D1D1D1D1D1")
test_dependency.target_proxy.instance_variable_set(:@uuid, "C1C1C1C1C1C1C1C1C1C1C1C1")
project.save

if package_resolved
  FileUtils.mkdir_p(File.dirname(package_resolved_path))
  File.write(package_resolved_path, package_resolved)
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(test_target)
scheme.set_launch_target(app_target)
if ENV["MOBILE_LOCAL_WRITE_TESTS"] == "1"
  variables = %w[
    MOBILE_LOCAL_WRITE_TESTS
    MOBILE_LOCAL_RPC_URL
    MOBILE_LOCAL_DEPLOYMENT
    MOBILE_LOCAL_SEED
    MOBILE_LOCAL_BUYER_PK
  ].map do |key|
    { :key => key, :value => ENV.fetch(key), :enabled => true }
  end
  scheme.test_action.should_use_launch_scheme_args_env = false
  scheme.test_action.environment_variables = Xcodeproj::XCScheme::EnvironmentVariables.new(variables)
end
scheme.save_as(project_path, "Recourse", true)

puts "generated #{project_path}"
