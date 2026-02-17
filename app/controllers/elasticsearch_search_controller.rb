# frozen_string_literal: true

# Controller for advanced Elasticsearch search functionality.
# Provides more options and flexibility than the standard search.
class ElasticsearchSearchController < ApplicationController
  before_action :require_elasticsearch
  before_action :find_optional_project_by_id

  helper :sort
  include SortHelper

  def index
    @question = params[:q]&.strip || ""
    @search_in = params[:search_in] || 'all' # all, title, content
    @types = params[:types] || []
    @types = available_types if @types.empty?
    @project_ids = params[:project_ids] || []
    @date_from = params[:date_from].presence
    @date_to = params[:date_to].presence
    @sort_by = params[:sort_by] || 'relevance' # relevance, date_desc, date_asc
    @include_closed = params[:include_closed] != '0'

    @limit = per_page_option
    @offset = params[:page].present? ? (params[:page].to_i - 1) * @limit : 0

    if @question.present?
      perform_search
    end

    @available_projects = User.current.projects.active.order(:name)
  end

  private

  def require_elasticsearch
    unless defined?(::RedmineElasticsearch) && ::RedmineElasticsearch.available?
      flash[:error] = l(:error_elasticsearch_not_available)
      redirect_to search_path
    end
  end

  def available_types
    %w[issue wiki_page news message document changeset project]
  end

  def perform_search
    searcher = Elasticsearch::AdvancedSearcher.new(
      User.current,
      search_options
    )

    @results = searcher.search(@question)
    @result_count = searcher.total_count
    @aggregations = searcher.aggregations
    @result_pages = Paginator.new(@result_count, @limit, params[:page])
  end

  def search_options
    {
      types: @types,
      project_ids: @project_ids.reject(&:blank?).map(&:to_i),
      project: @project,
      search_in: @search_in,
      date_from: @date_from,
      date_to: @date_to,
      sort_by: @sort_by,
      include_closed: @include_closed,
      offset: @offset,
      limit: @limit
    }
  end
end
