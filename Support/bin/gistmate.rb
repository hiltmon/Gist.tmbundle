#!/usr/bin/env ruby -wKU

# gistmate.rb
# Hilton Lipschitz (http://www.hiltmon.com)
# Use and modify freely, attribution appreciated
# 
# This script allows you to get, list, create, and update Github gists
# from the command line. There are others like this but this one caches
# file names to gist mappings so you do not need to remember them. The 
# cache is just a YAML file in ~/.gists. This script also leaves
# the URL of the last gist accessed on the clipboard.
#
# WARNING: This only works with files in the current folder, paths are
# not supported in gists.
#
# WARNING: `get` supports multiple file gists but `create` and `update`
# work on single files only
#
# Prerequisites:
# You need to get your github user and pasword in either:
# - In git's global config as github.user and github.password
# - In your envronment as GITHUB_USER and GITHUB_PASSWORD
#
# Usage:
# gist get <id>           -> retrieves the numbered gist (if possible) and writes the file locally
# gist create <file_name> -> creates a new gist of the file and returns the gist_id
# gist update <file_name> -> updates an existing gist of the file and returns the gist_id
# gist url <file_name>    -> gets the gist URL for a file
# gist id <file_name>     -> Displays the ID for a file from the cache
# gist list <user_name>   -> Lists up to 100 gists for a given user name (API limit)
# gist view <id>          -> displays the gist to stdout
# gist raw <id>           -> returns the raw JSON for a gist_id

$: << "#{ENV['TM_BUNDLE_SUPPORT']}/lib" if ENV.has_key?('TM_BUNDLE_SUPPORT')

require 'net/https'
require 'uri'
require 'json'
require 'optparse'
require 'yaml'
require 'fileutils'
require "#{ENV['TM_SUPPORT_PATH']}/lib/exit_codes.rb"
require "#{ENV['TM_SUPPORT_PATH']}/lib/escape.rb"
require "#{ENV['TM_SUPPORT_PATH']}/lib/ui.rb"
require ENV['TM_SUPPORT_PATH'] + '/lib/tm/htmloutput'

