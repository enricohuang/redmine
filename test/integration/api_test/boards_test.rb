# frozen_string_literal: true

require_relative '../../test_helper'

class Redmine::ApiTest::BoardsTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :boards, :messages, :enabled_modules

  test "GET /projects/:project_id/boards.xml should return boards" do
    get '/projects/ecookbook/boards.xml'

    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'boards[type=array]' do
      assert_select 'board', 2
      assert_select 'board id', :text => '1'
      assert_select 'board name', :text => 'Help'
    end
  end

  test "GET /projects/:project_id/boards.json should return boards" do
    get '/projects/ecookbook/boards.json'

    assert_response :success
    assert_equal 'application/json', response.media_type
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Hash, json
    assert_kind_of Array, json['boards']
    assert_equal 2, json['boards'].size
    board = json['boards'].find { |b| b['id'] == 1 }
    assert_equal 'Help', board['name']
    assert_equal 'Help board', board['description']
  end

  test "GET /projects/:project_id/boards.json should support pagination" do
    get '/projects/ecookbook/boards.json', :params => {:limit => 1, :offset => 0}

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['boards'].size
    assert_equal 2, json['total_count']
    assert_equal 0, json['offset']
    assert_equal 1, json['limit']
  end

  test "GET /boards/:id.xml should return board" do
    get '/projects/ecookbook/boards/1.xml'

    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'board' do
      assert_select 'id', :text => '1'
      assert_select 'name', :text => 'Help'
      assert_select 'description', :text => 'Help board'
      assert_select 'project[id="1"][name="eCookbook"]'
      assert_select 'topics_count', :text => '2'
      assert_select 'messages_count', :text => '6'
    end
  end

  test "GET /boards/:id.json should return board" do
    get '/projects/ecookbook/boards/1.json'

    assert_response :success
    assert_equal 'application/json', response.media_type
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Hash, json
    board = json['board']
    assert_equal 1, board['id']
    assert_equal 'Help', board['name']
    assert_equal 'Help board', board['description']
    assert_equal 1, board['project']['id']
    assert_equal 'eCookbook', board['project']['name']
  end

  test "GET /boards/:id.json should include last_message" do
    get '/projects/ecookbook/boards/1.json'

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    board = json['board']
    assert board['last_message']
    assert_equal 6, board['last_message']['id']
  end

  test "POST /projects/:project_id/boards.xml should create board" do
    assert_difference 'Board.count' do
      post(
        '/projects/ecookbook/boards.xml',
        :params => {:board => {:name => 'API Board', :description => 'Board created via API'}},
        :headers => credentials('admin')
      )
    end

    assert_response :no_content
    board = Board.find_by(:name => 'API Board')
    assert_not_nil board
    assert_equal 'Board created via API', board.description
    assert_equal 1, board.project_id
  end

  test "POST /projects/:project_id/boards.json should create board" do
    assert_difference 'Board.count' do
      post(
        '/projects/ecookbook/boards.json',
        :params => {:board => {:name => 'JSON Board', :description => 'Board created via JSON API'}},
        :headers => credentials('admin')
      )
    end

    assert_response :no_content
    board = Board.find_by(:name => 'JSON Board')
    assert_not_nil board
    assert_equal 'Board created via JSON API', board.description
  end

  test "POST /projects/:project_id/boards.xml with invalid data should return errors" do
    assert_no_difference 'Board.count' do
      post(
        '/projects/ecookbook/boards.xml',
        :params => {:board => {:name => ''}},
        :headers => credentials('admin')
      )
    end

    assert_response :unprocessable_content
    assert_select 'errors error', :text => "Name cannot be blank"
  end

  test "POST /projects/:project_id/boards.json with invalid data should return errors" do
    assert_no_difference 'Board.count' do
      post(
        '/projects/ecookbook/boards.json',
        :params => {:board => {:name => ''}},
        :headers => credentials('admin')
      )
    end

    assert_response :unprocessable_content
    json = ActiveSupport::JSON.decode(response.body)
    assert json['errors'].include?("Name cannot be blank")
  end

  test "PUT /boards/:id.xml should update board" do
    put(
      '/projects/ecookbook/boards/1.xml',
      :params => {:board => {:name => 'Updated Board', :description => 'Updated description'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    board = Board.find(1)
    assert_equal 'Updated Board', board.name
    assert_equal 'Updated description', board.description
  end

  test "PUT /boards/:id.json should update board" do
    put(
      '/projects/ecookbook/boards/1.json',
      :params => {:board => {:name => 'JSON Updated', :description => 'JSON updated description'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    board = Board.find(1)
    assert_equal 'JSON Updated', board.name
  end

  test "PUT /boards/:id.xml with invalid data should return errors" do
    put(
      '/projects/ecookbook/boards/1.xml',
      :params => {:board => {:name => ''}},
      :headers => credentials('admin')
    )

    assert_response :unprocessable_content
    assert_select 'errors error', :text => "Name cannot be blank"
  end

  test "DELETE /boards/:id.xml should delete board" do
    assert_difference 'Board.count', -1 do
      delete '/projects/ecookbook/boards/2.xml', :headers => credentials('admin')
    end

    assert_response :no_content
    assert_nil Board.find_by(:id => 2)
  end

  test "DELETE /boards/:id.json should delete board" do
    assert_difference 'Board.count', -1 do
      delete '/projects/ecookbook/boards/2.json', :headers => credentials('admin')
    end

    assert_response :no_content
    assert_nil Board.find_by(:id => 2)
  end
end
