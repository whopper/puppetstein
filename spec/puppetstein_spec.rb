require 'spec_helper'

def run_puppetstein(opts)
  `ruby puppetstein.rb #{opts.join(' ')}`
end

#TODO: test build_mode

describe Puppetstein do
  common_opts = ['--platform=centos-7-x86_64', '--noop']

  context 'options parsing' do
    it 'should not allow conflicting options: `use_last` and project patches' do
      options = ['--use_last', '--puppet=whopper:amazing_test_branch']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/ERROR: using preprovisioned system - ignoring request for modified components/)
    end
  end

  context 'specifying component versions and using patch mode' do
    it 'should use the correct puppet-agent base version when specified' do
      options = ['--puppet_agent=123abc']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/--pre-suite=lib\/setup\/patch\/pre-suite/)
      expect(output).to match(/Using puppet-agent base version 123abc/)
    end

    it 'should use puppet-agent#nightly when PA version is not specified' do
      output = run_puppetstein(common_opts)
      expect(output).to match(/--pre-suite=lib\/setup\/patch\/pre-suite/)
      expect(output).to match(/Using puppet-agent base version nightly/)
    end

    ['puppet', 'facter', 'hiera'].each do |component|
      it "should use the correct #{component} component version when specified as a branch" do
        options = ["--#{component}=whopper:amazing_test_branch"]
        output = run_puppetstein(common_opts + options)
        expect(output).to match(/--pre-suite=lib\/setup\/patch\/pre-suite/)
        expect(output).to match(/Using #{component}: whopper:amazing_test_branch/)
      end
    end
  end

  context 'specifying tests' do
    it 'should use user-specified acceptancedir if provided' do
      options = ['--acceptancedir=/foo/bar', '--tests=facter:tests/facts/el.rb']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Using acceptancedir \/foo\/bar\/lib and test location \/foo\/bar\/tests\/facts\/el.rb/)
    end

    it 'should clone the puppetlabs:master branch for tests if component version not specified' do
      options = ['--tests=facter:tests/facts/el.rb']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Cloning tests: facter: puppetlabs:master/)
    end

    it 'should clone the specified component branch for tests' do
      options = ['--facter=whopper:amazing_test_branch', '--tests=facter:tests/facts/el.rb']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Cloning tests: facter: whopper:amazing_test_branch/)
    end
  end

  context 'use_last mode' do
    it 'should use the latest hosts_preserved.yml file' do
      options = ['--use_last']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Using last pre-provisioned hosts.../)
      expect(output).to match(/--hosts=log\/latest\/hosts_preserved.yml/)
    end
  end

  context 'pre-provisioned hostname mode' do
    it 'should create a host config with the specified hostname' do
      options = ['--agent=agenthost', '--master=masterhost']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Creating host config with targets centos7-64a{hostname=agenthost}-redhat7-64m{hostname=masterhost\,use-service=true}/)
    end
  end

  context 'package_mode' do
    it 'should use the specified package' do
      options = ['--package=foo/bar']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Using prebuilt package foo\/bar/)
      expect(output).to match(/--pre-suite=lib\/setup\/build\/pre-suite/)
    end
  end

  context 'platform support' do
    it 'should properly create Debian host configs' do
      options = ['--platform=debian-8-x86_64']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Creating host config with targets debian8-64a/)
    end

    it 'should properly create Ubuntu host configs' do
      options = ['--platform=ubuntu-1604-x86_64']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Creating host config with targets ubuntu1604-64a/)
    end

    it 'should properly create Centos host configs' do
      options = ['--platform=centos-7-x86_64']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Creating host config with targets centos7-64a/)
    end

    it 'should properly create RedHat host configs' do
      options = ['--platform=redhat-7-x86_64']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Creating host config with targets redhat7-64a/)
    end

    it 'should use ubuntu 16.04 as the default agent and redhat 7 as the default master' do
      output = run_puppetstein(['--noop'])
      expect(output).to match(/Creating host config with targets ubuntu1604-64a-redhat7-64m/)
    end

    it 'should properly create OSX host configs' do
      options = ['--platform=osx-1010-x86_64']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Creating host config with targets osx1010-64a/)
    end

    it 'should properly create Windows host configs' do
      options = ['--platform=win-2008-x86_64']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/Creating host config with targets windows2008-64a/)
    end
  end

  context 'misc options' do
    it 'should pass the specified keyfile to beaker' do
      options = ['--keyfile=/foo/bar']
      output = run_puppetstein(common_opts + options)
      expect(output).to match(/--keyfile=\/foo\/bar/)
    end

    it 'should not use the keyfile option in beaker if keyfile is not specified' do
      output = run_puppetstein(common_opts)
      expect(output).not_to match(/--keyfile\/foo\/bar/)
    end
  end
end
