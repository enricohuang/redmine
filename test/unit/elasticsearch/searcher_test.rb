# frozen_string_literal: true

require_relative '../../test_helper'

class ElasticsearchSearcherTest < ActiveSupport::TestCase
  def test_standard_searcher_journal_query_filters_private_notes
    searcher = Elasticsearch::Searcher.allocate
    searcher.instance_variable_set(:@options, {})

    query = searcher.send(:public_journal_notes_query, 'secret')

    assert_equal(
      { term: { :'issue_fields.journals.is_private' => false } },
      query.dig(:nested, :query, :bool, :filter).first
    )
  end

  def test_standard_searcher_custom_field_query_filters_role_restricted_fields
    searcher = Elasticsearch::Searcher.allocate
    searcher.instance_variable_set(:@options, {})

    query = searcher.send(:public_custom_fields_query, 'secret')

    assert_equal(
      { term: { :'custom_fields.visible' => true } },
      query.dig(:nested, :query, :bool, :filter).first
    )
  end

  def test_advanced_searcher_journal_query_filters_private_notes
    searcher = Elasticsearch::AdvancedSearcher.allocate

    query = searcher.send(:public_journal_notes_query, 'secret')

    assert_equal(
      { term: { :'issue_fields.journals.is_private' => false } },
      query.dig(:nested, :query, :bool, :filter).first
    )
  end

  def test_advanced_searcher_custom_field_query_filters_role_restricted_fields
    searcher = Elasticsearch::AdvancedSearcher.allocate

    query = searcher.send(:public_custom_fields_query, 'secret')

    assert_equal(
      { term: { :'custom_fields.visible' => true } },
      query.dig(:nested, :query, :bool, :filter).first
    )
  end
end
