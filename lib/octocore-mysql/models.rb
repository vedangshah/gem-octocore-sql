require 'active_record'
require 'redis'


module ActiveRecord
  module Base

    include ActiveModel::Serializers::JSON

    DUMP_ATTRS = [:@attributes] #, :@collection_proxies, :@loaded, :@persisted, :@record_collection]

    # Updates caching config
    # @param [String] host The host to connect to
    # @param [Fixnum] port The port to connect to
    def self.update_cache_config(host, port)
      @redis = Redis.new(host: host,
                         port: port,
                         driver: :hiredis)
    end

    # Getter for redis object
    # @return [Redis] redis cache instance
    def self.redis
      @redis
    end

    def marshal_dump
      DUMP_ATTRS.inject({}) do |val, attr|
        val[attr] = self.instance_variable_get(attr)
        val
      end
    end

    def marshal_load(data)
      DUMP_ATTRS.each do |attr|
        instance_variable_set(attr, data[attr])
      end
      instance_variable_set(:@collection_proxies, {})
      instance_variable_set(:@record_collection, nil)
    end

    # Override ActiveRecord::Base here
    module ClassMethods

      # fakes up data
      def fake_data_with(args, values, opts={})
        res = []
        ts = args.fetch(:ts, 7.days.ago..Time.now.floor)
        if ts.class == Range
          bod = opts.fetch(:bod, false)
          ts_begin = ts.begin
          ts_end = ts.end
          if bod
            ts_begin = ts_begin.beginning_of_day
            ts_end = ts_end.end_of_day
          end
          step = opts.fetch(:step, 1.minute)
          ts_begin.to(ts_end, step).each do |_ts|
            _args = args.merge({ ts: _ts })
            r = self.where(_args)
            if r.count == 0
              res << self.new(_args.merge(values)).save!
            else
              res << r
            end
          end
        elsif ts.class == Time
          _args = args.merge({ ts: ts }).merge(values)
          res << self.new(_args).save!
        end
        res.flatten
      end

      # Recreates this object from other object
      def recreate_from(obj)
        keys = self.key_column_names
        args = {}
        if obj.respond_to?(:enterprise_id) and obj.respond_to?(:uid)
          args[keys.delete(:enterprise_id)] = obj.enterprise_id
          if keys.length == 1
            args[keys.first] = obj.uid
            self.get_cached(args)
          else
            puts keys.to_a.to_s
            raise NotImplementedError, 'See octocore/models.rb'
          end
        end
      end

      # If a record exists, will find it and update it's value with the
      #   provided options. Else, will just create the record.
      def findOrCreateOrUpdate(args, options = {})
        cache_key = gen_cache_key(args)
        res = get_cached(args)
        if res
          dirty = false

          # handle price separately because of float issues
          if options.has_key?(:price)
            _v = options.delete(:price)
            dirty = _v.round(2) != res.price.round(2)
          end

          # remaining opts
          options.each do |k, v|
            if res.respond_to?(k)
              unless res.public_send(k) == v
                dirty = true
                res.public_send("#{ k }=", v)
              end
            end
          end

          if dirty
            res.save!
            ActiveRecord::Base.redis.setex(cache_key, get_ttl,
                                       Octo::Utils.serialize(res))
          end
        else
          _args = args.merge(options)
          res = self.new(_args).save!
          ActiveRecord::Base.redis.setex(cache_key, get_ttl,
                                     Octo::Utils.serialize(res))
        end
        res
      end

      # Finds the record/recordset satisfying a `where` condition
      #   or create a new record from the params passed
      # @param [Hash] args The args used to build `where` condition
      # @param [Hash] options The options used to construct record
      def findOrCreate(args, options = {})
        # attempt to find the record
        res = get_cached(args)

        # on failure, do
        unless res
          args.merge!(options)
          res = self.new(args).save!

          # Update cache
          cache_key = gen_cache_key(args)
          ActiveRecord::Base.redis.setex(cache_key, get_ttl, Octo::Utils.serialize(res))
        end
        res
      end


      # If a record exists in a COUNTER TABLE, it will find
      #  it and increment or decrement it's value with the
      #  provided options. Else, will just create the
      #  record with default value.
      def findOrCreateOrAdjust(args, options)
        self.where(args).data_set.increment(options)
      end


      # Perform a cache backed get
      # @param [Hash] args The arguments hash for the record
      #   to be found
      # @return [ActiveRecord::Base::RecordSet] The record matching
      def get_cached(args)
        cache_key = gen_cache_key(args)

        begin
          cached_val = ActiveRecord::Base.redis.get(cache_key)
        rescue Exception
          cached_val = nil
        end

        unless cached_val
          res = where(args)
          result_count = res.count
          if result_count == 0
            return nil
          elsif result_count == 1
            cached_val = Octo::Utils.serialize(res.first)
            ActiveRecord::Base.redis.setex(cache_key, get_ttl, cached_val)
          elsif result_count > 1
            cached_val = Octo::Utils.serialize(res)
            ActiveRecord::Base.redis.setex(cache_key, get_ttl, cached_val)
          end
        end
        begin
          Octo::Utils.deserialize(cached_val)
        rescue Exception => e
          Octo.logger.error e
          nil
        end
      end

      private

      # Generate cache key
      # @param [Hash] args The arguments for fetching hash
      # @return [String] Cache key generated
      def gen_cache_key(args)
        args = args.flatten
        args.unshift(self.name.to_s)
        args.join('::')
      end

      def get_ttl
        # default ttl of 1 hour
        ttl = 60
        if self.constants.include?(:TTL)
          ttl = self.const_get(:TTL)
        end

        # convert ttl into seconds
        ttl *= 60
      end

    end
  end
