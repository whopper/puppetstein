#! /Users/whopper/.rbenv/shims/ruby

require_relative 'log_utils.rb'
require_relative 'platform_utils.rb'

include Puppetstein::LogUtils
include Puppetstein::PlatformUtils

#! /usr/env/ruby
module Puppetstein
  module VMUtils

    def request_vm(platform)
      log_notice("Acquiring VM: #{platform}")
      output = `curl -d --url http://vmpooler.delivery.puppetlabs.net/vm/#{platform} ;`
      match = /\"hostname\": \"(.*)\"/.match(output)
      log_notice("Done! Hostname: #{match[1]}")
      match[1]
    end

    def copy_package_to_vm(hostname, package)
      IO.popen("scp -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance #{package} root@#{hostname}:/root") do |io|
        while (line= io.gets) do
          puts line
        end
      end
    end

    def install_puppet_agent_on_vm(hostname, platform_family)
      log_notice("Installing puppet-agent <VERSION>on#{hostname}")
      pkg_cmd = get_package_command(platform_family)
      IO.popen("ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance root@#{hostname} '#{pkg_cmd} /root/puppet-agent* && ln -s /opt/puppetlabs/bin/* /usr/bin'") do |io|
        while (line = io.gets) do
          puts line
        end
      end
      log_notice("Done!")
    end

    def install_puppet_agent_from_url_on_vm(hostname, sha, platform_family, platform_flavor, platform_version, vanagon_arch)
      base_url = 'http://builds.puppetlabs.lan/puppet-agent'
      case platform_family
        when 'el'
          url = "#{base_url}/#{sha}/artifacts/el/#{platform_version}/PC1/#{vanagon_arch}"
          package_regex = "puppet-agent*el#{platform_version}\.#{vanagon_arch}*"
        when 'debian'
          url = "#{base_url}/#{sha}/artifacts/deb/#{platform_flavor}/PC1/"
          package_regex = "puppet-agent*#{platform_flavor}_#{vanagon_arch}*"
      end

      pkg_manager_cmd = get_package_manager_command(platform_family)
      IO.popen("ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance root@#{hostname} '#{pkg_manager_cmd} wget'") do |io|
        while (line = io.gets) do
          puts line
        end
      end

      IO.popen("ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa-acceptance root@#{hostname} 'wget -r -nH -nd -R \'*bundle*\' #{url} -P /root -A \'*#{package_regex}*\' -o /dev/null'") do |io|
        while (line = io.gets) do
          puts line
        end
      end

      install_puppet_agent_on_vm(hostname, platform_family)
    end
  end
end
