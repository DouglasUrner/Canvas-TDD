#!/usr/bin/env ruby
require 'bundler/setup'
require 'henkei'
require 'json'
require 'nokogiri'
require 'pry'
require 'yaml'

require_relative 'modules/capi'

CAPI::base_url= 'https://canvas.instructure.com/api'

def breadcrumbs(s, url)
  puts "#{s['user']['name']} (#{s['user']['id']}): #{s['submission_type']} #{s['workflow_state']} #{s['grade_matches_current_assignment']} #{url}"
end

def download_scorer(aid, url)
  puts url
  scorer_name = "score-#{aid}.rb"
  cmd = "curl -s #{url} -o #{scorer_name}"
  # TODO: check return - execute command method.
  # XXX: There is a potential injection attack here since the scorer URL is
  #      inferred from the assignment repository.
  %x( #{cmd} )
  return scorer_name
end

def download_submission(s)
  file_name = s['attachments'][0]['display_name']
  file_name = "#{@opts[:tmp_dir]}/#{file_name}" if (@opts[:tmp_dir])
  url = s['attachments'][0]['url']
  cmd = "curl -s -L \'#{url}\' -o \'#{file_name}\'"
  puts cmd if (@opts[:debug])
  %x( #{cmd} )
  return file_name
end

def extract_repo_url(f)
  locator = '//div[@class="annotation"]/a/@href'
  url = Nokogiri::HTML(Henkei.new(f).html).xpath(locator)
  return url.to_s
end

def get_assignment_id(cid, pat)
  if (pat.match?(/^\d+$/))
    return pat
  else
    # Match assignment using @opts[:assignment] as a regexp. If we get
    # one response use the assignment ID otherwise print a list of
    # assignment that matched the pattern and exit.
    assignment = CAPI::match_assignment(cid, pat)
    case (assignment)
    when 0
      puts "#{$0}: no assignment matches #{pat}"
      exit -1
    when (2..)
      puts "#{$0}: #{assignment} assignments match \'#{pat}\':"
      CAPI::list_assignments(pat).each do |c|
        puts "  #{c['name']}: #{c['id']}"
      end
      exit -1
    else
      puts "Found #{assignment['name']} (#{assignment['id']})" if (@opts[:debug])
      return assignment['id']
    end
  end
end

def get_course_id(pat)
  if (pat.match?(/^\d+$/))
    return pat
  else
    # Match course using @opts[:course] as a regexp. If we get
    # one response use the course ID otherwise print a list of
    # courses that matched the pattern and exit.
    course = CAPI::match_course(pat)
    case (course)
    when 0
      puts "#{$0}: no course matches #{pat}"
      exit -1
    when (2..)
      puts "#{$0}: #{course} courses match \'#{pat}\':"
      CAPI::list_courses(pat).each do |c|
        puts "  #{c['name']}: #{c['id']}"
      end
      exit -1
    else
      puts "Found #{course['name']} (#{course['id']})" if (@opts[:debug])
      return course['id']
    end
  end
end

# Given a Canvas submission object, extract the
# URL of the source repository.
def get_repo_url(s)
  case (s['submission_type'])
  when nil
    # Nothing submitted
    return nil
  when 'online_upload'
    pdf = download_submission(s)
    url = extract_repo_url(pdf)
  when 'online_url'
    url = s['url']
  else
    # XXX: error to stderr or raise an exception
    puts s['submission_type']
  end
  return ( (url.nil?) ? url : url.gsub(/\/tree\/.*$/, '') )
end

# Return the name of the downloaded scoring script - or exit if we fail.
def get_scorer(cid, aid)
  # XXX: need to handle failed requests / bad args.
  response = CAPI::assignment(cid, aid)

  scorer_url = get_scorer_url(response['description'])
  scorer = download_scorer(aid, scorer_url)
end

# Parse the HTML from the assignment description to generate the URL
# of the auto_score module in the source repo on GitHub.
def get_scorer_url(desc)
  host = 'https://raw.githubusercontent.com'
  branch = 'master'
  path = 'assessment/auto_score.rb'

  pages, repo = desc.gsub(/^.*https:\/\//, '').gsub(/\".*$/, '').split('/')
  org = (pages.split('.'))[0]

  return "#{host}/#{org}/#{repo}/#{branch}/#{path}"
end

def get_student_id(pat)
  return @opts[:student]
end

def needs_scoring?(s)
  ((s['workflow_state'] == 'submitted' &&
        s['grade_matches_current_assignment'] != true)) ? true : false
end

def post_score(cid, aid, sid, fb)
  payload = {
    'comment[text_comment]': "#{fb['comments']}",
    'submission[posted_grade]': "#{fb['score']}"
  }
  CAPI::score_submission(cid, aid, sid, payload)
end

def score_assignment(scorer, repo_url)
  if (repo_url.length == 0)
    fb['score'] = 0
    fb['comments'] = 'The link to your repository is missing. '                +
                     'Please correct and resubmit'
  else
    score_cmd = "ruby #{scorer} #{repo_url}"
    puts score_cmd  if (@opts[:debug])
    fb = %x( #{score_cmd} )
  end
  return JSON.parse(fb)
end

def submitted?(s)
  (s['submitted_at'] == nil) ? false : true
end



if (__FILE__ == $0)
  require 'optparse'

  @opts = {
    debug: false,
    tmp_dir: 'tmp',
    verbose: false,
  }

  OptionParser.new do |o|
    o.banner = "Usage: #{$0} [options]"

    o.on('-a ASSIGNMENT') { |v| @opts[:assignment] = v }
    o.on('-c COURSE')     { |v| @opts[:course] = v }
    o.on('-d')            { |v| @opts[:debug] = true }
    o.on('-p')            { |v| @opts[:post_scores] = true }
    o.on('-s STUDENT')    { |v| @opts[:student] = v }
    o.on('-T TMPDIR')     { |v| @opts[:tmp_dir] = v }
    o.on('-v')            { |v| @opts[:verbose] = true }
  end.parse!

  cid = get_course_id(@opts[:course])
  aid = get_assignment_id(cid, @opts[:assignment])
  sid = get_student_id(@opts[:student])

  scorer = get_scorer(cid, aid)

  if (@opts[:student])
    response = CAPI::submission(cid, aid, sid, %w[user])
    url = get_repo_url(response)
    breadcrumbs(response, url)
    if (submitted?(response) && needs_scoring?(response))
      score = score_assignment(scorer, url)
      # binding.pry
      CAPI::dump(score) if (@opts[:verbose])
      if (@opts[:post_scores])
        post_score(cid, aid, sid, score)
      else
      end
    end
  else
    response = CAPI::submissions(cid, aid, %w[user])
    response.each do |s|
      if (submitted?(s) && needs_scoring?(s))
        url = get_repo_url(s)
        breadcrumbs(s, url)
        score = score_assignment(scorer, url)
        post_score(cid, aid, s['user']['id'], score) if (@opts[:post_scores])
      else
        breadcrumbs(s, '') if (@opts[:verbose])
      end
    end
  end
end
