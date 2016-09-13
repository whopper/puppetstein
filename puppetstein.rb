#! /usr/bin/env ruby

require 'cri'
require 'git'
require 'yaml'
require_relative 'lib/host'
require_relative 'lib/util/common_utils.rb'
require_relative 'lib/util/platform_utils.rb'
require_relative 'lib/util/git_utils.rb'
require_relative 'lib/util/log_utils.rb'

include Puppetstein
include Puppetstein::PlatformUtils
include Puppetstein::BeakerUtils
include Puppetstein::GitUtils
include Puppetstein::LogUtils
include Beaker::DSL::InstallUtils::FOSSUtils

command = Cri::Command.define do
  name 'puppetstein'
  usage 'puppetstein [options] [arguments]

         Example: puppetstein --puppet=whopper:my_branch --tests=facter:tests/facts/el.rb --platform=centos-7-x86_64'

  summary 'Standalone puppet-agent composing and testing tool'
  description 'A tool to automate the building and composition of various versions of
               puppet-agent components for development and testing'

  flag   :h, :help, 'show help for this command' do |value, cmd|
    puts cmd.help
    exit 0
  end

  # TODO: allow tests from multiple projects to be run
  # TODO; allow testing multiple agent platforms at once
  # TODO: glob tests and test libs together for uber test

  option nil, :puppet_agent, 'specify base puppet-agent version', argument: :optional
  option :p, :platform, 'which platform to install on', argument: :optional
  flag :b, :build, 'build mode: force puppetstein to build a new PA', argument: :optional
  option nil, :package, 'path to a puppet-agent package to install', argument: :optional
  option nil, :puppet, 'separated with a :', argument: :optional
  option nil, :facter, 'separated with a :', argument: :optional
  option nil, :hiera, 'separated with a :', argument: :optional
  option nil, :agent, 'use a pre-provisioned agent. Useful for re-running tests. Requires --master option as well', argument: :optional
  option nil, :master, 'use a pre-provisioned master. Useful for re-running tests. Requires --agent option as well', argument: :optional
  flag nil, :use_last, 'use hosts from the last run', argument: :optional
  option :t, :tests, 'tests to run against a puppet-agent installation', argument: :optional
  option nil, :acceptancedir, 'colon separated list of directories where tests and test libraries can be found', argument: :optional
  option :k, :keyfile, 'keyfile to use with vmpooler', argument: :optional
  flag :nil, :noop, 'noop mode - output beaker command to run but don\'t execute', argument: :optional

  run do |opts, args, cmd|
    if opts[:platform]
      agent = Host.new(opts.fetch(:platform))
      master = Host.new('redhat-7-x86_64')
    else
      agent = Host.new('ubuntu-1604-amd64')
      master = Host.new('redhat-7-x86_64')
    end

    agent.hostname = opts.fetch(:agent) if opts[:agent]  # Preprovisioned agent
    master.hostname = opts.fetch(:master) if opts[:master]  # Preprovisioned master
    keyfile = opts[:keyfile] ? opts.fetch(:keyfile) : nil
    build_mode = opts.fetch(:build) if opts[:build]
    use_last = opts.fetch(:use_last) if opts[:use_last]
    package = opts.fetch(:package) if opts[:package]
    tests = opts.fetch(:tests) if opts[:tests]
    acceptancedir = opts.fetch(:acceptancedir) if opts[:acceptancedir]
    tmp = tmpdir
    config = "#{tmp}/hosts.yaml"

    # Check for conflicting options
    if (use_last || opts[:agent]) && (opts[:puppet_agent] || opts[:puppet] || opts[:hiera] || opts[:facter])
      log_notice('ERROR: using preprovisioned system - ignoring request for modified components')
      exit 1
    end

    ###
    # Get puppet_agent version info
    ###
    if opts[:puppet_agent]
      pa_version = parse_project_version(opts.fetch(:puppet_agent))
    else
      pa_version = Hash.new
      pa_version[:fork] = 'puppetlabs'
      pa_version[:sha] = 'nightly'
    end

    ENV['PA_SHA'] = pa_version[:sha]
    ENV['PA_SUITE'] = opts.fetch(:puppet_agent_suite_version) if opts[:puppet_agent_suite_version]
    log_notice("Using puppet-agent base version #{pa_version[:sha]}")

    ###
    # Setup tests: clone the proper repo(s) at the proper SHAs
    ###
    if tests
      project, test = tests.split(':')
      if acceptancedir
        ENV['RUBYLIB'] = "#{acceptancedir}/lib"
        test_location = "#{acceptancedir}/#{test}"
        log_notice("Using acceptancedir #{acceptancedir}/lib and test location #{acceptancedir}/#{test}")
      else
        if opts[:"#{project}"]
          # A topic branch may contain new acceptance tests, so clone it for tests.
          if pr = /pr_(\d+)/.match(opts[:"#{project}"])
            # This is a pull request number. Get the fork and branch
            v = parse_project_version(get_ref_from_pull_request(p, pr[1]))
          else
            v = parse_project_version(opts[:"#{project}"])
          end
        else
          v = Hash.new
          v[:fork] = 'puppetlabs'
          v[:sha] = 'master'
        end

        log_notice("Cloning tests: #{project}: #{v[:fork]}:#{v[:sha]}")
        clone_repo(project, v[:fork], v[:sha], tmp) if !opts[:noop]
        ENV['RUBYLIB'] = "#{tmp}/#{project}/acceptance/lib"
        test_location = "#{tmp}/#{project}/acceptance/#{test}"
        log_notice("Using acceptancedir #{tmp}/#{project}/acceptance/lib and test location #{tmp}/#{project}/acceptance/#{test}")
      end
    end

    ###
    # use_last mode: use the last host config we have with the given tests
    ###
    if use_last
      log_notice("Using last pre-provisioned hosts...")
      options = {'hosts' => 'log/latest/hosts_preserved.yml'}
      options['tests'] = test_location if tests
      options['keyfile'] = keyfile if keyfile
      options['noop'] = opts[:noop]
      run_beaker(options)

      if !opts[:noop]
        log = get_latest_host_config
        print_report({:agent => log[:HOSTS].keys[0], :master => log[:HOSTS].keys[1], :puppet_agent => "#{pa_version[:fork]}:#{pa_version[:sha]}"})
      end
      exit 0
    end

    ###
    # hostname mode: if give an agent and master hostname, use those with given tests
    ###
    if agent.hostname && master.hostname
      create_host_config([agent, master], config)
      options = {'hosts' => config, 'flag' => 'no-provision'}
      options['tests'] = test_location if tests
      options['keyfile'] = keyfile if keyfile
      options['noop'] = opts[:noop]
      run_beaker(options)
      if !opts[:noop]
        print_report({:agent => agent.hostname, :master => master.hostname, :puppet_agent => "#{pa_version[:fork]}:#{pa_version[:sha]}"})
      end
      exit 0
    end

    ###
    # build_mode: build a puppet_agent package with given component SHAs
    ###
    if build_mode
      pa_version[:sha] = 'master' if pa_version[:sha] == 'nightly'
      clone_repo('puppet-agent', pa_version[:fork], pa_version[:sha], tmp) if !opts[:noop]
      create_host_config([agent, master], config)

      ##
      # Update the PA components with specified versions
      ['puppet', 'facter', 'hiera'].each do |p|
        if opts[:"#{p}"]
          if pr = /pr_(\d+)/.match(opts[:"#{p}"])
            # This is a pull request number. Get the fork and branch
            v = parse_project_version(get_ref_from_pull_request(p, pr[1]))
          else
            v = parse_project_version(opts[:"#{p}"])
          end

          change_component_ref(p, "git://github.com/#{v[:fork]}/#{p}.git", v[:sha], tmp, opts[:noop])
        end
      end

      build_puppet_agent(agent, keyfile, tmp) if !opts[:noop]
      package = save_puppet_agent_artifact(agent, tmp)

      ENV['PACKAGE'] = package
      log_notice("Using newly built package #{package}")

      pre_suites = ['lib/setup/build/pre-suite', 'lib/setup/common/pre-suite']
      options = {'hosts' => config, 'pre-suite' => pre_suites.join(',')}
      options['tests'] = test_location if tests
      options['keyfile'] = keyfile if keyfile
      options['noop'] = opts[:noop]
      run_beaker(options)

      if !opts[:noop]
        log = get_latest_host_config
        print_report({:agent => log[:HOSTS].keys[0], :master => log[:HOSTS].keys[1], :puppet_agent => "#{pa_version[:fork]}:#{pa_version[:sha]}"})
      end
      exit 0
    end

    ###
    # package mode: use an existing package on the local filesystem
    ###
    if package
      create_host_config([agent, master], config)
      ENV['PACKAGE'] = package
      log_notice("Using prebuilt package #{package}")

      pre_suites = ['lib/setup/build/pre-suite', 'lib/setup/common/pre-suite']
      options = {'hosts' => config, 'pre-suite' => pre_suites.join(',')}
      options['tests'] = test_location if tests
      options['keyfile'] = keyfile if keyfile
      options['noop'] = opts[:noop]
      run_beaker(options)

      if !opts[:noop]
        log = get_latest_host_config
        print_report({:agent => log[:HOSTS].keys[0], :master => log[:HOSTS].keys[1], :puppet_agent => "#{pa_version[:fork]}:#{pa_version[:sha]}"})
      end
      exit 0
    end

    ###
    # Patch mode: If no other mode was specifically requested, try to patch a component
    ###
    patchable_projects = ['puppet', 'hiera', 'facter']
    patchable_projects.each do |p|
      if opts[:"#{p}"]
        if pr = /pr_(\d+)/.match(opts[:"#{p}"])
          # This is a pull request number. Get the fork and branch
          v = parse_project_version(get_ref_from_pull_request(p, pr[1]))
        else
          v = parse_project_version(opts[:"#{p}"])
        end

        ENV["#{p}"] = "#{v[:fork]}:#{v[:sha]}"
        log_notice("Using #{p}: #{v[:fork]}:#{v[:sha]}")
      end
    end

    create_host_config([agent, master], config)
    pre_suites = ['lib/setup/patch/pre-suite', 'lib/setup/common/pre-suite']
    options = {'hosts' => config, 'pre-suite' => pre_suites.join(',')}
    options['tests'] = test_location if tests
    options['keyfile'] = keyfile if keyfile
    options['noop'] = opts[:noop]
    run_beaker(options)

    if !opts[:noop]
      log = get_latest_host_config
      print_report({:agent => log[:HOSTS].keys[0], :master => log[:HOSTS].keys[1], :puppet_agent => "#{pa_version[:fork]}:#{pa_version[:sha]}"})
    end
    exit 0
  end
