#! /Users/whopper/.rbenv/shims/ruby

require_relative 'git_utils.rb'
require_relative 'log_utils.rb'
require "net/http"

include Puppetstein::GitUtils
include Puppetstein::LogUtils

#! /usr/env/ruby
module Puppetstein
  module PlatformUtils
    def execute(command)
      IO.popen(command) do |io|
        while (line=io.gets) do
          puts line
        end
      end
    end

    def save_puppet_agent_artifact(host, tmp)
      desc = `git --git-dir=#{tmp}/puppet-agent/.git describe`
      case host.family
        when 'el'
        package = "puppet-agent-#{desc.gsub('-','.').chomp}-1.el#{host.version}.#{host.arch}.rpm"
        path = "#{tmp}/puppet-agent/output/el/#{host.version}/PC1/#{host.arch}/#{package}"
        when 'debian'
        package = "puppet-agent_#{desc.gsub('-''.').chomp}-1#{host.flavor}_#{host.vanagon_arch}.deb"
        path = "#{tmp}/puppet-agent/output/deb/#{host.flavor}/PC1/#{package}"
      end

      execute("mv #{path} #{tmp}")
      "#{tmp}/#{package}"
    end
  end
end
