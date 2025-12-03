require 'fastlane/action'
require_relative '../helper/slack_bot_helper'

module Fastlane
  module Actions
    module SharedValues
      FILE_UPLOAD_TO_SLACK_RESULT = :FILE_UPLOAD_TO_SLACK_RESULT
    end

    class FileUploadToSlackAction < Action
      def self.run(params)
        file_path = params[:file_path]

        if params[:file_name].to_s.empty?
          file_name = File.basename(file_path, ".*") # if file_path = "/path/file_name.jpeg" then will return "file_name"
        else
          file_name = params[:file_name]
        end

        if params[:file_type].to_s.empty?
          file_type = File.extname(file_path)[1..-1] # if file_path = "/path/file_name.jpeg" then will return "jpeg"
        else
          file_type = params[:file_type]
        end

        begin
          require 'faraday'

          upload_filename = self.determine_upload_filename(params, file_path)

          get_url_api = "https://slack.com/api/files.getUploadURLExternal"
          conn_get = Faraday.new(url: get_url_api) do |faraday|
            faraday.request :url_encoded
            faraday.adapter :net_http
          end

          response_get = conn_get.post do |req|
            req.headers['Authorization'] = "Bearer #{params[:api_token]}"
            req.body = {
              filename: upload_filename,
              length: File.size(file_path)
            }
          end

          json_get = self.parse_json(response_get.body) || {}
          unless json_get['ok'] && json_get['upload_url'] && json_get['file_id']
            UI.error("Failed to get upload URL from Slack: #{json_get.inspect}")
            return nil
          end

          upload_url = json_get['upload_url']
          file_id = json_get['file_id']

          upload_conn = Faraday.new do |faraday|
            faraday.request :multipart
            faraday.request :url_encoded
            faraday.adapter :net_http
          end

          upload_response = upload_conn.post(upload_url) do |req|
            req.headers['Content-Type'] = 'application/octet-stream'
            req.body = File.open(file_path, 'rb') { |f| f.read }
          end

          unless upload_response.status == 200
            UI.error("File upload to Slack upload_url failed with status #{upload_response.status}")
            return nil
          end

          complete_api = "https://slack.com/api/files.completeUploadExternal"
          conn_complete = Faraday.new(url: complete_api) do |faraday|
            faraday.request :url_encoded
            faraday.adapter :net_http
          end

          files_param = [{ id: file_id }]
          files_param[0][:title] = params[:title] unless params[:title].nil?

          payload_complete = {
            files: files_param.to_json
          }

          payload_complete[:channels] = params[:channels] unless params[:channels].nil?
          payload_complete[:initial_comment] = params[:initial_comment] unless params[:initial_comment].nil?
          payload_complete[:thread_ts] = params[:thread_ts] unless params[:thread_ts].nil?

          response = conn_complete.post do |req|
            req.headers['Authorization'] = "Bearer #{params[:api_token]}"
            req.body = payload_complete
          end

          result = self.formatted_result(response)
        rescue => exception
          UI.error("Exception: #{exception}")
          return nil
        else
          UI.success("Successfully uploaded file to Slack! 🚀")
          Actions.lane_context[SharedValues::FILE_UPLOAD_TO_SLACK_RESULT] = result
          return result
        end
      end

      def self.formatted_result(response)
        result = {
          status: response[:status],
          body: response.body || "",
          json: self.parse_json(response.body) || {}
        }
      end

      def self.determine_upload_filename(params, file_path)
        if params[:file_name].to_s.empty?
          File.basename(file_path)
        else
          if File.extname(params[:file_name]).to_s.empty?
            params[:file_name].to_s + File.extname(file_path)
          else
            params[:file_name].to_s
          end
        end
      end

      def self.parse_json(value)
        require 'json'

        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Upload a file to slack channel"
      end

      def self.details
        "Upload a file to slack channel or DM to a slack user"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_token,
                                       env_name: "FL_FILE_UPLOAD_TO_SLACK_BOT_TOKEN",
                                       description: "Slack bot Token",
                                       sensitive: true,
                                       code_gen_sensitive: true,
                                       is_string: true,
                                       default_value: ENV["SLACK_API_TOKEN"],
                                       default_value_dynamic: true,
                                       optional: false),
          FastlaneCore::ConfigItem.new(key: :channels,
                                       env_name: "FL_FETCH_FILES_SLACK_CHANNELS",
                                       description: "Comma-separated list of slack #channel names where the file will be shared",
                                       is_string: true,
                                       optional: false),
          FastlaneCore::ConfigItem.new(key: :file_path,
                                       env_name: "FL_FILE_UPLOAD_TO_SLACK_FILE_PATH",
                                       description: "relative file path which will upload to slack",
                                       is_string: true,
                                       optional: false),
          FastlaneCore::ConfigItem.new(key: :file_name,
                                       env_name: "FL_FILE_UPLOAD_TO_SLACK_FILE_NAME",
                                       description: "This is optional filename of the file",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :file_type,
                                       env_name: "FL_FILE_UPLOAD_TO_SLACK_FILE_TYPE",
                                       description: "This is optional filetype of the file",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :title,
                                       env_name: "FL_FILE_UPLOAD_TO_SLACK_TITLE",
                                       description: "This is optional Title of file",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :initial_comment,
                                       env_name: "FL_FILE_UPLOAD_TO_SLACK_INITIAL_COMMENT",
                                       description: "This is optional message text introducing the file",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :thread_ts,
                                       env_name: "FL_FILE_UPLOAD_TO_SLACK_THREAD_TS",
                                       description: "Provide another message's ts value to make this message a reply",
                                       is_string: true,
                                       optional: true)
        ]
      end

      def self.authors
        ["crazymanish"]
      end

      def self.example_code
        [
          'file_upload_to_slack(
            channels: "slack_channel_name",
            file_path: "fastlane/test.png"
          )',
          'file_upload_to_slack(
            title: "This is test title",
            channels: "slack_channel_name1, slack_channel_name2",
            file_path: "fastlane/report.xml"
          )',
          'file_upload_to_slack(
            title: "This is test title",
            initial_comment: "This is test initial comment",
            channels: "slack_channel_name",
            file_path: "fastlane/screenshots.zip"
          )',
          'file_upload_to_slack(
            title: "This is test title", # Optional, uploading file title
            initial_comment: "This is test initial comment",  # Optional, uploading file initial comment
            channels: "slack_channel_name",
            file_path: "fastlane/screenshots.zip",
            thread_ts: thread_ts # Optional, Provide parent slack message `ts` value to upload this file as a reply.
          )'
        ]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
