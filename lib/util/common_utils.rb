require_relative 'log_utils.rb'
require_relative 'platform_utils.rb'
require 'beaker-hostgenerator'
require 'beaker/platform'
require 'beaker/logger'
require 'beaker/result'
require 'beaker/dsl/install_utils'
require 'beaker/dsl/install_utils/foss_utils'
require 'beaker/options/options_hash.rb'

module Puppetstein
  module BeakerUtils
    def run_beaker(args = {})
      options = ''
      args.each do |k,v|
        if k == 'flag'
          options = options + "--#{v} "
        else
          options = options + "--#{k}=#{v} " unless k == 'noop'
        end
      end

      cmd = "bundle exec beaker --options-file=options.rb #{options} --debug"

      if args['noop']
        Puppetstein::LogUtils.log_notice("Running beaker with the following command:\n\n")
        Puppetstein::LogUtils.log_notice(cmd)
        Puppetstein::LogUtils.log_notice('Finished noop mode')
      else
        Puppetstein::LogUtils.log_notice(cmd)
        Puppetstein::PlatformUtils.execute(cmd)
      end
    end

    def create_host_config(hosts, config)
      if hosts[0].hostname && hosts[1].hostname
        targets = "#{hosts[0].beaker_flavor}#{hosts[0].version}-64a{hostname=#{hosts[0].hostname}}-#{hosts[1].beaker_flavor}#{hosts[1].version}-64m{hostname=#{hosts[1].hostname}\,use-service=true}"
      else
        targets = "#{hosts[0].beaker_flavor}#{hosts[0].version}-64a-#{hosts[1].beaker_flavor}#{hosts[1].version}-64m{use-service=true}"
      end

      Puppetstein::LogUtils.log_notice("Creating host config with targets #{targets}")
      cli = BeakerHostGenerator::CLI.new([targets, '--disable-default-role', '--osinfo-version', '1'])

      FileUtils.mkdir_p(File.dirname(config))
      File.open(config, 'w') do |fh|
        fh.print(cli.execute)
      end
    end
  end

  module CronUtils
    def clean(agent, o={})
      o = {:user => 'tstuser'}.merge(o)
      run_cron_on(agent, :remove, o[:user])
      apply_manifest_on(agent, %[user { '%s': ensure => absent, managehome => false }] % o[:user])
    end

    def setup(agent, o={})
      o = {:user => 'tstuser'}.merge(o)
      apply_manifest_on(agent, %[user { '%s': ensure => present, managehome => false }] % o[:user])
      apply_manifest_on(agent, %[case $operatingsystem {
                                   centos, redhat: {$cron = 'cronie'}
                                   solaris: { $cron = 'core-os' }
                                   default: {$cron ='cron'} }
                                   package {'cron': name=> $cron, ensure=>present, }])
    end
  end

  module CAUtils

    def initialize_ssl
      hostname = on(master, 'facter hostname').stdout.strip
      fqdn = on(master, 'facter fqdn').stdout.strip

      if master.use_service_scripts?
        step "Ensure puppet is stopped"
        # Passenger, in particular, must be shutdown for the cert setup steps to work,
        # but any running puppet master will interfere with webrick starting up and
        # potentially ignore the puppet.conf changes.
        on(master, puppet('resource', 'service', master['puppetservice'], "ensure=stopped"))
      end

      step "Clear SSL on all hosts"
      hosts.each do |host|
        ssldir = on(host, puppet('agent --configprint ssldir')).stdout.chomp
        on(host, "rm -rf '#{ssldir}'")
      end

      step "Master: Start Puppet Master" do
        master_opts = {
          :main => {
            :dns_alt_names => "puppet,#{hostname},#{fqdn}",
          },
          :__service_args__ => {
            # apache2 service scripts can't restart if we've removed the ssl dir
            :bypass_service_script => true,
          },
        }
        with_puppet_running_on(master, master_opts) do

          hosts.each do |host|
            next if host['roles'].include? 'master'

            step "Agents: Run agent --test first time to gen CSR"
            on host, puppet("agent --test --server #{master}"), :acceptable_exit_codes => [1]
          end

          # Sign all waiting certs
          step "Master: sign all certs"
          on master, puppet("cert --sign --all"), :acceptable_exit_codes => [0,24]

          step "Agents: Run agent --test second time to obtain signed cert"
          on agents, puppet("agent --test --server #{master}"), :acceptable_exit_codes => [0,2]
        end
      end
    end

    def clean_cert(host, cn, check = true)
      if host == master && master[:is_puppetserver]
          on master, puppet_resource("service", master['puppetservice'], "ensure=stopped")
      end

      on(host, puppet('cert', 'clean', cn), :acceptable_exit_codes => check ? [0] : [0, 24])
      if check
        assert_match(/remov.*Certificate.*#{cn}/i, stdout, "Should see a log message that certificate request was removed.")
        on(host, puppet('cert', 'list', '--all'))
        assert_no_match(/#{cn}/, stdout, "Should not see certificate in list anymore.")
      end
    end

    def clear_agent_ssl
      return if master.is_pe?
      step "All: Clear agent only ssl settings (do not clear master)"
      hosts.each do |host|
        next if host == master
        ssldir = on(host, puppet('agent --configprint ssldir')).stdout.chomp
        (host[:platform] =~ /cisco_nexus/) ? on(host, "rm -rf #{ssldir}") : on(host, host_command("rm -rf '#{ssldir}'"))
      end
    end

    def reset_agent_ssl(resign = true)
      return if master.is_pe?
      clear_agent_ssl

      hostname = master.execute('facter hostname')
      fqdn = master.execute('facter fqdn')

      step "Clear old agent certificates from master" do
        agents.each do |agent|
          next if agent == master && agent.is_using_passenger?
          agent_cn = on(agent, puppet('agent --configprint certname')).stdout.chomp
          clean_cert(master, agent_cn, false) if agent_cn
        end
      end

      if resign
        step "Master: Ensure the master is listening and autosigning"
        with_puppet_running_on(master,
                                :master => {
                                  :dns_alt_names => "puppet,#{hostname},#{fqdn}",
                                  :autosign => true,
                                }
                              ) do

          agents.each do |agent|
            next if agent == master && agent.is_using_passenger?
            step "Agents: Run agent --test once to obtain auto-signed cert" do
              on agent, puppet('agent', "--test --server #{master}"), :acceptable_exit_codes => [0,2]
            end
          end
        end
      end
    end
  end

  module CommandUtils
    def ruby_command(host)
      "env PATH=\"#{host['privatebindir']}:${PATH}\" ruby"
    end
    module_function :ruby_command

    def gem_command(host, type='aio')
      if type == 'aio'
        if host['platform'] =~ /windows/
          "env PATH=\"#{host['privatebindir']}:${PATH}\" cmd /c gem"
        else
          "env PATH=\"#{host['privatebindir']}:${PATH}\" gem"
        end
      else
        on(host, 'which gem').stdout.chomp
      end
    end
    module_function :gem_command
  end
end
