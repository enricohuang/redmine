# frozen_string_literal: true

require_relative '../../test_helper'

class Redmine::ApiTest::MessagesTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :boards, :messages, :enabled_modules

  test "GET /boards/:board_id/messages.xml should return messages" do
    get '/boards/1/messages.xml', :headers => credentials('jsmith')

    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'messages[type=array]' do
      assert_select 'message', 2  # 2 topics in board 1
      assert_select 'message id', :text => '1'
      assert_select 'message subject', :text => 'First post'
    end
  end

  test "GET /boards/:board_id/messages.json should return messages" do
    get '/boards/1/messages.json', :headers => credentials('jsmith')

    assert_response :success
    assert_equal 'application/json', response.media_type
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Hash, json
    assert_kind_of Array, json['messages']
    assert_equal 2, json['messages'].size
    message = json['messages'].find { |m| m['id'] == 1 }
    assert_equal 'First post', message['subject']
    assert_equal 2, message['replies_count']
  end

  test "GET /boards/:board_id/messages.json should support pagination" do
    get '/boards/1/messages.json', :params => {:limit => 1}, :headers => credentials('jsmith')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['messages'].size
    assert_equal 2, json['total_count']
  end

  test "GET /messages/:id.xml should return message" do
    get '/messages/1.xml', :headers => credentials('jsmith')

    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'message' do
      assert_select 'id', :text => '1'
      assert_select 'subject', :text => 'First post'
      assert_select 'board[id="1"][name="Help"]'
      assert_select 'author[id="1"][name="Redmine Admin"]'
      assert_select 'replies_count', :text => '2'
    end
  end

  test "GET /messages/:id.json should return message" do
    get '/messages/1.json', :headers => credentials('jsmith')

    assert_response :success
    assert_equal 'application/json', response.media_type
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Hash, json
    message = json['message']
    assert_equal 1, message['id']
    assert_equal 'First post', message['subject']
    assert_equal 1, message['board']['id']
  end

  test "GET /messages/:id.json with include=replies should return replies" do
    get '/messages/1.json', :params => {:include => 'replies'}, :headers => credentials('jsmith')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    message = json['message']
    assert message['replies']
    assert_equal 2, message['replies'].size
    reply = message['replies'].find { |r| r['id'] == 2 }
    assert_equal 'First reply', reply['subject']
  end

  test "POST /boards/:board_id/messages.xml should create message" do
    assert_difference 'Message.count' do
      post(
        '/boards/1/messages.xml',
        :params => {:message => {:subject => 'API Topic', :content => 'Topic created via API'}},
        :headers => credentials('jsmith')
      )
    end

    assert_response :no_content
    message = Message.find_by(:subject => 'API Topic')
    assert_not_nil message
    assert_equal 'Topic created via API', message.content
    assert_equal 1, message.board_id
    assert_nil message.parent_id
  end

  test "POST /boards/:board_id/messages.json should create message" do
    assert_difference 'Message.count' do
      post(
        '/boards/1/messages.json',
        :params => {:message => {:subject => 'JSON Topic', :content => 'Topic created via JSON API'}},
        :headers => credentials('jsmith')
      )
    end

    assert_response :no_content
    message = Message.find_by(:subject => 'JSON Topic')
    assert_not_nil message
    assert_equal 'Topic created via JSON API', message.content
  end

  test "POST /boards/:board_id/messages.xml with invalid data should return errors" do
    assert_no_difference 'Message.count' do
      post(
        '/boards/1/messages.xml',
        :params => {:message => {:subject => '', :content => ''}},
        :headers => credentials('jsmith')
      )
    end

    assert_response :unprocessable_content
    assert_select 'errors error', :text => "Subject cannot be blank"
  end

  test "POST /messages/:id/replies.json should create reply" do
    assert_difference 'Message.count' do
      post(
        '/messages/1/replies.json',
        :params => {:message => {:subject => 'API Reply', :content => 'Reply via API'}},
        :headers => credentials('jsmith')
      )
    end

    assert_response :no_content
    reply = Message.find_by(:subject => 'API Reply')
    assert_not_nil reply
    assert_equal 1, reply.parent_id
    assert_equal 'Reply via API', reply.content
  end

  test "PUT /messages/:id.xml should update message" do
    put(
      '/messages/1.xml',
      :params => {:message => {:subject => 'Updated Subject', :content => 'Updated content'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    message = Message.find(1)
    assert_equal 'Updated Subject', message.subject
    assert_equal 'Updated content', message.content
  end

  test "PUT /messages/:id.json should update message" do
    put(
      '/messages/1.json',
      :params => {:message => {:subject => 'JSON Updated'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    message = Message.find(1)
    assert_equal 'JSON Updated', message.subject
  end

  test "PUT /messages/:id.xml with invalid data should return errors" do
    put(
      '/messages/1.xml',
      :params => {:message => {:subject => ''}},
      :headers => credentials('admin')
    )

    assert_response :unprocessable_content
    assert_select 'errors error', :text => "Subject cannot be blank"
  end

  test "DELETE /messages/:id.xml should delete message" do
    # Use a reply message so we don't delete a topic with children
    assert_difference 'Message.count', -1 do
      delete '/messages/2.xml', :headers => credentials('admin')
    end

    assert_response :no_content
    assert_nil Message.find_by(:id => 2)
  end

  test "DELETE /messages/:id.json should delete message" do
    assert_difference 'Message.count', -1 do
      delete '/messages/3.json', :headers => credentials('admin')
    end

    assert_response :no_content
    assert_nil Message.find_by(:id => 3)
  end
end
