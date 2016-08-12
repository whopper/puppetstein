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

    def copy_package_to_vm(platform, package_path)
      IO.popen("scp -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance #{package_path} root@#{platform.hostname}:/root") do |io|
        while (line= io.gets) do
          puts line
        end
      end
    end

    def patch_project_on_host(platform, project, project_fork, project_version)

      # TODO: make helper for installing package
      IO.popen("ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance root@#{platform.hostname} '#{platform.package_manager_command} git'") do |io|
        while (line = io.gets) do
          puts line
        end
      end

      log_notice("Patching #{project} on #{platform.hostname} with #{project_version}")

      pl_dir = '/opt/puppetlabs/puppet/lib/ruby/vendor_ruby/'
      clone_repo(project, project_fork, project_version)
      IO.popen("scp -r -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance /tmp/#{project}/lib root@#{platform.hostname}:/root") do |io|
        # Do nothing...
      end

      IO.popen("ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance root@#{platform.hostname} '/bin/cp -rf /root/lib/* #{pl_dir}'")
    end

    def install_puppet_agent_on_vm(platform)
      log_notice("Installing puppet-agent <VERSION>on#{platform.hostname}")
      IO.popen("ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance root@#{platform.hostname} '#{platform.package_command} /root/puppet-agent* && ln -s /opt/puppetlabs/bin/* /usr/bin'") do |io|
        while (line = io.gets) do
          puts line
        end
      end
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

      # TODO: make helper for installing package
      IO.popen("ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance root@#{platform.hostname} '#{platform.package_manager_command} wget'") do |io|
        while (line = io.gets) do
          puts line
        end
      end

      IO.popen("ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance root@#{platform.hostname} 'wget -r -nH -nd -R \'*bundle*\' #{url} -P /root -A \'*#{package_regex}*\' -o /dev/null'") do |io|
        while (line = io.gets) do
          puts line
        end
      end

      install_puppet_agent_on_vm(platform)
      0
    end
  end
end
