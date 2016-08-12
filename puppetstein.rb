#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require_relative 'lib/platform.rb'
require_relative 'lib/presuite.rb'
require_relative 'lib/util/platform_utils.rb'
require_relative 'lib/util/git_utils.rb'
require_relative 'lib/util/log_utils.rb'
require 'cri'
require 'git'
require 'json'

include Puppetstein
include Puppetstein::Presuite
include Puppetstein::PlatformUtils
include Puppetstein::GitUtils
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
  # don't sort options
  # build forces a build - always install
  # use mktemp
  # allow path to tests
  # add package installer helper / setup steps

  # Use puppetserver
  # PR testing: provide pr, get info and build it
  # Option: use local changes rather than github -> --puppet_repo=<blah> --puppet_sha=<blah>
  # Option: load in JSON config
  option nil, :puppet_agent, 'specify base puppet-agent version', argument: :optional
  option :p, :platform, 'which platform to install on', argument: :required
  option :b, :build, 'build mode: force puppetstein to build a new PA', argument: :optional
  option nil, :package, 'path to a puppet-agent package to install', argument: :optional

  # TODO: if file: then use local checkout
  option nil, :puppet, 'separated with a :', argument: :optional
  option nil, :facter, 'separated with a :', argument: :optional
  option nil, :hiera, 'separated with a :', argument: :optional

  option nil, :host, 'use a pre-provisioned host. Useful for re-running tests', argument: :optional

  option :t, :tests, 'tests to run against a puppet-agent installation', argument: :optional
  option :k, :keyfile, 'keyfile to use with vmpooler', argument: :optional

  run do |opts, args, cmd|

    platform = Platform.new(opts.fetch(:platform))
    platform.hostname = opts.fetch(:host) if opts[:host]
    build_mode = opts.fetch(:build) if opts[:build]
    package = opts.fetch(:package) if opts[:package]
    tests = opts.fetch(:tests) if opts[:tests]
    platform.keyfile = opts.fetch(:keyfile) if opts[:keyfile]

    if build_mode && platform.hostname
      log_notice("ERROR: build and preprovisioned host modes conflict!")
      exit 1
    end

    if build_mode && package
      log_notice("ERROR: build mode and pre-built package modes conflict!")
      exit 1
    end

    if opts[:puppet_agent]
      pa_fork, pa_version = opts[:puppet_agent].split(':')
    else
      pa_fork = 'puppetlabs'
      pa_version = 'master'
    end

    installed = false
    ######################
    # Just run tests on pre-provisioned host if we have one
    ######################
    if platform.hostname
      installed = true
    end

    ######################
    # Request a VM to use for the duration of the run
    ######################
    platform.hostname = request_vm(platform)
    install_prerequisite_packages(platform)

    ######################
    # If we already have a package, install it
    ######################
    if package
      remote_copy(platform, package, '/root')
      install_puppet_agent_on_vm(platform)
      installed = true
    end

    ######################
    # Patch mode: Install PA package from web and patch with updates
    # Only works for Ruby projects
    # Or, if no components are being changed, install from web
    ######################
    if (!opts[:facter] && !build_mode && !installed)
      # Patch ruby projects rather than build new package
      patchable_projects = ['puppet', 'hiera']

      result = install_puppet_agent_from_url_on_vm(platform, pa_version)

      # If we successfully grabbed PA from the web, we can patch. Otherwise, we build
      if result == 0
        patchable_projects.each do |project|
          if opts[:"#{project}"]
            project_fork, project_version = opts[:"#{project}"].split(':')
            patch_project_on_host(platform, project, project_fork, project_version )
          end
        end

        # TODO: leave big note that the VM is alive with FQDN
        # Use case: I want to install a hacked up PA for manual inspection
        installed = true
      end
    end

    ######################
    # Build mode
    # build a new puppet-agent package locally
    ######################
    if !installed
      log_notice("Building puppet-agent: #{pa_fork}:#{pa_version}")
      clone_repo('puppet-agent', pa_fork, pa_version)

      ##
      # Update the PA components with specified versions
      ['puppet', 'facter', 'hiera'].each do |project|
        if opts[:"#{project}"]
          project_fork, project_sha = opts[:"#{project}"].split(':')
          change_component_ref(project, "git://github.com/#{project_fork}/project.git", project_sha)
        else
          project_fork = 'puppetlabs'
          project_sha = 'master'
        end

        clone_repo(project, project_fork, project_sha)
      end

      ##
      # Build puppet-agent
      build_puppet_agent(platform)  #TODO: install existing local build rather than new
      package_path = save_puppet_agent_artifact(platform)
      remote_copy(platform, package_path, '/root')
      install_puppet_agent_on_vm(platform)
      installed = true
    end

    # Run tests if specified
    if tests && installed
      run_tests_on_host(platform, tests)
    end
    #cleanup
  end
end

def run_tests_on_host(platform, tests)
  hosts_file = '/tmp/hosts.yml'
  generate_host_config(platform, hosts_file)

  test_groups = tests.split(',')
  test_groups.each do |test|
    project, test = test.split(':')
    log_notice("Cloning #{project} to obtain tests...")
    clone_repo(project, 'puppetlabs', 'master')

    cmd = "export RUBYLIB=/tmp/#{project}/acceptance/lib && pushd /tmp/#{project}/acceptance " +
          "&& bundle install && bundle exec beaker --hosts #{hosts_file} " +
          "--tests #{test} --no-provision --debug"
    cmd = cmd + " --keyfile=#{platform.keyfile}" if platform.keyfile

    execute(cmd)
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

  cmd = "pushd /tmp/puppet-agent && bundle install && bundle exec build puppet-agent" +
        " #{platform.family}-#{platform.version}-#{platform.vanagon_arch} && popd"

  cmd = cmd + " VANAGON_SSH_KEY=#{keyfile}" if platform.keyfile
  execute(cmd)
end

def cleanup
  `rm -rf /tmp/puppet-agent`
end

command.run(ARGV)
