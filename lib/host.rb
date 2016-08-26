module Puppetstein
  class Host
    attr_accessor :string # platform
    attr_accessor :family_string
    attr_accessor :family
    attr_accessor :flavor
    attr_accessor :version
    attr_accessor :arch
    attr_accessor :vanagon_arch
    attr_accessor :hostname

    def initialize(platform)
      @string        = platform
      @family        = get_platform_family(@string)
      @flavor        = get_platform_flavor(@string)
      @version       = get_platform_version(@string)
      @arch          = get_platform_arch(@string)
      @vanagon_arch  = get_vanagon_arch(@string)
      @family_string = "#{@family}-#{@version}-#{@arch}"
    end

    def get_platform_family(platform_string)
      p = platform_string.split('-')
      case p[0]
      when 'centos', 'redhat'
        'el'
      when 'debian', 'ubuntu'
        'debian'
      when 'win'
        'win'
      end
    end

    def get_platform_flavor(platform_string)
      base = platform_string.split('-')[0]
      version = get_platform_version(platform_string)
      case base
        when 'redhat', 'centos'
          base
        when 'win'
          'windows'
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
  end
end
