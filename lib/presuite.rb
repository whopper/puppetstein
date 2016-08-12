#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require_relative 'util/log_utils.rb'

include Puppetstein::LogUtils

module Puppetstein
  module Presuite
    def install_prerequisite_packages(platform)
      ['wget', 'git'].each do |pkg|
        install_package_on_host(platform, pkg)
      end
    end

    def install_package_on_host(platform, pkg_name)
      IO.popen("ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance root@#{platform.hostname} '#{platform.package_manager_command} #{pkg_name}'") do |io|
        while (line = io.gets) do
          puts line
        end
      end
    end
  end
end
