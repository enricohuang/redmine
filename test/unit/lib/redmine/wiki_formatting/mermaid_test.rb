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

require_relative '../../../../test_helper'

class Redmine::WikiFormatting::MermaidTest < ActiveSupport::TestCase
  include ApplicationHelper
  include ActionView::Helpers::SanitizeHelper

  def setup
    @project = Project.find(1)
    User.current = User.find(1)
  end

  # Mermaid code block rendering tests for CommonMark (Markdown)
  def test_mermaid_flowchart_block_renders_with_data_language
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        flowchart LR
          A --> B
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      assert result.include?('flowchart')
    end
  end

  def test_mermaid_sequence_diagram_block
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        sequenceDiagram
          Alice->>John: Hello John
          John-->>Alice: Hi Alice
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      assert result.include?('sequenceDiagram')
    end
  end

  def test_mermaid_class_diagram_block
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        classDiagram
          class Animal {
            +name
            +age
            +makeSound()
          }
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      assert result.include?('classDiagram')
    end
  end

  def test_mermaid_state_diagram_block
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        stateDiagram-v2
          [*] --> Active
          Active --> Inactive
          Inactive --> [*]
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      assert result.include?('stateDiagram')
    end
  end

  def test_mermaid_pie_chart_block
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        pie title Pets
          "Dogs" : 386
          "Cats" : 85
          "Rats" : 15
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      assert result.include?('pie')
    end
  end

  def test_mermaid_gantt_chart_block
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        gantt
          title A Gantt Chart
          dateFormat  YYYY-MM-DD
          section Section
          Task1 :a1, 2024-01-01, 30d
          Task2 :after a1, 20d
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      assert result.include?('gantt')
    end
  end

  def test_mermaid_er_diagram_block
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        erDiagram
          CUSTOMER ||--o{ ORDER : places
          ORDER ||--|{ LINE-ITEM : contains
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      assert result.include?('erDiagram')
    end
  end

  def test_mermaid_git_graph_block
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        gitGraph
          commit
          branch develop
          checkout develop
          commit
          checkout main
          merge develop
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      assert result.include?('gitGraph')
    end
  end

  # Test that mermaid blocks are wrapped in code tags
  def test_mermaid_block_structure
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        flowchart LR
          A --> B
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      # Should be wrapped in pre > code
      assert result.include?('<pre')
      assert result.include?('<code')
    end
  end

  # Test mixing mermaid with regular markdown
  def test_mermaid_with_surrounding_content
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        Some text before the diagram.

        ```mermaid
        flowchart LR
          A --> B
        ```

        Some text after the diagram.

        - List item 1
        - List item 2
      MARKDOWN

      result = textilizable(text, project: @project)
      # Verify all content types render together properly
      assert result.include?('Some text before'), "Should include text before diagram"
      assert result.include?('data-language="mermaid"'), "Should include mermaid block"
      assert result.include?('Some text after'), "Should include text after diagram"
      assert result.include?('<li>'), "Should include list items"
    end
  end

  # Test multiple mermaid blocks in same content
  def test_multiple_mermaid_blocks
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        flowchart LR
          A --> B
        ```

        Some text.

        ```mermaid
        sequenceDiagram
          Alice->>Bob: Hi
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      # Should have two mermaid code blocks
      assert_equal 2, result.scan('data-language="mermaid"').count
    end
  end

  # Test that non-mermaid code blocks are not affected
  def test_non_mermaid_code_blocks_unaffected
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```ruby
        def hello
          puts "Hello"
        end
        ```

        ```mermaid
        flowchart LR
          A --> B
        ```

        ```javascript
        console.log("test");
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      # Ruby and JavaScript should have their own data-language
      assert result.include?('data-language="ruby"')
      assert result.include?('data-language="mermaid"')
      assert result.include?('data-language="javascript"')
    end
  end

  # Textile tests
  def test_mermaid_in_textile_pre_block
    with_settings text_formatting: 'textile' do
      text = <<~TEXTILE
        <pre><code class="mermaid">
        flowchart LR
          A --> B
        </code></pre>
      TEXTILE

      result = textilizable(text, project: @project)
      assert result.include?('flowchart')
    end
  end

  # Edge cases
  def test_empty_mermaid_block
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        ```
      MARKDOWN

      # Should not raise error
      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
    end
  end

  def test_mermaid_block_with_special_characters
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        flowchart LR
          A["Special <chars> & 'quotes'"] --> B
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      # Content should be preserved (possibly escaped)
      assert result.include?('Special')
    end
  end

  def test_mermaid_block_with_unicode
    with_settings text_formatting: 'common_mark' do
      text = <<~MARKDOWN
        ```mermaid
        flowchart LR
          A["日本語"] --> B["中文"]
        ```
      MARKDOWN

      result = textilizable(text, project: @project)
      assert result.include?('data-language="mermaid"')
      assert result.include?('日本語')
      assert result.include?('中文')
    end
  end
end
