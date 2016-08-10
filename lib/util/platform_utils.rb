#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

module Puppetstein
  module PlatformUtils
    def get_puppet_agent_package_output_path(platform)
      desc = `git --git-dir=/tmp/puppet-agent/.git describe`
      case platform.family
        when 'el'
        "/tmp/puppet-agent/output/el/#{platform.version}/PC1/#{platform.arch}/puppet-agent-#{desc.gsub('-','.').chomp}-1.el#{platform.version}.#{platform.arch}.rpm"
        when 'debian'
        "/tmp/puppet-agent/output/deb/#{platform.flavor}/PC1/puppet-agent_#{desc.gsub('-','.').chomp}-1#{platform.flavor}_#{platform.vanagon_arch}.deb"
      end
    end
  end
end