end


require 'octocore-mysql/models/enterprise'
require 'octocore-mysql/models/enterprise/adapter_details'
require 'octocore-mysql/models/enterprise/api_event'
require 'octocore-mysql/models/enterprise/api_hit'
require 'octocore-mysql/models/enterprise/api_key'
require 'octocore-mysql/models/enterprise/api_track'
require 'octocore-mysql/models/enterprise/app_init'
require 'octocore-mysql/models/enterprise/app_login'
require 'octocore-mysql/models/enterprise/app_logout'
require 'octocore-mysql/models/enterprise/authorization'
require 'octocore-mysql/models/enterprise/category'
require 'octocore-mysql/models/enterprise/category_baseline'
require 'octocore-mysql/models/enterprise/category_hit'
require 'octocore-mysql/models/enterprise/category_trend'
require 'octocore-mysql/models/enterprise/conversions'
require 'octocore-mysql/models/enterprise/ctr'
require 'octocore-mysql/models/enterprise/dimension_choice'
require 'octocore-mysql/models/enterprise/engagement_time'
require 'octocore-mysql/models/enterprise/funnels'
require 'octocore-mysql/models/enterprise/funnel_data'
require 'octocore-mysql/models/enterprise/funnel_tracker'

require 'octocore-mysql/models/enterprise/gcm'
require 'octocore-mysql/models/enterprise/newsfeed_hit'
require 'octocore-mysql/models/enterprise/notification_hit'
require 'octocore-mysql/models/enterprise/page'
require 'octocore-mysql/models/enterprise/pageload_time'
require 'octocore-mysql/models/enterprise/page_view'
require 'octocore-mysql/models/enterprise/product'
require 'octocore-mysql/models/enterprise/product_baseline'
require 'octocore-mysql/models/enterprise/product_hit'
require 'octocore-mysql/models/enterprise/product_page_view'
require 'octocore-mysql/models/enterprise/product_trend'
require 'octocore-mysql/models/enterprise/push_key'
require 'octocore-mysql/models/enterprise/rules'
require 'octocore-mysql/models/enterprise/segment.rb'
require 'octocore-mysql/models/enterprise/segment_data.rb'
require 'octocore-mysql/models/enterprise/tag'
require 'octocore-mysql/models/enterprise/tag_hit'
require 'octocore-mysql/models/enterprise/tag_baseline'
require 'octocore-mysql/models/enterprise/tag_trend'
require 'octocore-mysql/models/enterprise/template'

require 'octocore-mysql/models/user'
require 'octocore-mysql/models/user/push_token'
require 'octocore-mysql/models/user/user_browser_details'
require 'octocore-mysql/models/user/user_location_history'
require 'octocore-mysql/models/user/user_persona'
require 'octocore-mysql/models/user/user_phone_details'
require 'octocore-mysql/models/user/user_profile'
require 'octocore-mysql/models/user/user_timeline'

require 'octocore-mysql/models/subscribe'
require 'octocore-mysql/models/contactus'

require 'octocore-mysql/utils'
