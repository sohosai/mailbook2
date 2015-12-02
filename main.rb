require './spread_sheet'
require './querier'

class Mailbook < Sinatra::Base
  querier = Querier.new

  get '/' do
    slim :index
  end

  post '/revisions' do
    ss = SpreadSheet.new
    begin
      rev = querier.update(ss.accounts, ss.aliases)
    rescue => err
      case err  
      when Querier::InvalidAliasName
        @error = "不正なエイリアス名があります"
      when Querier::InvalidAliasElement
        @error = "不正なエイリアス要素があります"
      when Querier::InvalidLabel
        @error = "不正なラベル名があります"
      else
        @error = "不明なエラーです"
      end
      slim :error
    end
    redirect to("/revisions/#{rev.id}")
  end

  get '/revisions/:id' do
    rev = querier.rev(params[:id])
    @id = rev.id
    @labels = rev.labels.length
    @alias_names = rev.alias_names.length
    @accounts = rev.accounts.find.count
    slim :revision
  end

  get '/api/v1/groups/:group' do
    json querier.head.find(params[:group])
  end
end

#ss = SpreadSheet.new
#p q.head.find('spt15').length
