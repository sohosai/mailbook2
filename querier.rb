require "active_support"
require "mongo"

class Querier
  DB_NAME = 'mailbook2'
  IDENT_REGEXP = /^[_a-z][_a-z0-9]*$/
  ELEMENT_REGEXP = /^([_a-z][_a-z0-9]*|\*)$/

  class InvalidAliasName < StandardError ; end
  class InvalidAliasElement < StandardError ; end
  class InvalidLabel < StandardError ; end
  class CircularReference < StandardError ; end

  class Revision
    attr_reader :id

    def initialize(client, rev = nil)
      @client = client
      @id = rev
    end

    def virgin?
      id.nil?
    end

    def accounts
      @client["accounts_#{id}"]
    end

    def aliases
      @client["aliases_#{id}"]
    end

    def alias_names
      aliases.find.distinct(:alias)      
    end

    def alias_elements
      docs = aliases.find.aggregate [
        {
          '$unwind': '$elements'
        },
        { 
          '$group': {
            _id: nil,
            elements: { '$addToSet': '$elements' }
          }
        }
      ]
      docs.first['elements']
    end

    def labels
      docs = accounts.find.aggregate [
        {
          '$unwind': '$labels'
        },
        { 
          '$group': {
            _id: nil,
            labels: { '$addToSet': '$labels' }
          }
        }
      ]
      docs.first['labels']
    end

    def valid_labels?
      labels.all? {|label| label.match(IDENT_REGEXP) }
    end

    def valid_aliases?
      alias_names.all? {|alias_name| alias_name.match(IDENT_REGEXP) }
    end

    def valid_alias_elements?
      alias_elements.all? {|element| element.match(ELEMENT_REGEXP) }
    end

    def valid!
      raise InvalidAliasName unless valid_aliases?
      raise InvalidAliasElement unless valid_alias_elements?
      raise InvalidLabel unless valid_labels?
      
      alias_names.each do |alias_name|
        find(alias_name)
      end
      true
    end

    def create!(new_accounts, new_aliases)
      raise "This revision is not virgin" unless virgin?
      
      @id = gen_rev_id
      begin
        new_accounts.each_slice(50) do |group|
          accounts.insert_many group
        end

        new_aliases.each_slice(50) do |group|
          aliases.insert_many group
        end

        valid!
      rescue => err
        # rollback
        accounts.drop
        aliases.drop
        @id = nil

        raise err
      end
    end

    def activate!
      @client[:reflog].insert_one({ rev: id })
    end

    def find(query)
      resolve([], query)
    end

    private
    def resolve(footmark, query)
      raise CicularReference if footmark.include? query
      query.strip!
      return all_accounts if query == '*'
      resolved = resolve_alias(footmark, query)
      return resolved unless resolved.nil?
      resolve_label(footmark, query)
    end

    def resolve_alias(footmark, query)
      entry = aliases.find(alias: query).first
      return nil if entry.nil?

      resolved = entry[:elements].map do |element|
        resolve(footmark + [query], element)
      end
      resolved.flatten(1).uniq
    end

    def resolve_label(footmark, query)
      accounts.find(labels: query).map {|doc| doc.slice('name', 'email') }
    end

    def all_accounts
      accounts.find.to_a.map {|doc| doc.slice('name', 'email') }
    end

    def gen_rev_id
      datetime = Time.now.strftime "%Y%m%d_%H%M%S_%6N"
      suffix = Random.rand(1000).to_s.rjust(3, '0')
      "#{datetime}_#{suffix}"
    end
  end

  def initialize
    @client = Mongo::Client.new(ENV['MONGODB_URL'])
  end

  def update(new_accounts, new_aliases)
    rev = Revision.new(@client)
    rev.create!(new_accounts, new_aliases)
    rev.activate!
    rev
  end

  def head
    Revision.new(@client, head_rev)
  end

  def rev(id)
    Revision.new(@client, id)
  end

  private
  def head_rev
    head_doc = @client[:reflog].find.sort(_id: -1).first
    return nil if head_doc.nil?
    head_doc["rev"]
  end
end
