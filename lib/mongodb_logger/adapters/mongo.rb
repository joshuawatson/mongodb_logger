module MongodbLogger
  module Adapers
    class Mongo < Base

      def initialize(options = {})
        @authenticated = false
        @configuration = options
        if @configuration[:url]
          uri = URI.parse(@configuration[:url])
          @configuration[:database] = uri.path.gsub(/^\//, '')
          @connection ||= mongo_connection_object
          @authenticated = true
        else
          db_options = {database: @configuration[:database]}
          if @configuration[:username] && @configuration[:password]
            # the driver stores credentials in case reconnection is required
            db_options.merge!(user: @configuration[:username],
                           password: @configuration[:password])
            @authenticated = true
          end
          @connection ||= mongo_connection_object.with(db_options)
        end
      end

      def check_for_collection
        # setup the capped collection if it doesn't already exist
        create_collection unless @connection.database.collection_names.include?(@configuration[:collection])
        @collection = @connection[@configuration[:collection]]
      end

      def create_collection
        collection = @connection[collection_name, capped: true, size: @configuration[:capsize].to_i]
        collection.create
        collection
      end

      def insert_log_record(record, options = {})
        record[:_id] = ::BSON::ObjectId.new
        @collection.insert_one(record, write: options[:write_options])
      end

      def collection_stats
        collection_stats_hash(@collection.database.command(collstats: @collection.name).documents[0])
      end

      def rename_collection(to, drop_target = false)
        rename_collection_command(@connection.with(database: "admin").database, to, drop_target)
      end

      # filter
      def filter_by_conditions(filter)
        @collection.find(filter.get_mongo_conditions).limit(filter.get_mongo_limit).sort('$natural' => -1)
      end

      def find_by_id(id)
        @collection.find(_id: ::BSON::ObjectId.from_string(id)).first
      end

      def calculate_mapreduce(map, reduce, params = {})
        @collection.map_reduce(map, reduce, { query: params[:conditions], sort: ['$natural', -1], out: { inline: true }, raw: true }).find()
      end

      private

      def mongo_connection_object
        if @configuration[:url]
          conn = ::Mongo::Client.new(@configuration[:url])
        else
          db_options = {pool_timeout: 6}
          if @configuration[:hosts]
            hosts = @configuration[:hosts].map{|(host,port)| "#{host}:#{port}"}
            db_options.merge!(replica_set: @configuration[:application_name])
          else
            hosts = ["#{@configuration[:host]}:#{@configuration[:port]}"]
          end
          # ssl not need here, because even false will try use ssl :(
          db_options.merge!(ssl: @configuration[:ssl]) if @configuration[:ssl]
          # connection
          conn = ::Mongo::Client.new(hosts, db_options)
        end
        @connection_type = conn.class
        conn
      end

    end
  end
end