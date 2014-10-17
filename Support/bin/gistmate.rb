#!/usr/bin/env ruby18 -wKU

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
require 'tempfile'
require "#{ENV['TM_SUPPORT_PATH']}/lib/exit_codes.rb"
require "#{ENV['TM_SUPPORT_PATH']}/lib/escape.rb"
require "#{ENV['TM_SUPPORT_PATH']}/lib/ui.rb"
require "#{ENV['TM_SUPPORT_PATH']}/lib/osx/plist"
require "#{ENV['TM_SUPPORT_PATH']}/lib/progress"

class Gistmate
  
  VERSION = '0.0.1'
  AUTHOR = 'Hilton Lipschitz'
  TWITTER = '@hiltmon'
  HOME_URL = 'http://www.hiltmon.com'
  LEDE = 'Create, Retrieve and Update Gists'
  
  GIST_URL   = 'https://api.github.com/gists'
  WEB_URL   = 'https://gist.github.com'
  USER_URL   = 'https://api.github.com/users/%s/gists'
  ACCOUNT_URL   = 'https://api.github.com/user'
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
    abort_no_auth if no_auth?
    user = get_login()
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
    abort_no_gist if text.nil?
    TextMate.exit_show_tool_tip("'#{text}' Copied to Clipboard.") unless text.nil?
  end
  
  def view_on_web(path)
    filename = File.basename(path)
    text = url_gist(filename)
    abort_no_gist if text.nil?
    %x{open #{e_sh text}}
  end
  
  def update(path)
    abort_no_auth if no_auth?
    filename = File.basename(path)
    
    gist_id = get_id_from_cache(filename)
    abort_no_gist if gist_id.nil?

    response = api_post_request([path], "Updating Gist #{gist_id}...", gist_id)
    unless response.nil?
      to_pasteboard(gist_id)
      TextMate.exit_show_tool_tip("'#{gist_id}' Updated.")
    end    
  end
  
  def add_file_to_gist(path)
    abort_no_auth if no_auth?
    filename = File.basename(path)
    
    # gist_id = get_id_from_cache(filename)
    # abort_gist_already_exist unless gist_id.nil?
    
    # Bring up the pick list to add this file
    user = get_login()
    results = list_gists(user)
    
    # Show pick list
    line = TextMate::UI.request_item(
      :title => "Pick a Gist",
      :prompt => "Select a Gist to Add To:",
      :items => results,
      :button1 => 'Add To Gist'
    )
    TextMate.exit_discard if line == nil
    
    # Ok, we have a line, first token is the gist id
    gist_id = line.split(',')[0]
    
    response = api_post_request([path], "Adding to Gist #{gist_id}...", gist_id)
    unless response.nil?
      append_to_cache(gist_id, filename)
      to_pasteboard(gist_id)
      TextMate.exit_show_tool_tip("'#{gist_id}' Added To.")
    end   
  end
  
  def create(path, is_private)
    abort_no_auth if no_auth?
    filename = File.basename(path)
    
    gist_id = get_id_from_cache(filename)
    abort_gist_already_exist unless gist_id.nil?
    
    gist_id = create_gist(path, is_private)
    unless gist_id.nil?
      TextMate.exit_show_tool_tip("'#{gist_id}' Created.")
    end
  end
  
  def create_from_selection(content, path)
    abort_no_auth if no_auth?
    abort_no_selection if content.nil? || content.length == 0
    if path.nil? || path.length == 0
      ext = ''
    else
      ext = File.extname(path)
    end
    
    gist_id = create_temp_gist(content, ext)
    unless gist_id.nil?
      TextMate.exit_show_tool_tip("'#{gist_id}' Created.")
    end
  end
  
  protected
    
  def create_gist(filename, is_private)
    response = api_post_request([filename], "Creating New Gist...", nil, is_private)
    unless response.nil?
      gist_id = response["id"]
      cache_gist(gist_id, [File.basename(filename)])
      to_pasteboard(gist_id)
      return gist_id
    end
    nil
  end
  
  def create_temp_gist(content, ext)
    # temp_file = Tempfile.new("xyzzy-gist#{ext}")
    temp_file = Tempfile.new("xyzzygist#{ext}-") # Hyphen needed to clean up file name on send
    File.open(temp_file.path, "w") do |f| # Ruby 1.8 Style (not IO.write)
      f << content
    end
    
    response = api_post_request([temp_file.path], "Creating New Uncached Gist...", nil, false)
    unless response.nil?
      gist_id = response["id"]
      to_pasteboard(gist_id)
      temp_file.close
      return gist_id
    end
    
    temp_file.close
    nil
  end
  
  def get_gist(gist_id)
    data = retrieve_gist(gist_id)
    return if data.nil?
    
    files_array = {}
    data["files"].keys.each do |key|
      content = extract_content(data, key)
      file_name = extract_file_name(data, key) || key
      # file_path = File.expand_path(file_name, )
      Tempfile.open(file_name) do |f| # Ruby 1.8 Style (not IO.write)
        f << content
        files_array[file_name] = f.path
      end
    end
    cache_gist(gist_id, files_array.keys)
    files_array
  end
  
  def list_gists(user)
    response = api_get_request(USER_URL % user, "Retrieving List of Gists...")
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

  # For Debugging
  def abort_message(message)
    %x{ "$DIALOG" >/dev/null alert --title "Abort Message" --body "Message: #{message}" --button1 OK }
    TextMate.exit_discard
  end

  def abort_no_auth
    %x{ "$DIALOG" >/dev/null alert --title "GitHub authentication error." --body "To setup authentication you should run the following in a terminal:\n\ngit config --global github.user «username»\ngit config --global github.password «password»" --button1 OK }
    TextMate.exit_discard
  end
  
  def abort_no_selection
    %x{ "$DIALOG" >/dev/null alert --title "Nothing Selected." --body "To create a Gist from a selection, you need to select a block of text or code. Note that this new gist will not be cached" --button1 OK }
    TextMate.exit_discard
  end
  
  def abort_no_gist
    %x{ "$DIALOG" >/dev/null alert --title "No known gist for “${TM_DISPLAYNAME}”." --body "Either use “Create Gist” to register “${TM_DISPLAYNAME}” as a new gist, or use “Get Gist…” to retrieve an existing gist." --button1 OK }
    TextMate.exit_discard
  end

  def abort_gist_already_exist
    plist = %x{ "$DIALOG" alert --title "A gist already exist for “${TM_DISPLAYNAME}”." --body "You can use “Update Gist” to update the online version.\n\nIf you want to force create a new gist for this document then you must first remove the existing one from the cache." --button1 OK --button2 "Edit Cache" }
    hash = OSX::PropertyList::load(plist)
    %x{"$TM_SUPPORT_PATH/bin/mate" -tsource.yaml #{e_sh CACHE_FILE_PATH}} if hash['buttonClicked'].to_i == 1
    TextMate.exit_discard
  end
  
  def textmate_get_gist(gist_id)
    files_array = get_gist(gist_id)
    unless files_array.nil?
      # Open em
      files_array.each do |file_name, file_path|
        %x{cat #{e_sh file_path} | "$TM_SUPPORT_PATH/bin/mate" --no-wait -m #{e_sh file_name} -}
      end
    end
  end
  
  def retrieve_gist(params)
    api_get_request(GIST_URL + "/#{params}", "Retrieving Gist Files...")
  end
  
  def extract_content(data, key)
    data["files"][key]["content"]
  end

  def extract_file_name(data, key)
    data["files"][key]["filename"]
    # data["files"].map{|name, content| content['filename'] }.join("\n\n")
  end
  
  def api_get_request(url, message, params = nil, need_auth = false)
    uri = URI(url)
    uri.query = URI.encode_www_form(params) if params
        
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    
    request = Net::HTTP::Get.new(uri.request_uri)
    request.add_field('User-Agent', 'TextMate Gists Bundle')
    request["Content-Type"] = "application/json"
    if need_auth
      abort_no_auth if no_auth?
      user, password = auth()
      if user && password
        request.basic_auth(user, password)
      end
    end

    response = TextMate.call_with_progress(:title => 'Gists Progress', 
      :cancel => lambda { TextMate.exit_discard },
      :message => [message, uri.request_uri].join(" ")) do
        
      http.request(request)
    end
    if response.code.to_i >= 300
      abort_message("Failed: #{response.code}: #{response.body}")
      return nil
    end
    JSON.parse(response.body)
  end
  
  def api_post_request(file_names, message, id = nil, is_private = false)
    url = GIST_URL
    url = "#{url}/#{id}" unless id.nil?
    uri = URI(url)
    # puts uri
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Post.new(uri.request_uri)
    request.add_field('User-Agent', 'TextMate Gists Bundle')
    request.body = JSON.generate(make_data(file_names, id, is_private))
    request["Content-Type"] = "application/json"
    user, password = auth()
    if user && password
      request.basic_auth(user, password)
    end

    response = TextMate.call_with_progress(:title => 'Gists Progress', 
      :cancel => lambda { TextMate.exit_discard },
      :message => message) do
        
      http.request(request)
    end
    # puts response.code
    # puts response.body
    if response.code.to_i >= 300
      abort_message("Failed: #{response.code}: #{response.body}")
      return nil
    end
    JSON.parse(response.body)
  end
  
  def make_data(file_names, id, is_private)
    # abort_message("XXX #{Dir.pwd} #{file_names}")
    file_data = {}
    file_names.each do |file_name|
      if File.basename(file_name) =~ /^xyzzygist/
        file_data[File.basename(file_name).split('-')[0].sub!('xyzzygist', 'selection')] = {:content => IO.read(file_name).to_s }
      else
        file_data[File.basename(file_name)] = {:content => IO.read(file_name).to_s }
      end
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
  
  def get_login
    data = api_get_request(ACCOUNT_URL, "Get login...", nil, true)
    data['login'] unless data.nil?
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
  
  def append_to_cache(key, filename)
    cache = load_cache
    cache[key] << "," + filename
    save_cache(cache)
  end
  
  def to_pasteboard(gist_id)
    return unless RUBY_PLATFORM =~ /darwin/
    text = "#{WEB_URL}/#{gist_id}" 
    IO.popen('pbcopy', 'r+').puts text
  end
    
end
