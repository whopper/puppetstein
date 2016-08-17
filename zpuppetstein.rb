#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

require 'cri'
require 'git'
require 'yaml'
require 'beaker-hostgenerator'
require 'beaker/dsl/install_utils'
require_relative 'lib/host'
require_relative 'lib/util/platform_utils.rb'

include Puppetstein
include Puppetstein::PlatformUtils

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
  # fix the ruby thing
  # allow path to tests

  # Use puppetserver and patch the agent on the server
  # Always install PA latest and just patch?
  # Option: use local changes rather than github -> --puppet_repo=<blah> --puppet_sha=<blah>

  option nil, :puppet_agent, 'specify base puppet-agent version', argument: :optional
  option :p, :platform, 'which platform to install on', argument: :required
  option :b, :build, 'build mode: force puppetstein to build a new PA', argument: :optional
  option nil, :package, 'path to a puppet-agent package to install', argument: :optional

  # TODO: if file: then use local checkout
  option nil, :puppet, 'separated with a :', argument: :optional
  option nil, :facter, 'separated with a :', argument: :optional
  option nil, :hiera, 'separated with a :', argument: :optional

  option nil, :agent, 'use a pre-provisioned host. Useful for re-running tests', argument: :optional

  option :t, :tests, 'tests to run against a puppet-agent installation', argument: :optional
  option :k, :keyfile, 'keyfile to use with vmpooler', argument: :optional

  run do |opts, args, cmd|
    agent = Host.new(opts.fetch(:platform))
    master = Host.new('redhat-7-x86_64')
    agent.agentname = opts.fetch(:agent) if opts[:agent]  # Preprovisioned agent
    agent.keyfile = opts.fetch(:keyfile) if opts[:keyfile]
    master.keyfile = opts.fetch(:keyfile) if opts[:keyfile]
    build_mode = opts.fetch(:build) if opts[:build]
    package = opts.fetch(:package) if opts[:package]
    tests = opts.fetch(:tests) if opts[:tests]
    config = "tmp/hosts.yaml"

    if opts[:puppet_agent]
      pa_fork, pa_sha = opts.fetch(:puppet_agent).split(':')
    else
      pa_fork = 'puppetlabs'
      pa_sha = 'nightly'
    end

    ENV['PA_SHA'] = pa_sha
    ENV['PA_SUITE'] = opts.fetch(:puppet_agent_suite_version) if opts[:puppet_agent_suite_version]

    if agent.hostname
      # Pre-provisioned mode. Basically just run tests.
    end

    if build_mode || opts[:facter]
      # Build package and install it on agent and master
      # Get empty VMs from beaker and go from there. Beaker may be able to help.
      # See beaker scp_to method. This stuff will all happen in a presuite script.
      # Presuites: scp and install package on agent
      #            scp and install package on master
      #            install puppetserver on master
      #            sign agent cert on master
      # Then, run any tests
      create_host_config([agent, master], config)
    end

    if package
      # We already have a built package. Just do the same stuff as build_mode
      # except building the package.
      # Presuites: scp and install package on agent
      #            scp and install package on master
      #            install puppetserver on master
      #            sign agent cert on master
      # Then, run any tests
      create_host_config([agent, master], config)
    end

    # Patch mode
    # 1) Use beaker to create new VMs and install PA of the proper version on them.
    #    If we can't install from the web, fall back to building.
    # 2) Get the branch of the patched project, clone it on the VM and patch it
    # Presuites: Install and patch PA from web on agent  - catch a failure here and build instead
    #            Install and patch PA on master
    #            Install puppetserver on master
    #            sign agent cert on master
    # Then, run any tests
    create_host_config([agent, master], config)
    execute("bundle exec beaker --hosts=#{config} --type=aio --pre-suite=./lib/setup/patch/pre-suite,lib/setup/common/pre-suite --keyfile=#{agent.keyfile} --preserve-hosts=never")
  end
end

def create_host_config(hosts, config)
  targets = "#{hosts[0].flavor}#{hosts[0].version}-64a-#{hosts[1].flavor}#{hosts[1].version}-64m"
  cli = BeakerHostGenerator::CLI.new([targets, '--disable-default-role', '--osinfo-version', '1'])

  FileUtils.mkdir_p(File.dirname(config))
  File.open(config, 'w') do |fh|
    fh.print(cli.execute)
  end
end

def change_component_ref(component_name, url, ref)
  new_ref = Hash.new
  new_ref['url'] = url
  new_ref['ref'] = ref
  File.write("#{host.local_tmpdir}/puppet-agent/configs/components/#{component_name}.json", JSON.pretty_generate(new_ref))
  log_notice("updated #{host.local_tmpdir}/puppet-agent/configs/components/#{component_name}.json with url #{url} and ref #{ref}")
end

def build_puppet_agent(host)
  log_notice("building puppet-agent for #{host.family} #{host.version} #{host.arch}")

  cmd = "pushd #{host.local_tmpdir}/puppet-agent && bundle install && bundle exec build puppet-agent" +
        " #{host.family}-#{host.version}-#{host.vanagon_arch} && popd"

  cmd = cmd + " VANAGON_SSH_KEY=#{host.keyfile}" if host.keyfile
  execute(cmd)
end

def cleanup
  `rm -rf #{host.local_tmpdir}/puppet-agent`
end

command.run(ARGV)
