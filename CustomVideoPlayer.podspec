Pod::Spec.new do |s|
  s.name             = 'CustomVideoPlayer'
  s.version          = '2.0.0'
  s.summary          = 'A video player with custom playback controls, subtitle and video quality selection, live streaming, and error handling.'

  s.description      = <<-DESC
                       A video player with custom playback controls, the ability to select
                       subtitles and video quality, stream live content, as well as handle
                       errors.

                       This is a maintained fork of ajkmr7/Custom-Video-Player, originally
                       created by Ajay Kumar and released under the MIT license. The fork
                       adds an A-B repeat loop feature, crash and correctness fixes, and a
                       test suite. As of 2.0.0 the minimum deployment target is iOS 18.0
                       (upstream 1.1.0 supported iOS 11.0).
                       DESC

  s.homepage         = 'https://github.com/ethanbissbort/Custom-Video-Player'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Ajay Kumar' => 'ajayyasodha@gmail.com', 'Ethan Bissbort' => 'legal@fluxology.ca' }
  s.source           = { :git => 'https://github.com/ethanbissbort/Custom-Video-Player.git', :tag => s.version.to_s }

  s.ios.deployment_target = '18.0'
  s.swift_version    = '5.0'

  s.source_files = 'Custom-Video-Player/Classes/**/*'
  s.dependency 'SnapKit'
  
   s.resource_bundles = {
    'ResourcesBundle' => ['Custom-Video-Player/Assets/**']
  }
end
