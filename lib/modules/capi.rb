require 'json'
require 'rest-client'
require 'yaml'

# Local Gems
require_relative './secrets'

module CAPI
  # Canvas API interface.
  class Error < StandardError; end

  if (ENV['ACCESS_TOKEN'] == nil)
    Secrets::source('private/ENV')
  end

  def self.base_url=(base); @base_url = base; end
  def self.base_url; @base_url; end

  def self.headers
    {
      Authorization: "Bearer #{ENV['ACCESS_TOKEN']}"
    }
  end

  def self.get(route, includes = '')
    route += append_includes(includes) if (includes != '')
    route += "#{(includes == '' ? '?' : '&')}per_page=100"
    # puts "get(): includes = \'#{includes}\' #{base_url + route}"
    begin
      response = JSON.parse(RestClient.get(base_url + route, headers))
    rescue => e
      e.response
    end
  end

  def self.put(route, payload, includes = '')
    route += append_includes(includes) if (includes != '')
    # puts "put(): includes = \'#{includes}\' #{base_url + route}"
    begin
      response = JSON.parse(
        RestClient.put(
          base_url + route,
          payload.to_json,
          headers
        )
      )
    rescue => e
      e.response
    end
  end

  def self.assignment(cid, aid, includes = '')
    route = "/v1/courses/#{cid}/assignments/#{aid}"
    get(route, includes)
  end

  def self.submission(cid, aid, uid, includes = '')
    route = "/v1/courses/#{cid}/assignments/#{aid}/submissions/#{uid}"
    get(route, includes)
  end

  def self.submissions(cid, aid, includes = '')
    route = "/v1/courses/#{cid}/assignments/#{aid}/submissions"
    get(route, includes)
  end

  def self.score_submission(cid, aid, uid, scored_submission, includes = '')
    route = "/v1/courses/#{cid}/assignments/#{aid}/submissions/#{uid}"
    put(route, scored_submission, includes)
  end

  # UI helpers

  def self.list_assignments(pat = '', opts = {})
  end

  def self.match_assignment(pat, opts = {})
  end

  def self.list_courses(pat = '', opts = {})
  end

  def self.match_course(pat, opts = {})
  end

  def self.list_sections(pat = '', opts = {})
  end

  def self.match_section(pat, opts = {})
  end

  def self.list_users(pat = '', opts = {})
  end

  def self.match_user(pat, opts = {})
  end

  # Utility methods.

  def self.append_includes(list)
    # XXX: Guard against empty list?
    includes = ''
    list.each do |i|
      includes += ((includes == '') ? '?' : '&') + "include[]=#{i}"
    end
    return includes
  end

  def self.dump(obj)
    puts obj.to_yaml
  end
end
