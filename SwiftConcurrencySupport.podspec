#
# Be sure to run `pod lib lint SwiftConcurrencySupport.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name = "SwiftConcurrencySupport"
  s.version = "0.1.0"
  s.summary = "Additional functionalities for Swift concurrency."

  s.description = <<~DESC
    Additional functionalities for Swift concurrency.
  DESC

  s.homepage = "https://github.com/Klein/SwiftConcurrencySupport"
  s.license = {type: "MIT", file: "LICENSE"}
  s.author = {"Klein" => "mioke0428@gmail.com"}
  s.source = {git: "https://github.com/mioke/swift-concurrency-support.git", tag: s.version.to_s}

  s.ios.deployment_target = "13.0"
  s.swift_versions = "5"

  s.source_files = "Sources/**/*"

  s.test_spec "Tests" do |test_spec|
    test_spec.source_files = "Tests/**/*"
    test_spec.dependency "RxSwift", "~> 6.0"
    test_spec.dependency "RxCocoa", "~> 6.0"
  end
end
