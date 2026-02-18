# frozen_string_literal: true

module Elasticsearch
  # Builds Elasticsearch permission filters based on user access rights.
  # Implements the hybrid approach: ES handles coarse filtering, Ruby handles edge cases.
  class PermissionFilter
    def initialize(user)
      @user = user
    end

    # Build permission filter for specified document types
    def build(document_types = nil)
      types = Array(document_types || all_types)

      {
        bool: {
          should: types.filter_map { |type| filter_for_type(type) },
          minimum_should_match: 1
        }
      }
    end

    private

    def all_types
      %w[issue wiki_page news message changeset document project]
    end

    def filter_for_type(type)
      case type.to_s
      when 'issue' then issue_filter
      when 'wiki_page' then wiki_page_filter
      when 'news' then news_filter
      when 'message' then message_filter
      when 'changeset' then changeset_filter
      when 'document' then document_filter
      when 'project' then project_filter
      end
    end

    # Issue filter: handles private issues, role-based visibility
    def issue_filter
      return nil unless @user.allowed_to?(:view_issues, nil, global: true)

      project_ids = projects_with_permission(:view_issues)
      return nil if project_ids.empty? && !@user.admin?

      filters = []

      # Admin can see all issues
      if @user.admin?
        filters << { term: { type: 'issue' } }
      else
        # Non-private issues in permitted projects
        filters << {
          bool: {
            must: [
              { term: { type: 'issue' } },
              { term: { 'issue_fields.is_private': false } },
              { terms: { project_id: project_ids } }
            ]
          }
        }

        # Private issues where user is author
        filters << {
          bool: {
            must: [
              { term: { type: 'issue' } },
              { term: { 'issue_fields.is_private': true } },
              { term: { 'issue_fields.author_id': @user.id } }
            ]
          }
        }

        # Private issues where user is assignee
        filters << {
          bool: {
            must: [
              { term: { type: 'issue' } },
              { term: { 'issue_fields.is_private': true } },
              { term: { 'issue_fields.assigned_to_id': @user.id } }
            ]
          }
        }

        # Private issues in projects where user has view_private_issues
        private_project_ids = projects_with_permission(:view_private_issues)
        if private_project_ids.any?
          filters << {
            bool: {
              must: [
                { term: { type: 'issue' } },
                { term: { 'issue_fields.is_private': true } },
                { terms: { project_id: private_project_ids } }
              ]
            }
          }
        end
      end

      { bool: { should: filters, minimum_should_match: 1 } }
    end

    # Wiki page filter
    def wiki_page_filter
      return nil unless @user.allowed_to?(:view_wiki_pages, nil, global: true)

      project_ids = projects_with_permission(:view_wiki_pages)
      return nil if project_ids.empty? && !@user.admin?

      if @user.admin?
        { term: { type: 'wiki_page' } }
      else
        {
          bool: {
            must: [
              { term: { type: 'wiki_page' } },
              { terms: { project_id: project_ids } }
            ]
          }
        }
      end
    end

    # News filter
    def news_filter
      return nil unless @user.allowed_to?(:view_news, nil, global: true)

      project_ids = projects_with_permission(:view_news)
      return nil if project_ids.empty? && !@user.admin?

      if @user.admin?
        { term: { type: 'news' } }
      else
        public_filter = {
          bool: {
            must: [
              { term: { type: 'news' } },
              { term: { project_is_public: true } }
            ]
          }
        }

        member_filter = {
          bool: {
            must: [
              { term: { type: 'news' } },
              { terms: { project_id: project_ids } }
            ]
          }
        }

        { bool: { should: [public_filter, member_filter], minimum_should_match: 1 } }
      end
    end

    # Message/forum filter
    def message_filter
      return nil unless @user.allowed_to?(:view_messages, nil, global: true)

      project_ids = projects_with_permission(:view_messages)
      return nil if project_ids.empty? && !@user.admin?

      if @user.admin?
        { term: { type: 'message' } }
      else
        {
          bool: {
            must: [
              { term: { type: 'message' } },
              { terms: { project_id: project_ids } }
            ]
          }
        }
      end
    end

    # Changeset filter
    def changeset_filter
      return nil unless @user.allowed_to?(:view_changesets, nil, global: true)

      project_ids = projects_with_permission(:view_changesets)
      return nil if project_ids.empty? && !@user.admin?

      if @user.admin?
        { term: { type: 'changeset' } }
      else
        {
          bool: {
            must: [
              { term: { type: 'changeset' } },
              { terms: { project_id: project_ids } }
            ]
          }
        }
      end
    end

    # Document filter
    def document_filter
      return nil unless @user.allowed_to?(:view_documents, nil, global: true)

      project_ids = projects_with_permission(:view_documents)
      return nil if project_ids.empty? && !@user.admin?

      if @user.admin?
        { term: { type: 'document' } }
      else
        {
          bool: {
            must: [
              { term: { type: 'document' } },
              { terms: { project_id: project_ids } }
            ]
          }
        }
      end
    end

    # Project filter - public projects or member projects
    def project_filter
      filters = []

      # Public projects
      filters << {
        bool: {
          must: [
            { term: { type: 'project' } },
            { term: { project_is_public: true } },
            { term: { status: Project::STATUS_ACTIVE } }
          ]
        }
      }

      # Member projects (including private)
      member_project_ids = @user.memberships.map(&:project_id)
      if member_project_ids.any?
        filters << {
          bool: {
            must: [
              { term: { type: 'project' } },
              { terms: { project_id: member_project_ids } },
              { term: { status: Project::STATUS_ACTIVE } }
            ]
          }
        }
      end

      # Admin sees all
      if @user.admin?
        filters << { term: { type: 'project' } }
      end

      { bool: { should: filters, minimum_should_match: 1 } }
    end

    # Get project IDs where user has the specified permission
    def projects_with_permission(permission)
      @permission_cache ||= {}
      @permission_cache[permission] ||= if @user.admin?
                                          Project.active.pluck(:id)
                                        else
                                          Project.where(
                                            Project.allowed_to_condition(@user, permission)
                                          ).pluck(:id)
                                        end
    end
  end
end
