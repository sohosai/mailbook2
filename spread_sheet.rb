require "active_support"
require "google_drive"
require 'base64'

class SpreadSheet
  SHEET_ID = ENV['SHEET_ID']
  CLIENT_SECRET = MultiJson.load(Base64.decode64(ENV['CLIENT_SECRET']))

  def initialize
    client_secrets = Google::APIClient::ClientSecrets.new(CLIENT_SECRET)

    client = Google::APIClient.new
    auth = client.authorization
    auth.client_id = client_secrets.client_id
    auth.client_secret = client_secrets.client_secret
    auth.refresh_token = client_secrets.refresh_token
    auth.fetch_access_token!
    access_token = auth.access_token

    session = GoogleDrive.login_with_oauth(access_token)

    worksheets = session.spreadsheet_by_key(SHEET_ID).worksheets
    @accounts = worksheets[0]
    @aliases = worksheets[1]
  end

  def accounts
    rows = (1...@accounts.num_rows).map {|i| @accounts.rows[i]}

    rows.map do |row|
      {
        name: row[0],
        email: row[1],
        labels: row[2..-1].map(&:strip).reject(&:empty?),
      }
    end
  end

  def aliases
    rows = (1...@aliases.num_rows).map {|i| @aliases.rows[i]}

    rows.map do |row|
      {
        alias: row[0],
        elements: row[1..-1].map(&:strip).reject(&:empty?),
      }
    end
  end
end
