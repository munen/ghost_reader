require 'i18n'
require 'net/http'
require 'json'

module GhostReader
  class Backend
    include I18n::Backend::Simple::Implementation

    def initialize(url, opts={})
      @url=url
      @default_backend=opts[:default_backend]
      @wait_time=opts[:wait_time] || 30
      @hits={}
      @misses={}
      @last_server_call=0
      # initiates first call for filling caches in background
      call_server
    end

    # calculates data about cache-miss for server
    def calc_miss_data(misses)
      miss_data={}
      misses.each_pair do |key, key_data|
        key_result={}
        miss_data[key]=key_result
        if @default_backend
          default_data={}
          @default_backend.available_locales.each do |available_locale|
            default_value = @default_backend.lookup available_locale, key
            default_data[available_locale]= default_value if default_value
          end
          key_result[:default]=default_data unless default_data.empty?
        end
        count_data={}
        key_result[:count]=count_data
        key_data.each_pair do |locale, count|
          count_data[locale.to_sym]=count
        end
      end
      miss_data
    end

    # contact server and exchange data if last call is more than @wait_time
    #seconds
    def call_server
      if @bg_thread && (not @bg_thread.alive?)
        # get the values from the last call
        @store=@bg_thread[:store]
        @last_version=@bg_thread[:last_version]
        @bg_thread = nil
      end
      return if Time.now.to_i-@last_server_call<@wait_time

      # dont start more than one background_thread
      return if @bg_thread && @bg_thread.alive?
      # take the needed Values and give it to the thread
      misses=@misses
      hits=@hits
      # make new empty values for collecting statistics
      @hits={}
      @misses={}
      @last_server_call=Time.now.to_i

      @bg_thread=Thread.new(misses, hits) do
        miss_data = calc_miss_data(misses)

        if miss_data.size>0 || hits.size>0

          url=URI.parse(@url)
          req=Net::HTTP::Post.new(url.path)
          req['If-Modified-Since']=@last_version
          req.set_form_data({:hits=>hits.to_json,
                             :miss=>miss_data.to_json})
          res = Net::HTTP.new(url.host, url.port).start do |http|
            http.request(req)
          end
          case res
            when Net::HTTPSuccess
              Thread.current[:store]=YAML.load(res.body.to_s)
              Thread.current[:last_version]=res["last-modified"]
          end
        else
          url=URI.parse(@url)
          req=Net::HTTP::Get.new(url.path)
          req['If-Modified-Since']=@last_version if @last_version
          res = Net::HTTP.new(url.host, url.port).start do |http|
            http.request(req)
          end
          case res
            when Net::HTTPSuccess
              Thread.current[:store]=YAML.load(res.body.to_s)
              Thread.current[:last_version]=res["last-modified"]
          end
        end
      end

    end

    # counts a hit to a key
    def inc_hit(key)
      if @hits[key]
        @hits[key]+=1
      else
        @hits[key]=1
      end
    end

    # counts a miss to a key and a locale
    def inc_miss(locale, key)
      if @misses[key]
        key_hash=@misses[key]
      else
        key_hash={}
        @misses[key]=key_hash
      end
      if (key_hash[locale])
        key_hash[locale]+=1
      else
        key_hash[locale]=1
      end
    end

    def lookup(locale, key, scope = [], options = {})
      init_translations unless initialized?
      call_server
      keys = I18n.normalize_keys(locale, key, scope, options[:separator])

      found_value=keys.inject(@store) do |result, _key|
        _key = _key.to_s
        unless result.is_a?(Hash) && result.has_key?(_key)
          inc_miss locale.to_s, key.to_s
          return @default_backend.lookup locale, key
        end
        result = result[_key]
        result
      end
      inc_hit key.to_s
      found_value
    end
  end
end
