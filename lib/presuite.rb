#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require_relative 'util/platform_utils.rb'
require_relative 'util/log_utils.rb'

include Puppetstein::PlatformUtils
include Puppetstein::LogUtils

module Puppetstein
  module Presuite
    def install_prerequisite_packages(platform)
      ['wget', 'git'].each do |pkg|
        install_package_on_host(platform, pkg)
      end
    end

    def install_package_on_host(platform, pkg_name)
      remote_command(platform, "#{platform.package_manager_command} #{pkg_name}")
    end
  end
end
