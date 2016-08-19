require_relative '../../../util/install_utils.rb'

test_name "Install puppet_agent from local package"

agents.each do |agent|
  tmpdir = agent.tmpdir('puppet_agent')

  step "Copy package to #{agent}" do
    scp_to(agent, ENV['PACKAGE'], tmpdir)
  end

  step "Install package on #{agent}" do
    agent.install_package("#{tmpdir}/#{File.basename(ENV['PACKAGE'])}")
  end
end
