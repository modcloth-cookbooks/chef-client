#
# Author:: Joshua Timberman (<joshua@opscode.com>)
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Author:: Bryan Berry (<bryan.berry@gmail.com>)
# Cookbook Name:: chef-client
# Recipe:: cron 
#
# Copyright 2009-2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

root_group = value_for_platform(
                                ["openbsd", "freebsd", "mac_os_x"] => { "default" => "wheel" },
                                "default" => "root"
                                )

# COOK-635 account for alternate gem paths
# try to use the bin provided by the node attribute
if ::File.executable?(node["chef_client"]["bin"])
  client_bin = node["chef_client"]["bin"]
  # search for the bin in some sane paths
elsif Chef::Client.const_defined?('SANE_PATHS') && (chef_in_sane_path=Chef::Client::SANE_PATHS.map{|p| p="#{p}/chef-client";p if ::File.executable?(p)}.compact.first) && chef_in_sane_path
  client_bin = chef_in_sane_path
  # last ditch search for a bin in PATH
elsif (chef_in_path=%x{which chef-client}.chomp) && ::File.executable?(chef_in_path)
  client_bin = chef_in_path
else
  raise "Could not locate the chef-client bin in any known path. Please set the proper path by overriding node['chef_client']['bin'] in a role."
end

%w{run_path cache_path backup_path log_dir}.each do |key|
  directory node["chef_client"][key] do
    recursive true
    owner "root"
    group root_group
    mode 0755
  end
end

case node['platform']
when "smartos"
  local_path = ::File.join(Chef::Config[:file_cache_path], "/")
  
  directory "/etc/svc/method" do
    action :create
  end
  
  template "/etc/svc/method/chef-client" do
     source "smartos/chef-client.erb"
     owner "root"
     group "root"
     mode "0777"
   end

  template (local_path + "chef-client.xml") do
    source "smartos/manifest.xml.erb"
    owner "root"
    group "root"
    mode "0644"
    notifies :run, "execute[load chef-client manifest]", :immediately
  end

  cron "chef-client" do
    minute node['chef_client']['cron']['minute']	
    hour	node['chef_client']['cron']['hour']
    path node['chef_client']['cron']['path'] if node['chef_client']['cron']['path']
    user	"root"
    shell	"/bin/bash"
    if node['chef-client']['enabled'] == true
      command "/opt/local/bin/sleep `/opt/local/bin/expr $RANDOM \\% 90` &> /dev/null ; #{client_bin} 2>&1 >> #{node['chef_client']['log_dir']}/client.log"
    elsif node['chef-client']['enabled'] == false
      command "# /opt/local/bin/sleep `/opt/local/bin/expr $RANDOM \\% 90` &> /dev/null ; #{client_bin} 2>&1 >> #{node['chef_client']['log_dir']}/client.log"
    end
  end
  
       
  execute "load chef-client manifest" do
    command "svccfg import #{local_path}chef-client.xml"
  end
  
  service "chef-client" do
    action [:disable, :stop]
    provider Chef::Provider::Service::Solaris
  end
else
  dist_dir, conf_dir = value_for_platform(
                                          ["ubuntu", "debian"] => { "default" => ["debian", "default"] },
                                          ["redhat", "centos", "fedora", "scientific", "amazon"] => { "default" => ["redhat", "sysconfig"]}
                                          )

  # let's create the service file so the :disable action doesn't fail
  template "/etc/init.d/chef-client" do
    source "#{dist_dir}/init.d/chef-client.erb"
    mode 0755
    variables(
              :client_bin => client_bin
              )
  end

  template "/etc/#{conf_dir}/chef-client" do
    source "#{dist_dir}/#{conf_dir}/chef-client.erb"
    mode 0644
  end
  
  cron "chef-client" do
    minute node['chef_client']['cron']['minute']	
    hour	node['chef_client']['cron']['hour']
    path node['chef_client']['cron']['path'] if node['chef_client']['cron']['path']
    user	"root"
    shell	"/bin/bash"
    command "/opt/local/bin/sleep `/opt/local/bin/expr $RANDOM \\% 90` &> /dev/null ; #{client_bin} 2>&1 >> #{node['chef_client']['log_dir']}/client.log"
  end

  service "chef-client" do
    supports :status => true, :restart => true
    action [:disable, :stop]
  end
end

