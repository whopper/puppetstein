#! /Users/whopper/.rbenv/shims/ruby

require_relative 'git_utils.rb'
require_relative 'log_utils.rb'
require "net/http"

include Puppetstein::GitUtils
include Puppetstein::LogUtils

#! /usr/env/ruby
module Puppetstein
  module PlatformUtils
    def execute(command)
      IO.popen(command) do |io|
        while (line=io.gets) do
          puts line
        end
      end
    end

    def remote_command(host, command)
      puts "COMMAND: #{command}"
      puts "KEYFILE: #{host.keyfile}"
      cmd = "ssh -o StrictHostKeyChecking=no "
      cmd = cmd + "-i #{host.keyfile} " if host.keyfile
      cmd = cmd + "root@#{host.hostname} '#{command}'"
      execute(cmd)
    end

    def remote_copy(host, local_file, remote_path)
      cmd = "scp -r -o StrictHostKeyChecking=no "
      cmd = cmd + "-i #{host.keyfile} " if host.keyfile
      cmd = cmd + "#{local_file} root@#{host.hostname}:#{remote_path}"
      execute(cmd)
    end

    def request_vm(host)
      log_notice("Acquiring VM: #{host.string}")
      output = `curl -d --url http://vmpooler.delivery.puppetlabs.net/vm/#{host.string} ;`
      match = /\"hostname\": \"(.*)\"/.match(output)
      log_notice("Done! Hostname: #{match[1]}")
      match[1]
    end

    def patch_project_on_host(host, project, project_fork, project_version)
      # TODO: clone on remote system
      log_notice("Patching #{project} on #{host.hostname} with #{project_version}")
      clone_repo(project, project_fork, project_version, host.local_tmpdir)

      remote_copy(host, "#{host.local_tmpdir}/#{project}/lib", '/root')
      pl_dir = '/opt/puppetlabs/puppet/lib/ruby/vendor_ruby/'
      remote_command(host, "/bin/cp -rf /root/lib/* #{pl_dir}")
    end

    def install_puppet_agent_on_vm(host)
      # TODO: don't just assume we're installing /root/pkg
      log_notice("Installing puppet-agent on #{host.hostname}")
      remote_command(host, "#{host.package_command} /root/puppet-agent* && ln -s /opt/puppetlabs/bin/* /usr/bin")
      log_notice("Done!")
    end

    def install_puppet_agent_from_url_on_vm(host, pa_version)
      base_url = 'http://builds.puppetlabs.lan/puppet-agent'
      case host.family
        when 'el'
          url = "#{base_url}/#{pa_version}/artifacts/el/#{host.version}/PC1/#{host.vanagon_arch}"
          package_regex = "puppet-agent*el#{host.version}\.#{host.vanagon_arch}*"
        when 'debian'
          url = "#{base_url}/#{pa_version}/artifacts/deb/#{host.flavor}/PC1/"
          package_regex = "puppet-agent*#{host.flavor}_#{host.vanagon_arch}*"
      end

      url = URI.parse(url)
      req = Net::HTTP.new(url.host, url.port)
      res = req.request_head(url.path)

      if res.code != "200"
        puts "Failed to download puppet-agent from builds.puppetlabs.lan"
        1
      end

      remote_command(host, "wget -r -nH -nd -R \'*bundle*\' #{url} -P /root -A \'*#{package_regex}*\' -o /dev/null")
      install_puppet_agent_on_vm(host)
      0
    end

    def generate_host_config(host, path="#{host.local_tmpdir}/hosts.yml")
      if host.family == 'el'
        os = host.flavor
      else
        os = host.family
      end

      execute("bundle exec beaker-hostgenerator #{os}#{host.version}-64ma{hostname=#{host.hostname}.delivery.puppetlabs.net} > #{path}")
    end

    def save_puppet_agent_artifact(host, tmp)
      desc = `git --git-dir=#{tmp}/puppet-agent/.git describe`
      case host.family
        when 'el'
        package = "puppet-agent-#{desc.gsub('-','.').chomp}-1.el#{host.version}.#{host.arch}.rpm"
        path = "#{host.local_tmpdir}/puppet-agent/output/el/#{host.version}/PC1/#{host.arch}/#{package}"
        when 'debian'
        package = "puppet-agent_#{desc.gsub('-''.').chomp}-1#{host.flavor}_#{host.vanagon_arch}.deb"
        path = "#{tmp}/puppet-agent/output/deb/#{host.flavor}/PC1/#{package}"
      end

      execute("mv #{path} #{tmp}")
      "#{tmp}/#{package}"
    end
  end
end
