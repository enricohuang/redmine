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

    respond_to do |format|
      format.html
      format.json do
        render json: {
          query: @question,
          total_count: @result_count.to_i,
          offset: @offset,
          limit: @limit,
          results: (@results || []).map do |r|
            project = Project.find_by(id: r[:project_id])
            {
              type: r[:type],
              id: r[:id],
              title: r[:title],
              content: r[:content],
              score: r[:score],
              project_id: r[:project_id],
              project_name: project&.name,
              project_identifier: project&.identifier,
              created_on: r[:created_on],
              updated_on: r[:updated_on]
            }
          end,
          aggregations: @aggregations || {}
        }
      end
    end
  end

  private

  def require_elasticsearch
    unless defined?(::RedmineElasticsearch) && ::RedmineElasticsearch.available?
      respond_to do |format|
        format.html do
          flash[:error] = l(:error_elasticsearch_not_available)
          redirect_to search_path
        end
        format.json { render json: { error: 'elasticsearch_not_available' }, status: :service_unavailable }
      end
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
