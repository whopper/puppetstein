require 'open-uri'
require 'open3'
require 'uri'
require_relative 'platform_utils.rb'
require_relative 'log_utils.rb'
require_relative 'common_utils.rb'

include Puppetstein::LogUtils

module Puppetstein
  module InstallUtils
    PLATFORM_PATTERNS = {
      :redhat        => /fedora|el-|centos/,
      :debian        => /debian|ubuntu|cumulus/,
      :debian_ruby18 => /debian|ubuntu-lucid|ubuntu-precise/,
      :solaris_10    => /solaris-10/,
      :solaris_11    => /solaris-11/,
      :windows       => /windows/,
      :eos           => /^eos-/,
    }.freeze

    # Installs packages on the hosts.
    #
    # @param hosts [Array<Host>] Array of hosts to install packages to.
    # @param package_hash [Hash{Symbol=>Array<String,Array<String,String>>}]
    #   Keys should be a symbol for a platform in PLATFORM_PATTERNS.  Values
    #   should be an array of package names to install, or of two element
    #   arrays where a[0] is the command we expect to find on the platform
    #   and a[1] is the package name (when they are different).
    # @param options [Hash{Symbol=>Boolean}]
    # @option options [Boolean] :check_if_exists First check to see if
    #   command is present before installing package.  (Default false)
    # @return true
    def install_packages_on(hosts, package_hash, options = {})
      check_if_exists = options[:check_if_exists]
      hosts = [hosts] unless hosts.kind_of?(Array)
      hosts.each do |host|
        package_hash.each do |platform_key,package_list|
          if pattern = PLATFORM_PATTERNS[platform_key]
            if pattern.match(host.family_string)
              package_list.each do |cmd_pkg|
                if cmd_pkg.kind_of?(Array)
                  command, package = cmd_pkg
                else
                  command = package = cmd_pkg
                end
                if !check_if_exists || !host.check_for_package(command)
                  log_notice("Installing #{package}")
                  #additional_switches = '--allow-unauthenticated' if platform_key == :debian
                  install_package_on_host(host, package)
                  #host.install_package(package, additional_switches)
                end
              end
            end
          else
            raise("Unknown platform '#{platform_key}' in package_hash")
          end
        end
      end
      return true
    end

   def install_repos_on(host, project, sha, repo_configs_dir)
      platform = host.family_string
      platform_configs_dir = File.join(repo_configs_dir,platform)
      tld     = sha == 'nightly' ? 'nightlies.puppetlabs.com' : 'builds.puppetlabs.lan'
      project = sha == 'nightly' ? project + '-latest'        :  project
      sha     = sha == 'nightly' ? nil                        :  sha

      puts platform
      case platform
      when /^(fedora|el|centos)-(\d+)-(.+)$/
        variant = (($1 == 'centos') ? 'el' : $1)
        fedora_prefix = ((variant == 'fedora') ? 'f' : '')
        version = $2
        arch = $3

        repo_filename = "pl-%s%s-%s-%s%s-%s.repo" % [
          project,
          sha ? '-' + sha : '',
          variant,
          fedora_prefix,
          version,
          arch
        ]
        repo_url = "http://%s/%s/%s/repo_configs/rpm/%s" % [tld, project, sha, repo_filename]

        remote_command(host, "curl -o /etc/yum.repos.d/#{repo_filename} #{repo_url}")
        #on host, "curl -o /etc/yum.repos.d/#{repo_filename} #{repo_url}"
      when /^(debian|ubuntu|cumulus)-([^-]+)-(.+)$/
        variant = $1
        version = $2
        arch = $3

        if variant =~ /cumulus/ then
          version = variant
        end

        list_filename = "pl-%s%s-%s.list" % [
          project,
          sha ? '-' + sha : '',
          version
        ]
        list_url = "http://%s/%s/%s/repo_configs/deb/%s" % [tld, project, sha, list_filename]

        remote_command(host, "curl -o /etc/apt/sources.list.d/#{list_filename} #{list_url}")
        remote_command(host, "apt-get update")
        #on host, "curl -o /etc/apt/sources.list.d/#{list_filename} #{list_url}"
        #on host, "apt-get update"
      else
        if project == 'puppet-agent'
          opts = {
            :puppet_collection => 'PC1',
            :puppet_agent_sha => ENV['SHA'],
            :puppet_agent_version => ENV['SUITE_VERSION'] || ENV['SHA']
          }
          # this installs puppet-agent on windows (msi), osx (dmg) and eos (swix)
          install_puppet_agent_dev_repo_on(agent, opts)
        else
          fail_test("No repository installation step for #{platform} yet...")
        end
      end
    end
  end
end
