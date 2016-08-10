#! /Users/whopper/.rbenv/shims/ruby

require_relative 'log_utils.rb'
require_relative 'platform_utils.rb'

include Puppetstein::LogUtils
include Puppetstein::PlatformUtils

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
    end
  end
end
