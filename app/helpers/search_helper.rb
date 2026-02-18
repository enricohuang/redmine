# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

module SearchHelper
  def highlight_tokens(text, tokens)
    return text unless text && tokens && !tokens.empty?

    re_tokens = tokens.collect {|t| Regexp.escape(t)}
    regexp = Regexp.new "(#{re_tokens.join('|')})", Regexp::IGNORECASE
    result = +''
    text.split(regexp).each_with_index do |words, i|
      if result.length > 1200
        # maximum length of the preview reached
        result << '...'
        break
      end
      if i.even?
        result << h(words.length > 100 ? "#{words.slice(0..44)} ... #{words.slice(-45..-1)}" : words)
      else
        t = (tokens.index(words.downcase) || 0) % 4
        result << content_tag('span', h(words), :class => "highlight token-#{t}")
      end
    end
    result.html_safe
  end

  def type_label(t)
    l("label_#{t.singularize}_plural", :default => t.to_s.humanize)
  end

  def project_select_tag
    options = [[l(:label_project_all), 'all']]
    options << [l(:label_my_projects), 'my_projects'] unless User.current.memberships.empty?
    options << [l(:label_my_bookmarks), 'bookmarks'] unless User.current.bookmarked_project_ids.empty?
    options << [l(:label_and_its_subprojects, @project.name), 'subprojects'] unless @project.nil? || @project.descendants.active.empty?
    options << [@project.name, ''] unless @project.nil?
    label_tag("scope", l(:description_project_scope), :class => "hidden-for-sighted") +
    select_tag('scope', options_for_select(options, params[:scope].to_s)) if options.size > 1
  end

  def render_results_by_type(results_by_type)
    links = []
    # Sorts types by results count
    results_by_type.keys.sort_by {|k| results_by_type[k]}.reverse_each do |t|
      c = results_by_type[t]
      next if c == 0

      text = "#{type_label(t)} (#{c})"
      links << link_to(h(text), :q => params[:q], :titles_only => params[:titles_only],
                       :all_words => params[:all_words], :scope => params[:scope], t => 1)
    end
    ('<ul>'.html_safe +
        links.map {|link| content_tag('li', link)}.join(' ').html_safe +
        '</ul>'.html_safe) unless links.empty?
  end

  def issues_filter_path(question, options)
    projects_scope = options[:projects_scope]
    titles_only = options[:titles_only]
    all_words = options[:all_words]
    open_issues = options[:open_issues]

    field_to_search = titles_only ? 'subject' : 'any_searchable'
    params = {
      :set_filter => 1,
      :f => ['status_id', field_to_search],
      :op => {
        'status_id' => open_issues ? 'o' : '*',
        field_to_search => all_words ? '~' : '*~'
      },
      :v => {field_to_search => [question]},
      :sort => 'updated_on:desc'
    }

    case projects_scope
    when 'all'
      # nothing to do
    when 'my_projects'
      params[:f] << 'project_id'
      params[:op]['project_id'] = '='
      params[:v]['project_id'] = ['mine']
    when 'bookmarks'
      params[:f] << 'project_id'
      params[:op]['project_id'] = '='
      params[:v]['project_id'] = ['bookmarks']
    when 'subprojects'
      params[:f] << 'subproject_id'
      params[:op]['subproject_id'] = '*'
      params[:project_id] = @project.id
    else
      if @project
        # current project only
        params[:f] << 'subproject_id'
        params[:op]['subproject_id'] = '!*'
        params[:project_id] = @project.id
      end
      # else all projects
    end

    issues_path(params)
  end

  # ============================================
  # New helpers for modern search UI
  # ============================================

  # Relative timestamp with tooltip showing full date
  def time_ago_tag(datetime)
    return '' unless datetime

    content_tag(:span, time_ago_in_words(datetime) + ' ago',
                title: format_time(datetime),
                class: 'search-relative-time')
  end

  # Type badge with icon and color
  def search_type_badge(result)
    event_type = result.event_type.to_s.gsub('-closed', '')

    # For issues, use tracker name if available
    if result.is_a?(Issue) && result.tracker
      tracker_class = "tracker-#{result.tracker.name.to_s.parameterize}"
      label = result.tracker.name
    else
      tracker_class = ''
      label = type_label(event_type.pluralize)
    end

    content_tag(:span, label,
                class: "search-type-badge search-type-#{event_type} #{tracker_class}".strip)
  end

  # Status pill for issues
  def issue_status_pill(issue)
    return unless issue.is_a?(Issue) && issue.status

    status_class = if issue.closed?
                     'closed'
                   else
                     issue.status.name.to_s.parameterize
                   end

    content_tag(:span, issue.status.name,
                class: "search-status-pill status-#{status_class}")
  end

  # Attachment indicator with count
  def attachment_indicator(result)
    return unless result.respond_to?(:attachments)

    count = result.attachments.count
    return if count == 0

    content_tag(:span, class: 'search-attachment-indicator') do
      sprite_icon('attachment') + content_tag(:span, count.to_s)
    end
  end

  # Labels for issues (if labels plugin is active)
  def issue_labels_tag(issue)
    return unless issue.is_a?(Issue) && issue.respond_to?(:labels) && issue.labels.any?

    content_tag(:span, class: 'search-result-labels') do
      issue.labels.map do |label|
        bg_color = label.respond_to?(:color) ? label.color : '#666'
        content_tag(:span, label.name,
                    class: 'search-label',
                    style: "background-color: #{bg_color}")
      end.join.html_safe
    end
  end

  # Result meta line (project, author, date, attachments)
  def search_result_meta(result)
    parts = []

    # Project
    if result.respond_to?(:project) && result.project && @project != result.project
      parts << content_tag(:span, class: 'search-meta-project') do
        link_to(result.project.name, project_path(result.project))
      end
    end

    # Author
    if result.respond_to?(:author) && result.author
      parts << content_tag(:span, result.author.name, class: 'search-meta-author')
    end

    # Assignee for issues
    if result.is_a?(Issue) && result.assigned_to
      parts << content_tag(:span, class: 'search-meta-assignee') do
        l(:field_assigned_to) + ': ' + result.assigned_to.name
      end
    end

    # Attachment count
    if result.respond_to?(:attachments) && result.attachments.count > 0
      parts << attachment_indicator(result)
    end

    # Relative time
    parts << time_ago_tag(result.event_datetime)

    safe_join(parts.compact)
  end

  # Find attachment that matched search tokens
  def find_matched_attachment(result, tokens)
    return nil unless result.respond_to?(:attachments) && tokens.present?

    result.attachments.each do |att|
      # Check filename
      if tokens.any? { |t| att.filename.to_s.downcase.include?(t.downcase) }
        return { filename: att.filename, excerpt: nil }
      end

      # Check fulltext content if available
      if att.respond_to?(:fulltext_content) && att.fulltext_content&.content.present?
        content = att.fulltext_content.content
        if tokens.any? { |t| content.downcase.include?(t.downcase) }
          # Extract excerpt around the match
          excerpt = extract_excerpt(content, tokens.first, 60)
          return { filename: att.filename, excerpt: excerpt }
        end
      end
    end

    nil
  end

  # Extract excerpt around a search term
  def extract_excerpt(text, term, radius = 60)
    return nil unless text && term

    index = text.downcase.index(term.downcase)
    return nil unless index

    start_pos = [0, index - radius].max
    end_pos = [text.length, index + term.length + radius].min

    excerpt = text[start_pos...end_pos]
    excerpt = '...' + excerpt if start_pos > 0
    excerpt = excerpt + '...' if end_pos < text.length

    excerpt
  end
end
