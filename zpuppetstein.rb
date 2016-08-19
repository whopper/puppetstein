#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require 'cri'
require 'git'
require 'yaml'
require 'beaker-hostgenerator'
require 'beaker/platform'
require 'beaker/logger'
require 'beaker/result'
require 'beaker/dsl/install_utils'
require 'beaker/dsl/install_utils/foss_utils'
require 'beaker/options/options_hash.rb'
require_relative 'lib/host'
require_relative 'lib/util/platform_utils.rb'
require_relative 'lib/util/git_utils.rb'

include Puppetstein
include Puppetstein::PlatformUtils
include Puppetstein::GitUtils
include Beaker::DSL::InstallUtils::FOSSUtils

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

  # TODO: allow tests from multiple projects to be run
  # TODO; allow testing multiple agent platforms at once
  # TODO: glob tests and test libs together for uber test

  option nil, :puppet_agent, 'specify base puppet-agent version', argument: :optional
  option :p, :platform, 'which platform to install on', argument: :optional
  option :b, :build, 'build mode: force puppetstein to build a new PA', argument: :optional
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

  run do |opts, args, cmd|
    if opts[:platform]
      agent = Host.new(opts.fetch(:platform))
      master = Host.new('redhat-7-x86_64')
    else
      agent = Host.new('ubuntu-1604-x86_64')
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

    default_beaker_options = {
      'type' => 'aio',
      'keyfile' => keyfile,
      'preserve-hosts' => 'always'
    }

    # Check for conflicting options
    if (use_last || opts[:agent]) && (opts[:puppet_agent] || opts[:puppet] || opts[:hiera] || opts[:facter])
      log_notice('ERROR: using preprovisioned system - ignoring request for modified components')
      exit 1
    end

    if opts[:puppet_agent]
      pa_fork, pa_sha = opts.fetch(:puppet_agent).split(':')
    else
      # TODO: builds.puppetlabs doesn't have latest...
      pa_fork = 'puppetlabs'
      pa_sha = 'latest'
    end

    ENV['PA_SHA'] = pa_sha
    ENV['PA_SUITE'] = opts.fetch(:puppet_agent_suite_version) if opts[:puppet_agent_suite_version]

    if tests
      # --tests=facter:facts/el.rb
      # --acceptancedir=~/Coding/facter/acceptance
      project, test = tests.split(':')
      if acceptancedir
        ENV['RUBYLIB'] = "#{acceptancedir}/lib"
        test_location = "#{acceptancedir}/tests/#{test}"
      else
        clone_repo(project, 'puppetlabs', 'master', tmp)
        ENV['RUBYLIB'] = "#{tmp}/#{project}/acceptance/lib"
        test_location = "#{tmp}/#{project}/acceptance/tests/#{test}"
      end
    end

    if use_last
      options = {'hosts' => 'log/latest/hosts_preserved.yml'}
      options['tests'] = test_location if tests
      run_beaker(options.merge(default_beaker_options))

      log = YAML.load_file('log/latest/hosts_preserved.yml')
      print_report({:agent => log[:HOSTS].keys[0], :master => log[:HOSTS].keys[1], :puppet_agent => "#{pa_fork}:#{pa_sha}"})
      exit 0
    end

    if agent.hostname && master.hostname
      create_host_config([agent, master], config)
      options = {'hosts' => config, 'flag' => 'no-provision'}
      options['tests'] = test_location if tests
      run_beaker(options.merge(default_beaker_options))

      print_report({:agent => agent.hostname, :master => master.hostname, :puppet_agent => "#{pa_fork}:#{pa_sha}"})
      exit 0
    end

    if build_mode || opts[:facter]
      clone_repo('puppet-agent', pa_fork, pa_sha, tmp)
      create_host_config([agent, master], config)

      ##
      # Update the PA components with specified versions
      ['puppet', 'facter', 'hiera'].each do |p|
        if opts[:"#{p}"]
          if pr = /pr_(\d+)/.match(opts[:"#{p}"])
            # This is a pull request number. Get the fork and branch
            project_fork, project_sha = get_ref_from_pull_request(p, pr[1]).split(':')
          else
            project_fork, project_sha = opts[:"#{p}"].split(':')
          end

          change_component_ref(p, "git://github.com/#{project_fork}/#{p}.git", project_sha, tmp)
        end
      end

      build_puppet_agent(agent, keyfile, tmp)
      package = save_puppet_agent_artifact(agent, tmp)

      ENV['PACKAGE'] = package

      pre_suites = ['lib/setup/build/pre-suite', 'lib/setup/common/pre-suite']
      options = {'hosts' => config, 'pre-suite' => pre_suites.join(',')}
      options['tests'] = test_location if tests
      run_beaker(options.merge(default_beaker_options))

      log = YAML.load_file('log/latest/hosts_preserved.yml')
      print_report({:agent => log[:HOSTS].keys[0], :master => log[:HOSTS].keys[1], :puppet_agent => "#{pa_fork}:#{pa_sha}"})
      exit 0
    end

    if package
      create_host_config([agent, master], config)
      ENV['PACKAGE'] = package

      pre_suites = ['lib/setup/build/pre-suite', 'lib/setup/common/pre-suite']
      options = {'hosts' => config, 'pre-suite' => pre_suites.join(',')}
      options['tests'] = test_location if tests
      run_beaker(options.merge(default_beaker_options))

      log = YAML.load_file('log/latest/hosts_preserved.yml')
      print_report({:agent => log[:HOSTS].keys[0], :master => log[:HOSTS].keys[1], :puppet_agent => "#{pa_fork}:#{pa_sha}"})
      exit 0
    end

    # Patch mode: If no other mode was specifically requested
    patchable_projects = ['puppet', 'hiera']
    patchable_projects.each do |p|
      if opts[:"#{p}"]
        if pr = /pr_(\d+)/.match(opts[:"#{p}"])
          # This is a pull request number. Get the fork and branch
          project_fork, project_sha = get_ref_from_pull_request(p, pr[1]).split(':')
        else
          project_fork, project_sha = opts[:"#{p}"].split(':')
        end

        ENV["#{p.upcase}"] = "#{project_fork}:#{project_sha}"
      end
    end

    create_host_config([agent, master], config)
    pre_suites = ['lib/setup/patch/pre-suite', 'lib/setup/common/pre-suite']
    options = {'hosts' => config, 'pre-suite' => pre_suites.join(',')}
    options['tests'] = test_location if tests
    run_beaker(options.merge(default_beaker_options))

    log = YAML.load_file('log/latest/hosts_preserved.yml')
    print_report({:agent => log[:HOSTS].keys[0], :master => log[:HOSTS].keys[1], :puppet_agent => "#{pa_fork}:#{pa_sha}"})
    exit 0
  end
