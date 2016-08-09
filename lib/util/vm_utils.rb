#! /Users/whopper/.rbenv/shims/ruby

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
  end
end
