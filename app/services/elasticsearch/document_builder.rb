# frozen_string_literal: true

module Elasticsearch
  # Builds Elasticsearch documents from Redmine model records.
  # Each document includes permission-relevant metadata for filtering.
  class DocumentBuilder
    class << self
      def build(record)
        case record
        when Issue
          build_issue(record)
        when WikiPage
          build_wiki_page(record)
        when News
          build_news(record)
        when Message
          build_message(record)
        when Changeset
          build_changeset(record)
        when Document
          build_document(record)
        when Project
          build_project(record)
        else
          raise ArgumentError, "Unsupported record type: #{record.class}"
        end
      end

      def document_id(record)
        "#{record.class.name.underscore}_#{record.id}"
      end

      private

      def build_issue(issue)
        {
          id: issue.id,
          type: 'issue',
          project_id: issue.project_id,
          project_is_public: issue.project.is_public?,
          created_on: issue.created_on&.iso8601,
          updated_on: issue.updated_on&.iso8601,
          title: issue.subject,
          content: issue.description,
          issue_fields: {
            is_private: issue.is_private?,
            author_id: issue.author_id,
            assigned_to_id: issue.assigned_to_id,
            tracker_id: issue.tracker_id,
            status_id: issue.status_id,
            status_is_closed: issue.status&.is_closed?,
            priority_id: issue.priority_id,
            journals: build_journals(issue)
          },
          custom_fields: build_custom_fields(issue),
          attachments: build_attachments(issue)
        }
      end

      def build_wiki_page(wiki_page)
        project = wiki_page.wiki&.project
        {
          id: wiki_page.id,
          type: 'wiki_page',
          project_id: project&.id,
          project_is_public: project&.is_public?,
          created_on: wiki_page.created_on&.iso8601,
          updated_on: wiki_page.updated_on&.iso8601,
          title: wiki_page.title,
          content: wiki_page.content&.text,
          attachments: build_attachments(wiki_page)
        }
      end

      def build_news(news)
        {
          id: news.id,
          type: 'news',
          project_id: news.project_id,
          project_is_public: news.project&.is_public?,
          created_on: news.created_on&.iso8601,
          updated_on: nil,
          title: news.title,
          content: [news.summary, news.description].compact.join("\n"),
          author_id: news.author_id
        }
      end

      def build_message(message)
        project = message.board&.project
        {
          id: message.id,
          type: 'message',
          project_id: project&.id,
          project_is_public: project&.is_public?,
          created_on: message.created_on&.iso8601,
          updated_on: message.updated_on&.iso8601,
          title: message.subject,
          content: message.content,
          author_id: message.author_id,
          board_id: message.board_id,
          parent_id: message.parent_id
        }
      end

      def build_changeset(changeset)
        project = changeset.repository&.project
        {
          id: changeset.id,
          type: 'changeset',
          project_id: project&.id,
          project_is_public: project&.is_public?,
          created_on: changeset.committed_on&.iso8601,
          updated_on: nil,
          title: changeset.revision,
          content: changeset.comments,
          author_id: changeset.user_id,
          repository_id: changeset.repository_id
        }
      end

      def build_document(document)
        {
          id: document.id,
          type: 'document',
          project_id: document.project_id,
          project_is_public: document.project&.is_public?,
          created_on: document.created_on&.iso8601,
          updated_on: nil,
          title: document.title,
          content: document.description,
          category_id: document.category_id,
          attachments: build_attachments(document)
        }
      end

      def build_project(project)
        {
          id: project.id,
          type: 'project',
          project_id: project.id,
          project_is_public: project.is_public?,
          created_on: project.created_on&.iso8601,
          updated_on: project.updated_on&.iso8601,
          title: project.name,
          content: [project.identifier, project.description].compact.join("\n"),
          status: project.status
        }
      end

      def build_journals(issue)
        issue.journals.map do |journal|
          next if journal.notes.blank?

          {
            id: journal.id,
            notes: journal.notes,
            is_private: journal.private_notes?,
            user_id: journal.user_id,
            created_on: journal.created_on&.iso8601
          }
        end.compact
      end

      def build_custom_fields(record)
        return [] unless record.respond_to?(:custom_field_values)

        record.custom_field_values.map do |cfv|
          next if cfv.value.blank?
          next unless cfv.custom_field&.searchable?

          {
            id: cfv.custom_field_id,
            name: cfv.custom_field.name,
            value: cfv.value.is_a?(Array) ? cfv.value.join(' ') : cfv.value.to_s
          }
        end.compact
      end

      def build_attachments(record)
        return [] unless record.respond_to?(:attachments)

        record.attachments.map do |attachment|
          {
            id: attachment.id,
            filename: attachment.filename,
            description: attachment.description
          }
        end
      end
    end
  end
end
