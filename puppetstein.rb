#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require_relative 'lib/platform.rb'
require_relative 'lib/util/platform_utils.rb'
require_relative 'lib/util/git_utils.rb'
require_relative 'lib/util/vm_utils.rb'
require_relative 'lib/util/log_utils.rb'
require 'cri'
require 'git'
require 'json'

include Puppetstein
include Puppetstein::PlatformUtils
include Puppetstein::GitUtils
include Puppetstein::VMUtils
include Puppetstein::LogUtils

command = Cri::Command.define do
  name 'puppetstein'
  usage 'puppetstein [options] [arguments]

         Example: puppetstein --puppet_agent=puppetlabs:1.5.4 --puppet=whopper:my_branch --hack --install --tests=./puppet/acceptance/tests --platform=centos-7-x86_64'

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
  # Option: use local changes rather than github -> --puppet_repo=<blah> --puppet_sha=<blah>
  # Option: load in JSON config
  option nil, :puppet_agent, 'specify base puppet-agent version', argument: :optional
  option :p, :platform, 'which platform to install on', argument: :required
  option :i, :install, 'install the composed puppet-agent package on a VM', argument: :optional

  option nil, :hack, 'hack mode: patch installed PA with puppet/hiera', argument: :optional
  option :b, :build, 'build mode: force puppetstein to build a new PA', argument: :optional

  # if file: then use local checkout
  option nil, :puppet, 'separated with a :', argument: :optional
  option nil, :facter, 'separated with a :', argument: :optional
  option nil, :hiera, 'separated with a :', argument: :optional

  option nil, :pre_provisioned_host, 'use a pre-provisioned host. Useful for re-running tests', argument: :optional

  option :t, :tests, 'tests to run against a puppet-agent installation', argument: :optional

  run do |opts, args, cmd|

    platform = Platform.new(opts.fetch(:platform))
    platform.hostname = opts.fetch(:pre_provisioned_host) if opts[:pre_provisioned_host]

    ######################
    # Option parsing: error on incompatible options
    ######################
    install = opts.fetch(:install) if opts[:install]
    hack_mode = opts.fetch(:hack) if opts[:hack]
    build_mode = opts.fetch(:build) if opts[:build]
    tests = opts.fetch(:tests) if opts[:tests]

    if hack_mode && build_mode
      log_notice("ERROR: hack and build modes conflict!")
      exit 1
    end

    if hack_mode && opts[:facter]
      log_notice("ERROR: hack mode and custom facter build conflict!")
      exit 1
    end

    if !install && !opts[:pre_provisioned_host] && tests
      log_notice("ERROR: must install puppet-agent on a vmpooler VM to run tests!")
      exit 1
    end

    if opts[:puppet_agent]
      pa_fork, pa_version = opts[:puppet_agent].split(':')
    else
      pa_fork = 'puppetlabs'
      pa_version = 'master'
    end

    ######################
    # Just run tests on pre-provisioned host if we have one, and then exit
    ######################
    if platform.hostname
      if tests
        run_tests_on_host(platform, tests)
      end
      exit
    end

    ######################
    # Hack mode: Install PA package from web and patch with updates
    # Only works for Ruby projects
    # Or, if no components are being changed, install from web
    ######################
    if hack_mode || (!opts[:facter] && !opts[:puppet] && !opts[:hiera] && !build_mode)
      # Hacky bit: for Ruby projects, hack in changes rather than building new package
      # First, install specified PA version on host
      # then, figure out changed files in SHA. Download and replace existing files with them
      # Run tests
      platform.hostname = request_vm(platform)
      install_puppet_agent_from_url_on_vm(platform, pa_version)

      # replace_files_on_host(list, paths) ?
      # test, exit
      if opts[:puppet]
        puppet_fork, puppet_version = opts[:puppet].split(':')
        log_notice("Patching puppet-agent with puppet: #{puppet_fork}:#{ puppet_version}")
        patch_project_on_host(platform, 'puppet', puppet_fork, puppet_version )
      end

      if opts[:hiera]
        hiera_fork, hiera_version = opts[:hiera].split(':')
        log_notice("Patching puppet-agent with hiera: #{hiera_fork}:#{hiera_version}")
        patch_project_on_host('hiera', hiera_fork, hiera_version )
      end

      # TODO: leave big note that the VM is alive with FQDN
      # Use case: I want to install a hacked up PA for manual inspection
      if tests
        run_tests_on_host(platform, tests)
      end
      exit 0
    end

    ######################
    # Build mode
    # build a new puppet-agent package locally
    ######################
    clone_repo('puppet-agent', pa_fork, pa_version)

    ##
    # Update the PA components with specified versions
    if opts[:puppet]
      puppet_fork, puppet_sha = opts[:puppet].split(':')
      change_component_ref("puppet", "git://github.com/#{puppet_fork}/puppet.git", puppet_sha)
    else
      puppet_fork = 'puppetlabs'
      puppet_sha = 'master'
    end

    clone_repo('puppet', puppet_fork, puppet_sha)

    if opts[:facter]
      facter_fork, facter_sha = opts[:facter].split(':')
      change_component_ref("facter", "git://github.com/#{facter_fork}/facter.git", facter_sha)
    else
      facter_fork = 'puppetlabs'
      facter_sha = 'master'
    end

    clone_repo('facter', facter_fork, facter_sha)

    if opts[:hiera]
      hiera_fork, hiera_sha = opts[:hiera].split(':')
      change_component_ref("hiera", "git://github.com/#{hiera_fork}/hiera.git", hiera_sha)
    else
      hiera_fork = 'puppetlabs'
      hiera_sha = 'master'
    end

    clone_repo('hiera', hiera_fork, hiera_sha)

    ##
    # Build puppet-agent
    build_puppet_agent(platform) if build_mode
    package_path = get_puppet_agent_package_output_path(platform)

    ##
    # Install the newly built PA package if install option is set
    if install
      platform.hostname = request_vm(platform)
      copy_package_to_vm(platform, package_path)
      install_puppet_agent_on_vm(platform)

      # Run tests if specified
      if tests
        run_tests_on_host(platform, tests)
      end
    end
    #cleanup
  end
end

def run_tests_on_host(platform, tests)
  # Need host config... need master...?
  if platform.family == 'el'
    os = platform.flavor
  else
    os = platform.family
  end

  IO.popen("bundle exec beaker-hostgenerator #{os}#{platform.version}-64ma{hostname=#{platform.hostname}.delivery.puppetlabs.net} > /tmp/puppet-agent/hosts.yml")
  test_groups = tests.split(',')
  test_groups.each do |test|
    project, test = test.split(':')
    IO.popen("export RUBYLIB=/tmp/#{project}/acceptance/lib && pushd /tmp/#{project}/acceptance && bundle install && bundle exec beaker --hosts /tmp/puppet-agent/hosts.yml --tests #{test} --no-provision --keyfile=~/.ssh/id_rsa-acceptance --debug") do |io|
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

def build_puppet_agent(platform)
  log_notice("building puppet-agent for #{platform.family} #{platform.version} #{platform.arch}")
  IO.popen("VANAGON_SSH_KEY=~/.ssh/id_rsa-acceptance && pushd /tmp/puppet-agent && bundle install && bundle exec build puppet-agent #{platform.family}-#{platform.version}-#{platform.vanagon_arch} && popd") do |io|
    while (line = io.gets) do
      puts line
    end
  end
end

def cleanup
  `rm -rf output/*`
  `rm -rf /tmp/puppet-agent`
end

command.run(ARGV)
