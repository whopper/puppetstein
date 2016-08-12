#! /Users/whopper/.rbenv/shims/ruby

require_relative 'platform_utils.rb'
require_relative 'git_utils.rb'
require_relative 'log_utils.rb'
require "net/http"

include Puppetstein::PlatformUtils
include Puppetstein::GitUtils
include Puppetstein::LogUtils

#! /usr/env/ruby
module Puppetstein
  module VMUtils

    def request_vm(platform)
      log_notice("Acquiring VM: #{platform.string}")
      output = `curl -d --url http://vmpooler.delivery.puppetlabs.net/vm/#{platform.string} ;`
      match = /\"hostname\": \"(.*)\"/.match(output)
      log_notice("Done! Hostname: #{match[1]}")
      match[1]
    end

    def copy_package_to_vm(platform, keyfile, package_path)
      # TODO: add cmd building method and IO.popen method
      cmd = "scp -o StrictHostKeyChecking=no "
      cmd = cmd + "-i #{keyfile} " if keyfile
      cmd = cmd + "#{package_path} root@#{platform.hostname}:/root"

      IO.popen(cmd) do |io|
        while (line= io.gets) do
          puts line
        end
      end
    end

    def patch_project_on_host(platform, keyfile, project, project_fork, project_version)
      log_notice("Patching #{project} on #{platform.hostname} with #{project_version}")
      pl_dir = '/opt/puppetlabs/puppet/lib/ruby/vendor_ruby/'
      clone_repo(project, project_fork, project_version)

      scp_cmd = "scp -r -o StrictHostKeyChecking=no "
      scp_cmd = scp_cmd + "-i #{keyfile} " if keyfile
      scp_cmd = scp_cmd + "/tmp/#{project}/lib root@#{platform.hostname}:/root"

      IO.popen(scp_cmd) do |io|
        # Do nothing...
      end

      install_cmd = "ssh -o StrictHostKeyChecking=no "
      install_cmd = install_cmd + "-i #{keyfile} " if keyfile
      install_cmd = install_cmd + "root@#{platform.hostname} '/bin/cp -rf /root/lib/* #{pl_dir}'"

      IO.popen(install_cmd)
    end

    def install_puppet_agent_on_vm(platform, keyfile)
      # TODO: don't just assume we're installing /root/pkg
      log_notice("Installing puppet-agent on #{platform.hostname}")

      cmd = "ssh -o StrictHostKeyChecking=no "
      cmd = cmd + "-i #{keyfile} " if keyfile
      cmd = cmd + "root@#{platform.hostname} '#{platform.package_command} /root/puppet-agent* " +
                  "&& ln -s /opt/puppetlabs/bin/* /usr/bin'"

      IO.popen(cmd) do |io|
        while (line = io.gets) do
          puts line
        end
      end
      log_notice("Done!")
    end

    def install_puppet_agent_from_url_on_vm(platform, keyfile, pa_version)
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

      cmd = "ssh -o StrictHostKeyChecking=no "
      cmd = cmd + "-i #{keyfile} " if keyfile
      cmd = cmd + "root@#{platform.hostname} 'wget -r -nH -nd -R \'*bundle*\' #{url} " +
                  "-P /root -A \'*#{package_regex}*\' -o /dev/null'"

      IO.popen(cmd) do |io|
        while (line = io.gets) do
          puts line
        end
      end

      install_puppet_agent_on_vm(platform, keyfile)
      0
    end
  end
end
