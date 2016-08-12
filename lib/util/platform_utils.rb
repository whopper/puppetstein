#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

module Puppetstein
  module PlatformUtils
    def generate_host_config(platform, path='/tmp/hosts.yml')
      if platform.family == 'el'
        os = platform.flavor
      else
        os = platform.family
      end

      IO.popen("bundle exec beaker-hostgenerator #{os}#{platform.version}-64ma{hostname=#{platform.hostname}.delivery.puppetlabs.net} > #{path}")
    end

    def save_puppet_agent_artifact(platform)
      desc = `git --git-dir=/tmp/puppet-agent/.git describe`
      case platform.family
        when 'el'
        package = "puppet-agent-#{desc.gsub('-','.').chomp}-1.el#{platform.version}.#{platform.arch}.rpm"
        path = "/tmp/puppet-agent/output/el/#{platform.version}/PC1/#{platform.arch}/#{package}"
        when 'debian'
        package = "puppet-agent_#{desc.gsub('-''.').chomp}-1#{platform.flavor}_#{platform.vanagon_arch}.deb"
        path = "/tmp/puppet-agent/output/deb/#{platform.flavor}/PC1/#{package}"
      end

      IO.popen("mv #{path} /tmp") do |io|
        while (line = io.gets) do
          puts line
        end
      end
      "/tmp/#{package}"
    end
  end
end
