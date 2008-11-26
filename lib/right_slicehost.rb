require 'benchmark'

$:.unshift(File.dirname(__FILE__))
require 'benchmark_fix'

require 'rubygems'

require 'rest_client'
require 'roxy'
require 'activesupport'

module RightScale

  module SliceHost
  
    class API
      include Roxy::Moxie
    
      attr_reader :resource
    
      def initialize(api_password, base_uri="https://api.slicehost.com/")
        @resource = RestClient::Resource.new(base_uri, :user => api_password)
      end

      def slices
        @resource["slices"]
      end
    
      def images
        @resource["images"]
      end

      def backups
        @resource["backups"]
      end

      def flavors
        @resource["flavors"]
      end

      proxy :images do
        def get(arg=nil)
          if arg
            Hash.from_xml(proxy_target[arg].get)
          else
            Hash.from_xml(proxy_target.get).values.first
          end
        end
      end

      proxy :flavors do
        def get(arg=nil)
          if arg
            Hash.from_xml(proxy_target[arg].get)
          else
            Hash.from_xml(proxy_target.get).values.first
          end
        end
      end

      proxy :slices do

        def get(arg=nil)
          if arg
            Hash.from_xml(proxy_target[arg].get)
          else
            Hash.from_xml(proxy_target.get).values.first
          end
        end

        def post(slice)
          Hash.from_xml(proxy_target.post(:slice => slice)).values.first
        end
        
      end

    end


  end


end