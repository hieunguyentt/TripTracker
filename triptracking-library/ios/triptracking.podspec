Pod::Spec.new do |s|
  s.name             = 'triptracking'
  s.version          = '1.0.0'
  s.summary          = 'triptracking cross-platform native library'
  s.description      = <<-DESC
    Native iOS library that can be consumed by iOS native, Flutter, and Ionic apps.
  DESC
  s.homepage         = 'https://github.com/hieunguyentt/triptracking-library'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Your Name' => 'you@email.com' }
  s.source           = {
    :git => 'https://github.com/hieunguyentt/triptracking-library.git',
    :tag => s.version.to_s
  }
  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.0'
  s.source_files          = 'ios/Sources/triptracking/**/*.{swift,h,m}'
  s.public_header_files   = 'ios/Sources/triptracking/*.h'
  # s.dependency 'Alamofire', '~> 5.0'   ← add your iOS dependencies here
end
