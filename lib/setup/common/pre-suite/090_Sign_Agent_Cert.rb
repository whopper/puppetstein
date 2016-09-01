test_name "Sign agent cert on master"

require_relative '../../../util/common_utils.rb'
extend Puppetstein::CAUtils

initialize_ssl

agents.each do |agent|
  step "Add master to agent config and start puppetserver" do
    on(master, facter('fqdn')) do
      on(agent, "puppet config set --section main server #{stdout.chomp}")
    end

    on(master, puppet('resource', 'service', master['puppetservice'], "ensure=running"))
  end
end