end

def run_beaker(args = {})
  options = ''
  args.each do |k,v|
    if k == 'flag'
      options = options + "--#{v}"
    else
      options = options + "--#{k}=#{v} "
    end
  end

  cmd = "bundle exec beaker #{options} --debug"
  puts cmd
  execute(cmd)
end

def create_host_config(hosts, config)
  if hosts[0].hostname && hosts[1].hostname
    targets = "#{hosts[0].flavor}#{hosts[0].version}-64a{hostname=#{hosts[0].hostname}}-#{hosts[1].flavor}#{hosts[1].version}-64m{hostname=#{hosts[1].hostname}}"
  else
    targets = "#{hosts[0].flavor}#{hosts[0].version}-64a-#{hosts[1].flavor}#{hosts[1].version}-64m"
  end

  cli = BeakerHostGenerator::CLI.new([targets, '--disable-default-role', '--osinfo-version', '1'])

  FileUtils.mkdir_p(File.dirname(config))
  File.open(config, 'w') do |fh|
    fh.print(cli.execute)
  end
end

def tmpdir
  `mktemp -d /tmp/puppetstein.XXXXX`.chomp!
end

def print_report(report)
  puts "\n\n"
  puts "====================================="
  puts "Run Report"
  puts "====================================="
  report.each do |k,v|
    puts "#{k}: #{v}"
  end
  puts "====================================="
end

def change_component_ref(component_name, url, ref, tmp)
  new_ref = Hash.new
  new_ref['url'] = url
  new_ref['ref'] = ref
  File.write("#{tmp}/puppet-agent/configs/components/#{component_name}.json", JSON.pretty_generate(new_ref))
  log_notice("updated #{tmp}/puppet-agent/configs/components/#{component_name}.json with url #{url} and ref #{ref}")
end

def build_puppet_agent(host, keyfile, tmp)
  log_notice("building puppet-agent for #{host.family} #{host.version} #{host.arch}")

  ENV['VANAGON_SSH_KEY'] = keyfile if keyfile
  cmd = "pushd #{tmp}/puppet-agent && bundle install && bundle exec build puppet-agent" +
        " #{host.family}-#{host.version}-#{host.vanagon_arch} && popd"
  execute(cmd)
end

def cleanup
  `rm -rf #{tmpdir}`
end

command.run(ARGV)
