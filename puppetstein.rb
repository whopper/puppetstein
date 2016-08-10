#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require './lib/util/platform_utils.rb'
require './lib/util/git_utils.rb'
require './lib/util/vm_utils.rb'
require './lib/util/log_utils.rb'
require 'cri'
require 'git'
require 'json'

include Puppetstein::PlatformUtils
include Puppetstein::GitUtils
include Puppetstein::VMUtils
include Puppetstein::LogUtils

command = Cri::Command.define do
  name 'puppetstein'
  usage 'puppetstein [options] [arguments]

         Example: puppetstein 1.5.4 --install --vmpooler --tests=./puppet/acceptance/tests'

  summary 'Standalone puppet-agent composing and testing tool'
  description 'A tool to automate the building and composition of various versions of
               puppet-agent components for development and testing'

  flag   :h, :help, 'show help for this command' do |value, cmd|
    puts cmd.help
    exit 0
  end

  # TODO:
  # Use puppetserver
  # PR testing: provide pr, get info and build it
  # Option: hack in non-compiled bits. Can combine with PR testing for puppet
  # Option: use local changes rather than github -> --puppet_repo=<blah> --puppet_sha=<blah>
  # Option: install PA:<something/master> from package on VM
  # Option: load in JSON config
  option nil, :puppet_agent, 'specify base puppet-agent version', argument: :required
  option :i, :install, 'install the composed puppet-agent package on a VM', argument: :optional
  option :p, :platform, 'which platform to install on', argument: :optional
  option nil, :puppet, 'which fork and SHA of puppet to use, separated with a :', argument: :optional
  option nil, :facter, 'which fork and SHA of facter to use, separated with a :', argument: :optional
  option nil, :host, 'use a pre-provisioned host. Useful for re-running tests', argument: :optional
  option :t, :tests, 'tests to run against a puppet-agent installation', argument: :optional
  option :d, :debug, 'debug mode', argument: :optional

  run do |opts, args, cmd|
    install = opts.fetch(:install) if opts[:install]
    tests = opts.fetch(:tests) if opts[:tests]
    platform = opts.fetch(:platform) if opts[:platform]
    host = opts.fetch(:host) if opts[:host]
    debug = opts.fetch(:debug) if opts[:debug]
    #pa_path = '/tmp/puppet-agent'

    # TODO: stick these in a helper class object
    platform_family = get_platform_family(platform)
    platform_version = get_platform_version(platform)
    platform_flavor = get_platform_flavor(platform)
    platform_arch = get_platform_arch(platform)
    vanagon_arch = get_vanagon_platform_arch(platform)

    if host
      # Just run tests on pre-provisioned host
      if tests
        run_tests_on_host(host, platform_family, platform_flavor, platform_version, tests)
      end
      exit
    end

    if opts[:puppet_agent]
      pa_fork, pa_version = opts[:puppet_agent].split(':')
    else
      pa_fork = 'puppetlabs'
      pa_version = 'master'
    end

    if (!opts[:facter] && (opts[:puppet] || opts[:hiera])) || (!opts[:facter] && !opts[:puppet] && !opts[:hiera])
      # Hacky bit: for Ruby projects, hack in changes rather than building new package
      # First, install specified PA version on host
      # then, figure out changed files in SHA. Download and replace existing files with them
      # Run tests
      hostname = request_vm(platform)
      install_puppet_agent_from_url_on_vm(hostname,
                                          pa_version,
                                          platform_family,
                                          platform_flavor,
                                          platform_version,
                                          vanagon_arch)

      # install_puppet_agent_from_web_on_vm()
      # get_changed_file_list()
      # replace_files_on_host(list, paths) ?
      # test, exit
      if opts[:puppet]
        log_notice('Patching puppet-agent with puppet PR')
      end

      if opts[:hiera]
        log_notice('Patching puppet-agent with hiera PR')
      end

      # TODO: leave big note that the VM is alive with FQDN
      if tests
        run_tests_on_host(hostname, platform_family, platform_flavor, platform_version, tests)
      end
      exit
    end

    # Hacking puppet-agent phase
    clone_repo('puppet-agent', pa_fork, pa_version)

    if opts[:puppet]
      puppet_fork, puppet_sha = opts[:puppet].split(':')
      change_component_ref("puppet", "git://github.com/#{puppet_fork}/puppet.git", puppet_sha)
      clone_repo('puppet', puppet_fork, puppet_sha)
    else
      clone_repo('puppet', 'puppetlabs', 'master')
    end

    if opts[:facter]
      facter_fork, facter_sha = opts[:facter].split(':')
      change_component_ref("facter", "git://github.com/#{facter_fork}/facter.git", facter_sha)
      clone_repo('facter', facter_fork, facter_sha)
    else
      clone_repo('facter', 'puppetlabs', 'master')
    end

    if opts[:hiera]
      hiera_fork, hiera_sha = opts[:hiera].split(':')
      change_component_ref("hiera", "git://github.com/#{hiera_fork}/hiera.git", hiera_sha)
      clone_repo('hiera', hiera_fork, hiera_sha)
    else
      clone_repo('hiera', 'puppetlabs', 'master')
    end

    # Build phase
    build_puppet_agent(platform_family, platform_version, platform_arch, vanagon_arch) unless debug
    package_path = get_puppet_agent_package_output_path(platform_family, platform_flavor, platform_version, platform_arch)

    if install
      hostname = request_vm(platform)
      copy_package_to_vm(hostname, package_path)
      install_puppet_agent_on_vm(hostname, platform_family)

      if tests
        run_tests_on_host(hostname, platform_family, platform_flavor, platform_version, tests)
      end
    end
    #cleanup
  end
