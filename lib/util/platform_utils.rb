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

    def remote_command(platform, command)
      cmd = "ssh -o StrictHostKeyChecking=no "
      cmd = cmd + "-i #{platform.keyfile} " if platform.keyfile
      cmd = cmd + "root@#{platform.hostname} '#{command}'"
      execute(cmd)
    end

    def remote_copy(platform, local_file, remote_path)
      cmd = "scp -o StrictHostKeyChecking=no "
      cmd = cmd + "-i #{platform.keyfile} " if platform.keyfile
      cmd = cmd + "#{local_file} root@#{platform.hostname}:#{remote_path}"
      execute(cmd)
    end

    def request_vm(platform)
      log_notice("Acquiring VM: #{platform.string}")
      output = `curl -d --url http://vmpooler.delivery.puppetlabs.net/vm/#{platform.string} ;`
      match = /\"hostname\": \"(.*)\"/.match(output)
      log_notice("Done! Hostname: #{match[1]}")
      match[1]
    end

    def patch_project_on_host(platform, project, project_fork, project_version)
      log_notice("Patching #{project} on #{platform.hostname} with #{project_version}")
      clone_repo(project, project_fork, project_version)

      remote_copy(platform, "/tmp/#{project}/lib", '/root')
      pl_dir = '/opt/puppetlabs/puppet/lib/ruby/vendor_ruby/'
      remote_command(platform, "/bin/cp -rf /root/lib/* #{pl_dir}")
    end

    def install_puppet_agent_on_vm(platform)
      # TODO: don't just assume we're installing /root/pkg
      log_notice("Installing puppet-agent on #{platform.hostname}")
      remote_command(platform, "#{platform.package_command} /root/puppet-agent* && ln -s /opt/puppetlabs/bin/* /usr/bin")
      log_notice("Done!")
    end

    def install_puppet_agent_from_url_on_vm(platform, pa_version)
      base_url = 'http://builds.puppetlabs.lan/puppet-agent'
      case platform.family
        when 'el'
          url = "#{base_url}/#{pa_version}/artifacts/el/#{platform.version}/PC1/#{platform.vanagon_arch}"
          package_regex = "puppet-agent*el#{platform.version}\.#{platform.vanagon_arch}*"
        when 'debian'
          url = "#{base_url}/#{pa_version}/artifacts/deb/#{platform.flavor}/PC1/"
          package_regex = "puppet-agent*#{platform.flavor}_#{platform.vanagon_arch}*"
      end

      url = URI.parse(url)
      req = Net::HTTP.new(url.host, url.port)
      res = req.request_head(url.path)

      if res.code != "200"
        puts "Failed to download puppet-agent from builds.puppetlabs.lan"
        1
      end

      remote_command(platform, "wget -r -nH -nd -R \'*bundle*\' #{url} -P /root -A \'*#{package_regex}*\' -o /dev/null")
      install_puppet_agent_on_vm(platform)
      0
    end

    def generate_host_config(platform, path='/tmp/hosts.yml')
      if platform.family == 'el'
        os = platform.flavor
      else
        os = platform.family
      end

      execute("bundle exec beaker-hostgenerator #{os}#{platform.version}-64ma{hostname=#{platform.hostname}.delivery.puppetlabs.net} > #{path}")
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

      execute("mv #{path} /tmp")
      "/tmp/#{package}"
    end
  end
end
