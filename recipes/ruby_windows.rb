#
# Cookbook Name:: omnibus
# Recipe:: ruby_windows
#
# Copyright 2013, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe '7-zip::default'

# Determine download urls
ruby_version = node['omnibus']['ruby_version']
ruby_file_name = "ruby-#{ruby_version}-i386-mingw32.7z"
ruby_download_url = "http://dl.bintray.com/oneclick/rubyinstaller/#{ruby_file_name}?direct"

# Determine the directories where we will unpack ruby
file_cache_path = windows_safe_path_expand(Chef::Config[:file_cache_path])
unzip_dir_name = windows_safe_path_join(file_cache_path, File.basename(ruby_file_name, '.7z'))
ruby_package_path = windows_safe_path_join(file_cache_path, ruby_file_name)
zip_bin = windows_safe_path_join(node['7-zip']['home'], '7z.exe')

remote_file ruby_package_path do
  source ruby_download_url
  checksum node['omnibus']['windows']['win_ruby_checksum']
  not_if { File.exists?(ruby_package_path) }
end

install_dir = windows_safe_path_join(node['omnibus']['windows']['ruby_root'], ruby_version)
ruby_bindir = windows_safe_path_join(install_dir, 'bin')
ruby_bin = windows_safe_path_join(ruby_bindir, 'ruby.exe')

windows_batch 'unzip_ruby' do
  code <<-EOH
"#{zip_bin}\" x #{ruby_package_path} -o#{file_cache_path} -r -y
xcopy #{unzip_dir_name} \"#{install_dir}\" /I /e /y
EOH
  creates ruby_bin
  action :run
end

# Ensure Ruby's bin directory is in PATH
windows_path ruby_bindir do
  action :add
end

# Enable the DevKit
devkit_file_name = ::File.basename(node['omnibus']['windows']['dev_kit_url'])

file windows_safe_path_join(install_dir, 'config.yml') do
  content <<-EOH
# This configuration file contains the absolute path locations of all
# installed Rubies to be enhanced to work with the DevKit. This config
# file is generated by the 'ruby dk.rb init' step and may be modified
# before running the 'ruby dk.rb install' step. To include any installed
# Rubies that were not automagically discovered, simply add a line below
# the triple hyphens with the absolute path to the Ruby root directory.
#
# Example:
#
# ---
# - C:/ruby19trunk
# - C:/ruby192dev
#
---
- #{install_dir}
  EOH
end

remote_file windows_safe_path_join(file_cache_path, devkit_file_name) do
  source node['omnibus']['windows']['dev_kit_url']
  checksum node['omnibus']['windows']['dev_kit_checksum']
end

devkit_path = windows_safe_path_join(file_cache_path, devkit_file_name)
dk_rb_path = windows_safe_path_join(install_dir, 'dk.rb')

windows_batch 'install_devkit_and_enhance_ruby' do
  code <<-EOH
  #{devkit_path} -y -o\"#{install_dir}\"
  cd \"#{install_dir}\" & \"#{ruby_bin}\" \"#{dk_rb_path}\" install
  EOH
  action :run
  not_if { ::File.exists?(dk_rb_path) }
end

# Ensure a certificate authority is available and configured
# https://gist.github.com/fnichol/867550

cert_dir = windows_safe_path_join(install_dir, 'ssl', 'certs')
cacert_file = windows_safe_path_join(cert_dir, 'cacert.pem')

directory cert_dir do
  recursive true
  action :create
end

remote_file cacert_file do
  source 'http://curl.haxx.se/ca/cacert.pem'
  checksum 'f5f79efd63440f2048ead91090eaca3102d13ea17a548f72f738778a534c646d'
  action :create
end

ENV['SSL_CERT_FILE'] = cacert_file

env 'SSL_CERT_FILE' do
  value cacert_file
end

# Ensure Bundler is installed and available
gem_package 'bundler' do
  version '1.3.5'
  gem_binary ::File.join(ruby_bindir, 'gem')
end
