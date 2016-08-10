#! /Users/whopper/.rbenv/shims/ruby

#! /usr/env/ruby

module Puppetstein
  module PlatformUtils

    def get_platform_family(beaker_platform_string)
      p = beaker_platform_string.split('-')
      case p[0]
      when 'centos', 'redhat'
        'el'
      when 'debian', 'ubuntu'
        'debian'
      end
    end

    def get_platform_flavor(beaker_platform_string)
      base = beaker_platform_string.split('-')[0]
      version = beaker_platform_string.split('-')[1]
      case base
        when 'redhat', 'centos'
          base
        when 'debian', 'ubuntu'
          case version
            when '7'
              'wheezy'
            when '8'
              'jessie'
            when '9'
              'stretch'
            when '1204'
              'precise'
            when '1404'
              'trusty'
            when '1504'
              'vivid'
            when '1510'
              'wily'
            when '1604'
              'xenial'
          end
      end
    end

    def get_platform_version(beaker_platform_string)
      beaker_platform_string.split('-')[1]
    end

    def get_platform_arch(beaker_platform_string)
      beaker_platform_string.split('-')[2]
    end

    # When building puppet-agent, debian based beaker_platform_strings use 'amd' instead of 'x86'
    def get_vanagon_platform_arch(beaker_platform_string)
      case beaker_platform_string.split('-')[0]
      when 'debian', 'ubuntu'
        'amd64'
      else
        beaker_platform_string.split('-')[2]
      end
    end

    def get_package_type(beaker_platform_string)
      case beaker_platform_string.split('-')[0]
      when 'centos', 'redhat', 'el'
        'rpm'
      else
        'deb'
      end
    end

    def get_package_command(platform_family)
      case platform_family
        when 'el'
          'rpm -i'
        when 'debian'
          'dpkg -i'
      end
    end

    def get_package_manager_command(platform_family)
      case platform_family
        when 'el'
          'yum -y install'
        when 'debian'
          'apt-get -y install'
      end
    end

    def get_puppet_agent_package_output_path(platform_family, platform_flavor, platform_version, platform_arch)
      desc = `git --git-dir=/tmp/puppet-agent/.git describe`
      case platform_family
        when 'el'
        "/tmp/puppet-agent/output/el/#{platform_version}/PC1/#{platform_arch}/puppet-agent-#{desc.gsub('-','.').chomp}-1.el#{platform_version}.#{platform_arch}.rpm"
        when 'debian'
        "/tmp/puppet-agent/output/deb/#{platform_flavor}/PC1/puppet-agent_#{desc.gsub('-','.').chomp}-1#{platform_flavor}_#{get_vanagon_platform_arch("debian-#{platform_version}-#{platform_arch}")}.deb"
      end
    end
  end
end
