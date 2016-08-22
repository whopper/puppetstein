module Puppetstein
  class Host
    attr_accessor :string # platform
    attr_accessor :family_string
    attr_accessor :family
    attr_accessor :flavor
    attr_accessor :version
    attr_accessor :arch
    attr_accessor :vanagon_arch
    attr_accessor :package_command
    attr_accessor :package_manager_command
    attr_accessor :hostname
    attr_accessor :keyfile
    attr_accessor :local_tmpdir # scratch space for building puppet-agent locally

    def initialize(platform)
      @string        = platform
      @family        = get_platform_family(@string)
      @flavor        = get_platform_flavor(@string)
      @version       = get_platform_version(@string)
      @arch          = get_platform_arch(@string)
      @vanagon_arch  = get_vanagon_arch(@string)
      @package_command         = get_package_command(@family)
      @package_manager_command = get_package_manager_command(@family)
      @local_tmpdir = tmpdir
      @family_string = "#{@family}-#{@version}-#{@arch}"
    end

    def get_platform_family(platform_string)
      p = platform_string.split('-')
      case p[0]
      when 'centos', 'redhat'
        'el'
      when 'debian', 'ubuntu'
        'debian'
      end
    end

    def get_platform_flavor(platform_string)
      base = platform_string.split('-')[0]
      version = get_platform_version(platform_string)
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

    def get_platform_version(platform_string)
      platform_string.split('-')[1]
    end

    def get_platform_arch(platform_string)
      platform_string.split('-')[2]
    end

    # When building puppet-agent, debian based beaker_platform_strings use 'amd' instead of 'x86'
    def get_vanagon_arch(platform_string)
      case platform_string.split('-')[0]
      when 'debian', 'ubuntu'
        'amd64'
      else
        platform_string.split('-')[2]
      end
    end

    def get_package_type(platform_string)
      case platform_string.split('-')[0]
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
          'apt-get update && apt-get -y install'
      end
    end

    def tmpdir
      `mktemp -d /tmp/puppetstein.XXXXX`.chomp!
    end
  end
end
