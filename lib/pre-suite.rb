#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require_relative 'util/platform_utils.rb'
require_relative 'util/install_utils.rb'
require_relative 'util/log_utils.rb'

include Puppetstein::PlatformUtils
include Puppetstein::InstallUtils
include Puppetstein::LogUtils

module Puppetstein
  module Presuite
    def install_prerequisite_packages(host)
      ['wget', 'git'].each do |pkg|
        install_package_on_host(host, pkg)
      end
    end

    def install_package_on_host(host, pkg_name)
      remote_command(host, "#{host.package_manager_command} #{pkg_name}")
    end

    def setup_puppetserver_on_host(master, pa_version)
      master_packages = {
        :redhat => [
          'puppetserver',
        ],
        :debian => [
          'puppetserver',
        ],
      }

      repo_configs_dir = 'repo-configs'
      install_repos_on(master, 'puppetserver', 'nightly', repo_configs_dir)
      install_repos_on(master, 'puppet-agent', pa_version, repo_configs_dir)
      install_packages_on(master, master_packages)
      remote_command(master, 'service puppetserver start')
    end

    def sign_agent_cert_on_master(agent, master)
      remote_command(agent, "puppet config set server #{master.hostname}.delivery.puppetlabs.net")
      remote_command(agent, "puppet agent -t")
      remote_command(master, "puppet cert sign --all")
    end
  end
end