end

def parse_project_version(option)
  keys = option.split(':')
  if keys.length == 2
    project_fork = keys[0]
    project_sha = keys[1]
  else
    project_fork = 'puppetlabs'
    project_sha = keys[0]
  end
  project_sha = 'nightly' if project_sha == 'latest'
  {:fork => project_fork, :sha => project_sha}
end

def tmpdir
  `mktemp -d /tmp/puppetstein.XXXXX`.chomp!
end

def change_component_ref(component_name, url, ref, tmp, noop=nil)
  new_ref = Hash.new
  new_ref['url'] = url
  new_ref['ref'] = ref
  File.write("#{tmp}/puppet-agent/configs/components/#{component_name}.json", JSON.pretty_generate(new_ref)) if !noop
  log_notice("updated #{tmp}/puppet-agent/configs/components/#{component_name}.json with url #{url} and ref #{ref}")
end

def build_puppet_agent(host, keyfile, tmp)
  log_notice("building puppet-agent for #{host.family} #{host.version} #{host.arch}")

  ENV['VANAGON_SSH_KEY'] = keyfile if keyfile
  cmd = "pushd #{tmp}/puppet-agent && bundle install && bundle exec build puppet-agent" +
        " #{host.vanagon_string} && popd"
  execute(cmd)
end

def build_facter
  # 1) Clone, build and install leatherman (check if it exists? Require it?)
  # 1.5) Clone, build and install cpp-hocon??
  # 2) Clone and build facter
  # 3) copy libfacter.so to VM and put in on top of the old one
end

def cleanup
  `rm -rf #{tmpdir}`
end

if __FILE__ == $0
  command.run(ARGV)
end
