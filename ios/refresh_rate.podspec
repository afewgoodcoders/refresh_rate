Pod::Spec.new do |s|
  s.name             = 'refresh_rate'
  s.version          = '2.0.0-dev.1'
  s.summary          = 'Control display refresh rates in Flutter.'
  s.description      = <<-DESC
Cross-platform Flutter plugin to query and control display refresh rates.
Reports source-qualified display capabilities and Flutter frame timings.
System scheduling remains in control when engine control is unsupported.
                       DESC
  s.homepage         = 'https://qoder.in'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Qoder' => 'dev@qoder.in' }
  s.source           = { :path => '.' }
  s.source_files     = [
    'refresh_rate/Sources/refresh_rate/**/*.swift',
    'refresh_rate/Sources/refresh_rate_objc/**/*.{h,m}'
  ]
  s.public_header_files = 'refresh_rate/Sources/refresh_rate_objc/include/**/*.h'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
end
