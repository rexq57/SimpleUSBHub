Pod::Spec.new do |s|
  s.name             = 'SimpleUSBHub'
  s.version          = '0.1.0'
  s.summary          = '基于peertalk的简单USB连接通信装置'

  s.description      = '基于peertalk的简单USB连接通信装置'

  s.homepage         = 'https://github.com/rexq57/SimpleUSBHub'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'rexq57' => 'rexq57c@gmail.com' }
  s.source           = { :git => 'git@github.com:rexq57/SimpleUSBHub.git', :tag => s.version.to_s }

  s.ios.deployment_target = '7.0'
  s.osx.deployment_target = '10.6'

  s.header_mappings_dir = 'src/*'
  s.header_dir = 'SimpleUSBHub/'
  s.source_files = 'src/**/*{h,hpp,c,cpp,mm,m}'

end
