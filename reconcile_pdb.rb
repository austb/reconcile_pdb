require 'httparty'

project = 'PDB'.freeze
version = '6.3.1'.freeze
prev_version = '6.3.0'.freeze
fix_version = "#{project} #{version}".freeze
branch = /^(\d+\.\d+\.)\d+$/.match(version).to_a[1] + "x"
branch = "master"

puppetdb_repo = "../puppetdb".freeze
pe_puppetdb_extensions_repo = "../pe-puppetdb-extensions".freeze
git_log = "git log --oneline --no-merges --no-decorate #{prev_version}..HEAD".freeze

api_url = 'https://tickets.puppetlabs.com/rest/api/2'.freeze
jql_search = "#{api_url}/search".freeze

url = "#{jql_search}?jql=fixVersion='#{fix_version}'"
response = HTTParty.get(url)
json = response.parsed_response

if json['maxResults'] <= json['total']
  url = "#{jql_search}?maxResults=#{json['total']}&jql=fixVersion='#{fix_version}'"
  response = HTTParty.get(url)
  json = response.parsed_response
end

jira_issues = []
require 'pry'
json['issues'].each do |issue|
  # puts issue['key']
  jira_issues.push({
    id: issue['id'],
    ticket: issue['key'],
    api_url: issue['self']
  });
end

def construct_git_data(output, repo)
  git_data = {}
  output.each_line do |line|
    commit, message = line.split(" ", 2)
    _, pdb_ref = /^\((PDB-\d+)\)/.match(message).to_a

    if pdb_ref
      if git_data.include?(pdb_ref)
        git_data[pdb_ref][:commits].push(commit)
      else
        git_data[pdb_ref] = {
          commits: [commit],
        }
      end
    else
      # Allow (doc) (docs) (maint) case-insensitive
      doc_regex = /^\(docs?\)/i
      maint_regex = /^\(maint\)/i
      i18n_regex = /^\(i18n\)/i
      puts "INVESTIGATE! #{repo} #{line}" unless doc_regex =~ message || maint_regex =~ message || i18n_regex =~ message
    end
  end

  git_data
end

out = `cd #{puppetdb_repo}; #{git_log}`
pdb_git_data = construct_git_data(out, 'puppetdb')

out = `cd #{pe_puppetdb_extensions_repo}; #{git_log}`
pe_git_data = construct_git_data(out, 'pe-puppetdb-extensions')

jira_issues.each do |issue|
  ticket = issue[:ticket]
  unless pdb_git_data.include?(ticket) || pe_git_data.include?(ticket)
    puts "#{ticket} exists in JIRA with fixVersion '#{fix_version}', but there is no corresponding git commit"
  end
end

def fix_version_na(ticket)
end

def find_jira_match(jql_search, ticket, git_data, jira_issues, fix_version, repo)
  jira_match = jira_issues.any? do |issue|
    ticket == issue[:ticket]
  end

  url = "#{jql_search}?maxResults=1&jql=key=#{ticket} AND fixVersion='PDB n/a'"
  response = HTTParty.get(url)
  json = response.parsed_response

  if !jira_match and json['issues'].empty?
    puts "#{ticket} has a git commit(s) #{git_data[:commits]} in #{repo}, but its JIRA ticket does not have fixVersion '#{fix_version}'"
  end
end

pdb_git_data.each do |ticket, data|
  find_jira_match(jql_search, ticket, data, jira_issues, fix_version, 'puppetdb')
end

pe_git_data.each do |ticket, data|
  find_jira_match(jql_search, ticket, data, jira_issues, fix_version, 'pe-puppetdb-exntesions')
end