class Gistmate
  
  VERSION = '0.0.1'
  AUTHOR = 'Hilton Lipschitz'
  TWITTER = '@hiltmon'
  HOME_URL = 'http://www.hiltmon.com'
  LEDE = 'Create, Retrieve and Update Gists'
  
  GIST_URL   = 'https://api.github.com/gists'
  WEB_URL   = 'https://gist.github.com'
  USER_URL   = 'https://api.github.com/users/%s/gists'
  CACHE_FILE_PATH = "#{ENV['HOME']}/.gists"
  
  def get(selection = nil)
    # Get the ID only (last number in the string)
    default = selection.match(/(\d+)\D*\z/) unless selection.nil?
    
    gist_id = TextMate::UI.request_string(
      :title => "Gist ID", 
      :prompt => "Enter the gist ID or URL.",
      :button1 => 'Get Gist',
      :default => default.to_s
    )
    TextMate.exit_discard if gist_id == nil
    
    textmate_get_gist(gist_id)
  end
  
  def pick()
    TextMate.exit_show_html(no_auth_message) if no_auth?
    user, _ = auth()
    results = list_gists(user)
    
    # Show pick list
    line = TextMate::UI.request_item(
      :title => "Pick a Gist",
      :prompt => "Select a Gist to Get:",
      :items => results,
      :button1 => 'Get Gist'
    )
    TextMate.exit_discard if line == nil
    
    gist_id = line.split(',')[0]
    textmate_get_gist(gist_id)
  end
  
  def url(path)
    filename = File.basename(path)
    text = url_gist(filename)
    TextMate.exit_show_html(no_gist_message) if text.nil?
    TextMate.exit_show_tool_tip("'#{text}' Copied to Clipboard.") unless text.nil?
  end
  
  def view_on_web(path)
    filename = File.basename(path)
    text = url_gist(filename)
    TextMate.exit_show_html(no_gist_message) if text.nil?
    %x{open #{text}}
  end
  
  def update(path)
    TextMate.exit_show_html(no_auth_message) if no_auth?
    filename = File.basename(path)
    
    gist_id = get_id_from_cache(filename)
    TextMate.exit_show_html(no_gist_message) if gist_id.nil?

    response = api_post_request([path], gist_id)
    unless response.nil?
      to_pasteboard(gist_id)
      TextMate.exit_show_tool_tip("'#{gist_id}' Updated.")
    end    
  end
  
  def create(path, is_private)
    TextMate.exit_show_html(no_auth_message) if no_auth?
    filename = File.basename(path)
    
    gist_id = get_id_from_cache(filename)
    TextMate.exit_show_html(is_gist_message) unless gist_id.nil?
    
    gist_id = create_gist(filename, is_private)
    unless gist_id.nil?
      TextMate.exit_show_tool_tip("'#{gist_id}' Created.")
    end
  end
  
  protected
    
  def create_gist(filename, is_private)
    response = api_post_request([filename], nil, is_private)
    unless response.nil?
      gist_id = response["id"]
      cache_gist(gist_id, [filename])
      to_pasteboard(gist_id)
      return gist_id
    end
    nil
  end
  
  def get_gist(gist_id)
    data = retrieve_gist(gist_id)
    return if data.nil?
    
    files_array = []
    data["files"].keys.each do |key|
      content = extract_content(data, key)
      file_name = extract_file_name(data, key)
      File.open(file_name, "w") do |f| # Ruby 1.8 Style (not IO.write)
        f << content
      end
      files_array << file_name
    end
    cache_gist(gist_id, files_array)
    files_array
  end
  
  def list_gists(user)
    response = api_get_request(USER_URL % user)
    results = []
    unless response.nil?
      response.each do |line|
        files_array = []
        line["files"].keys.each do |key|
          files_array << key
        end
        results << "#{line['id']},#{files_array.join(',')}"
      end
    end
    results
  end
  
  def url_gist(filename)
    gist_id = get_id_from_cache(filename)
    unless gist_id.nil?
      text = "#{WEB_URL}/#{gist_id}" 
      to_pasteboard(gist_id)
      return text
    end
    nil
  end
  
  def no_auth_message
    TextMate::HTMLOutput.show(
      :title      => "GitHub Authentication Error"
    ) do |io|
      io << <<-HTML
        <h3 class="error">GitHub Authentication is not set up.</h3>

        <p>The gists bundle needs your github user name and password to compleet this action.</p>

        <p>Either add github.user and github.password to your global git config, or set the
          GITHUB_USER and GITHUB_PASSWORD environment variables.</p>
      HTML
    end
  end
  
  def no_gist_message
    TextMate::HTMLOutput.show(
      :title      => "Gist Error"
    ) do |io|
      io << <<-HTML
        <h3 class="error">Unknown Gist.</h3>

        <p>This file is not part of a known gist. Either <strong>Create Gist</strong> to
          create a new gist, or <strong>Get Gist</strong> to retrieve a gist before
          editing. <strong>Warning:</strong> Get Gist will overwrite this file.</p>
      HTML
    end
  end

  def is_gist_message
    TextMate::HTMLOutput.show(
      :title      => "Gist Error"
    ) do |io|
      io << <<-HTML
        <h3 class="error">Gist already Created!</h3>

        <p>This file is part of a known gist. Either <strong>Update Gist</strong> to
          update it, or remove this gist from the cache and try again. The cache can
          be found in <code>~/.gists</code></p>
      HTML
    end
  end
  
  def textmate_get_gist(gist_id)
    files_array = get_gist(gist_id)
    unless files_array.nil?
      # Open em
      files_array.each do |file_name|
        %x{mate "#{file_name}"}
      end
    end
  end
  
  def retrieve_gist(params)
    api_get_request(GIST_URL + "/#{params}")
  end
  
  def extract_content(data, key)
    data["files"][key]["content"]
  end

  def extract_file_name(data, key)
    data["files"][key]["filename"]
    # data["files"].map{|name, content| content['filename'] }.join("\n\n")
  end
  
  def api_get_request(url, params = nil)
    uri = URI(url)
    uri.query = URI.encode_www_form(params) if params
        
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    
    request = Net::HTTP::Get.new(uri.request_uri)
    
    response = http.request(request)
    if response.code.to_i >= 300
      puts "Failed: #{response.code}: #{response.body}"
      return nil
    end
    JSON.parse(response.body)
  end
  
  def api_post_request(file_names, id = nil, is_private = false)
    url = GIST_URL
    url = "#{url}/#{id}" unless id.nil?
    uri = URI(url)
    # puts uri
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Post.new(uri.request_uri)
    request.body = JSON.generate(make_data(file_names, id, is_private))
    request["Content-Type"] = "application/json"
    user, password = auth()
    if user && password
      request.basic_auth(user, password)
    end

    response = http.request(request)
    # puts response.code
    # puts response.body
    if response.code.to_i >= 300
      puts "Failed: #{response.code}: #{response.body}"
      return nil
    end
    JSON.parse(response.body)
  end
  
  def make_data(file_names, id, is_private)
    file_data = {}
    file_names.each do |file_name|
      file_data[File.basename(file_name)] = {:content => IO.read(file_name).to_s }
    end

    data = {"files" => file_data}
    # data.merge!({ 'description' => description }) unless description.nil?
    if id.nil?
      data.merge!({ 'public' => !is_private})
    end
    data
  end
  
  def no_auth?
    user, password = auth()
    if user.to_s.empty? || password.to_s.empty?
      puts "Unable to proceed, you need to set your Github User and Password. Either set github.user and github.password in your global git config, or set GITHUB_USER and GITHUB_PASSWORD in the environment."
      return true
    end
    false # Ok to proceed
  end
    
  def auth
    user = `git config --global github.user`.strip
    user = ENV['GITHUB_USER'] if user.to_s.empty?

    password = `git config --global github.password`.strip
    password = ENV['GITHUB_PASSWORD'] if password.to_s.empty?
     
    [ user, password ]
  end
  
  def no_file?(file_name)
    unless File.exists?(file_name)
      puts "Unable to open the file #{file_name}."
      return true
    end
    false
  end
   
  def load_cache
    if File.exists?(CACHE_FILE_PATH)
      YAML.load_file(CACHE_FILE_PATH)
    else
      {} # New Hash
    end
  end
  
  def save_cache(cache_array)
    FileUtils.touch(CACHE_FILE_PATH)
    File.open(CACHE_FILE_PATH, "w") do |f| # Ruby 1.8 Style (not IO.write)
      f << cache_array.to_yaml
    end
  end
  
  def cache_gist(gist_id, files_array)
    cache = load_cache
    cache[gist_id] = files_array.join(',')
    save_cache(cache)
  end
  
  def get_id_from_cache(file_name)
    cache = load_cache
    cache.keys.each do |key|
      return key if cache[key].split(',').index(file_name)
    end
    nil
  end
  
  def to_pasteboard(gist_id)
    return unless RUBY_PLATFORM =~ /darwin/
    text = "#{WEB_URL}/#{gist_id}" 
    IO.popen('pbcopy', 'r+').puts text
  end
    
end
