#
# Be sure to run `pod lib lint SwiftConcurrencySupport.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SwiftConcurrencySupport'
  s.version          = '0.1.0'
  s.summary          = 'A short description of SwiftConcurrencySupport.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/Klein/SwiftConcurrencySupport'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Klein' => 'mioke0428@gmail.com' }
  s.source           = { :git => 'https://github.com/mioke/swift-concurrency-support.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '13.0'
  s.swift_versions = '5'

  s.source_files = 'Sources/**/*'

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*'
    test_spec.dependency 'RxSwift', '~> 6.0'
    test_spec.dependency 'RxCocoa', '~> 6.0'
  end

  # s.resource_bundles = {
  #   'SwiftConcurrencySupport' => ['SwiftConcurrencySupport/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
