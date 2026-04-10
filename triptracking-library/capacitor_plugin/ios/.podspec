Pod::Spec.new do |s|
  s.name             = ''
  s.version          = '1.0.0'
  s.summary          = 'Capacitor plugin for triptracking'
  s.homepage         = 'https://github.com/hieunguyentt/triptracking-library'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Your Name' => 'you@email.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Plugin/**/*.{swift,h,m}'
  s.dependency 'Capacitor'
  s.dependency 'triptracking', '1.0.0'
  s.swift_version             = '5.0'
  s.ios.deployment_target     = '13.0'
end