end

def run_tests_on_host(hostname, platform_family, platform_flavor, platform_version, tests)
  # Need host config... need master...?
  IO.popen("bundle exec beaker-hostgenerator #{platform_family}#{platform_version}-64ma{hostname=#{hostname}.delivery.puppetlabs.net} > /tmp/puppet-agent/hosts.yml")
  test_groups = tests.split(',')
  test_groups.each do |test|
    project, test = test.split(':')
    IO.popen("export RUBYLIB=/tmp/#{project}/acceptance/lib && pushd /tmp/#{project}/acceptance && bundle install && bundle exec beaker --hosts /tmp/puppet-agent/hosts.yml --tests #{test} --no-provision always --keyfile=~/.ssh/id_rsa-acceptance --debug") do |io|
      while (line = io.gets) do
        puts line
      end
    end
  end
end

def change_component_ref(component_name, url, ref)
  new_ref = Hash.new
  new_ref['url'] = url
  new_ref['ref'] = ref
  File.write("/tmp/puppet-agent/configs/components/#{component_name}.json", JSON.pretty_generate(new_ref))
  log_notice("updated /tmp/puppet-agent/configs/components/#{component_name}.json with url #{url} and ref #{ref}")
end

def build_puppet_agent(platform_family, platform_version, platform_arch, vanagon_arch)
  log_notice("building puppet-agent for #{platform_family} #{platform_version} #{platform_arch}")
  IO.popen("VANAGON_SSH_KEY=~/.ssh/id_rsa-acceptance && pushd /tmp/puppet-agent && bundle install && bundle exec build puppet-agent #{platform_family}-#{platform_version}-#{vanagon_arch} && popd") do |io|
    while (line = io.gets) do
      puts line
    end
  end
end

def fetch_puppet_agent_package(version, platform)
  # http://builds.puppetlabs.lan/puppet-agent/1.5.3/artifacts/el/7/PC1/x86_64/puppet-agent-1.5.3-1.el7.x86_64.rpm
  os, os_ver, arch = platform.split('-')
  package_name = "puppet-agent-#{version}-1.#{os}#{os_ver}.#{arch}.rpm"

  log_notice("Fetching puppet-agent #{version}...")
  IO.popen("wget -r -nH -nd -np -R 'index.html*' http://builds.puppetlabs.lan/puppet-agent/#{version}/artifacts/#{os}/#{os_ver}/PC1/#{arch}/ -P ./output -o /dev/null")
  log_notice("Done! Package in output/#{package_name}")
  "./output/#{package_name}"
end

def cleanup
  `rm -rf output/*`
  `rm -rf /tmp/puppet-agent`
end

command.run(ARGV)
