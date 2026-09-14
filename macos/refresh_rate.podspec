Pod::Spec.new do |s|
  s.name             = 'refresh_rate'
  s.version          = '2.0.1'
  s.summary          = 'Control display refresh rates in Flutter.'
  s.description      = <<-DESC
Cross-platform Flutter plugin to query and control display refresh rates.
                       DESC
  s.homepage         = 'https://afewgoodcoders.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'A Few Good Coders'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.14'
  s.swift_version    = '5.0'
end
