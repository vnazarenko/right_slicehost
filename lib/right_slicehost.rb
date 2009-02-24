#
# Copyright (c) 2007-2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'cgi'
require 'benchmark'
require 'md5'
require 'rubygems'
require "rexml/document"
require 'right_http_connection'

$:.unshift(File.dirname(__FILE__))
require 'benchmark_fix'
require 'support'
require 'slicehost_base'


module RightSlicehost
  MAJOR = 0
  MINOR = 1
  TINY  = 0
  VERSION = [MAJOR, MINOR, TINY].join('.')
end

module Rightscale

    #  # Slices:
    #
    #  sl = Rightscale::Slicehost.new('12345...uvwxyz')
    #
    #  sl.list_images #=>
    #    [{:sls_id=>2, :name=>"CentOS 5.2"},
    #     {:sls_id=>3, :name=>"Gentoo 2008.0"},
    #     {:sls_id=>4, :name=>"Debian 4.0 (etch)"},
    #     {:sls_id=>5, :name=>"Fedora 9"},
    #     {:sls_id=>9, :name=>"Arch 2007.08"},
    #     {:sls_id=>10, :name=>"Ubuntu 8.04.1 LTS (hardy)"},
    #     {:sls_id=>11, :name=>"Ubuntu 8.10 (intrepid)"}]
    #
    #   sl.list_flavors #=>
    #    [{:sls_id=>1, :name=>"256 slice", :price=>2000, :ram=>256},
    #     {:sls_id=>2, :name=>"512 slice", :price=>3800, :ram=>512},
    #     {:sls_id=>3, :name=>"1GB slice", :price=>7000, :ram=>1024},
    #     {:sls_id=>4, :name=>"2GB slice", :price=>13000, :ram=>2048},
    #     {:sls_id=>5, :name=>"4GB slice", :price=>25000, :ram=>4096},
    #     {:sls_id=>6, :name=>"8GB slice", :price=>45000, :ram=>8192},
    #     {:sls_id=>7, :name=>"15.5GB slice", :price=>80000, :ram=>15872}]
    #
    #  sl.create_slice(:flavor_id=>1 , :image_id=>2, :name=>'my-slice' ) #=>
    #    {:flavor_sls_id=>1,
    #     :addresses=>["173.45.224.125"],
    #     :bw_in=>0.0,
    #     :sls_id=>26831,
    #     :name=>"my-slice",
    #     :status=>"build",
    #     :bw_out=>0.0,
    #     :ip_address=>"173.45.224.125",
    #     :progress=>0,
    #     :image_sls_id=>2,
    #     :root_password=>"my-slicen57"}
    #
    #  sl.rebuild_slice(26831, :image_id => 3) #=> true
    #
    #  sl.reboot_slice(26832, :hard) #=> true
    #
    #  sl.delete_slice(26832) #=> true
    #
    #  # DNS:
    #
    #  sl.list_zones #=>
    #    [ {:origin=>"a1.my-domain.com.", :ttl=>300, :sls_id=>45486, :active=>true},
    #      {:origin=>"a2.my-domain.com.", :ttl=>300, :sls_id=>45485, :active=>true},
    #      {:origin=>"a3.my-domain.com.", :ttl=>300, :sls_id=>45487, :active=>false}, ... ]
    #
    #  sl.list_records #=>
    #    [ { :sls_id=>"348257",
    #        :zone_id=>45687,
    #        :data=>"woo-hoo.my-domain.com",
    #        :aux=>"0",
    #        :name=>"wooooohooooo",
    #        :ttl=>86400,
    #        :active=>true,
    #        :record_type=>"CNAME"}, ... ]
    #
  class Slicehost
    include RightSlicehostInterface

    def initialize(slicehost_password=nil, params={})
      slicehost_password ||= ENV['SLICEHOST_PASSWORD']
      init slicehost_password, params
    end

    def build_path(path, sls_id=nil, action=nil) # :nodoc:
      path = path.to_s
      unless (sls_id || action)
        path += '.xml'
      else
        path += "/#{sls_id}#{action ? '' : '.xml'}" if sls_id
        path += "/#{action}.xml" if action
      end
      path
    end

    def build_xml(name, params) # :nodoc:
      xml_params = params.to_a.map do |key,value|
        key = key.to_s.gsub('_','-')
        "<#{key}>#{CGI.escape(value.to_s)}</#{key}>"
      end.join("\n")
      
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
      "<#{name.to_s}>\n" +
      "#{xml_params}\n" +
      "</#{name.to_s}>\n"
    end
    
    #------------------------------------------------------------
    # Images
    #------------------------------------------------------------

    # List images.
    #
    #  sl.list_images #=>
    #    [{:sls_id=>2, :name=>"CentOS 5.2"},
    #     {:sls_id=>3, :name=>"Gentoo 2008.0"},
    #     {:sls_id=>4, :name=>"Debian 4.0 (etch)"},
    #     {:sls_id=>5, :name=>"Fedora 9"},
    #     {:sls_id=>9, :name=>"Arch 2007.08"},
    #     {:sls_id=>10, :name=>"Ubuntu 8.04.1 LTS (hardy)"},
    #     {:sls_id=>11, :name=>"Ubuntu 8.10 (intrepid)"}]
    #
    #  sl.list_images(9) #=> {:sls_id=>9, :name=>"Arch 2007.08"}
    #
    def list_images(sls_id=nil)
      req    = generate_request(Net::HTTP::Get, build_path(:images, sls_id))
      result = request_cache_or_info(:list_images, req, ImagesParser, sls_id.nil?)
      sls_id ? result.first : result
    rescue
      on_exception
    end

    #------------------------------------------------------------
    # Flavors
    #------------------------------------------------------------

    # List flavors.
    #
    #   sl.list_flavors #=> 
    #    [{:sls_id=>1, :name=>"256 slice", :price=>2000, :ram=>256},
    #     {:sls_id=>2, :name=>"512 slice", :price=>3800, :ram=>512},
    #     {:sls_id=>3, :name=>"1GB slice", :price=>7000, :ram=>1024},
    #     {:sls_id=>4, :name=>"2GB slice", :price=>13000, :ram=>2048},
    #     {:sls_id=>5, :name=>"4GB slice", :price=>25000, :ram=>4096},
    #     {:sls_id=>6, :name=>"8GB slice", :price=>45000, :ram=>8192},
    #     {:sls_id=>7, :name=>"15.5GB slice", :price=>80000, :ram=>15872}]
    #
    #      sl.list_flavors(6) #=> {:sls_id=>6, :name=>"8GB slice", :price=>45000, :ram=>8192}
    #
    def list_flavors(sls_id=nil)
      req    = generate_request(Net::HTTP::Get, build_path(:flavors, sls_id))
      result = request_cache_or_info(:list_flavors, req, FlavorsParser, sls_id.nil?)
      sls_id ? result.first : result
    rescue
      on_exception
    end

    #------------------------------------------------------------
    # Backups
    #------------------------------------------------------------

    # List backups.
    #
    #  sl.list_backups #=>
    #    [{:sls_id=>"5-6507",
    #      :slice_sls_id=>26831,
    #      :name=>"backup 1",
    #      :date=>Wed Dec 10 00:43:20 UTC 2008}, ...]
    #
    #  sl.list_backups("5-6507") #=>
    #    {:sls_id=>"5-6507",
    #     :slice_sls_id=>26831,
    #     :name=>"backup 1",
    #     :date=>Wed Dec 10 00:43:20 UTC 2008}
    #
    #
    #
    def list_backups(sls_id=nil)
      req    = generate_request(Net::HTTP::Get, build_path(:backups, sls_id))
      result = request_cache_or_info(:list_backups, req, BackupsParser, sls_id.nil?)
      sls_id ? result.first : result
    rescue
      on_exception
    end

    #------------------------------------------------------------
    # Slices
    #------------------------------------------------------------

    # List slices.
    #
    #  sl.list_slices #=>
    #    [{:bw_in=>0.05,
    #      :sls_id=>26706,
    #      :bw_out=>0.0,
    #      :ip_address=>"173.45.233.125",
    #      :progress=>100,
    #      :status=>"active",
    #      :name=>"slice26706",
    #      :image_sls_id=>11,
    #      :flavor_sls_id=>1,
    #      :addresses=>["173.45.233.125"]}, ...]
    #
    def list_slices(sls_id=nil)
      # GET /slices.xml
      req    = generate_request(Net::HTTP::Get, build_path(:slices, sls_id))
      result = request_cache_or_info(:list_slices, req, SlicesParser, sls_id.nil?)
      sls_id ? result.first : result
    rescue
      on_exception
    end

    # Create a new slice.
    #
    #  sl.create_slice(:flavor_id=>1 , :image_id=>2, :name=>'my-slice' ) #=>
    #    {:flavor_sls_id=>1,
    #     :addresses=>["173.45.224.125"],
    #     :bw_in=>0.0,
    #     :sls_id=>26831,
    #     :name=>"my-slice",
    #     :status=>"build",
    #     :bw_out=>0.0,
    #     :ip_address=>"173.45.224.125",
    #     :progress=>0,
    #     :image_sls_id=>2,
    #     :root_password=>"my-slicen57"}
    #
    def create_slice(params={})
      # POST /slices.xml
      req = generate_request(Net::HTTP::Post, build_path(:slices))
      req[:request].body = build_xml(:slice, params)
      request_info(req, SlicesParser.new(:logger => @logger)).first
    end

    # Update a slice.
    #
    #  sl.update_slice(26831, :name => 'my-awesome-slice') #=> true
    #
    def update_slice(sls_id, params={})
      # PUT /slices/id.xml
      req = generate_request(Net::HTTP::Put, build_path(:slices, sls_id))
      req[:request].body = build_xml(:slice, params)
      request_info(req, RightHttp2xxParser.new(:logger => @logger))
    end

    # Rebuild a slice.
    #
    #  sl.rebuild_slice(26831, :image_id => 3) #=> true
    #  
    def rebuild_slice(sls_id, params)
      # PUT /slices/id/rebuild.xml?params
      req = generate_request(Net::HTTP::Put, build_path(:slices, sls_id, :rebuild), params)
      request_info(req, RightHttp2xxParser.new)
    rescue
      on_exception
    end

    # Reboot a slice (soft reboot is by default).
    #
    #  sl.reboot_slice(26831) #=> true
    #  sl.reboot_slice(26832, :hard) #=> true
    #
    def reboot_slice(sls_id, hard_reboot = false)
      # PUT /slices/id/reboot.xml
      action = hard_reboot ? :hard_reboot : :reboot
      req = generate_request(Net::HTTP::Put, build_path(:slices, sls_id, action))
      request_info(req, RightHttp2xxParser.new)
    rescue
      on_exception
    end

    # Delete a slice.
    #
    #  sl.delete_slice(26831) #=> true
    # 
    def delete_slice(sls_id)
      # DELETE /slices/id.xml
      req = generate_request(Net::HTTP::Delete, build_path(:slices, sls_id))
      request_info(req, RightHttp2xxParser.new(:logger => @logger))
    end


    #------------------------------------------------------------
    # Zones
    #------------------------------------------------------------

    # List DNS Zones.
    #
    #  # bunch of zones
    #  sl.list_zones #=>
    #    [ {:origin=>"a1.my-domain.com.", :ttl=>300, :sls_id=>45486, :active=>true},
    #      {:origin=>"a2.my-domain.com.", :ttl=>300, :sls_id=>45485, :active=>true},
    #      {:origin=>"a3.my-domain.com.", :ttl=>300, :sls_id=>45487, :active=>false} ]
    #
    #  # single zone
    #  sl.list_zones(45486) #=> 
    #    {:origin=>"a1.my-domain.com.", :ttl=>300, :sls_id=>45486, :active=>true}
    #  
    def list_zones(sls_id=nil)
      # GET /zones.xml
      # GET /zones/id.xml
      req    = generate_request(Net::HTTP::Get, build_path(:zones, sls_id))
      result = request_cache_or_info(:list_zones, req, ZonesParser, sls_id.nil?)
      sls_id ? result.first : result
    rescue
      on_exception
    end

    # Create a new zone.
    #
    #  sl.create_zone(:origin => 'a4.my_domain.ru', :ttl => 111, :active => false) #=>
    #    { :origin=>"a4.my-domain.com.",
    #      :ttl=>111,
    #      :sls_id=>45689,
    #      :active=>false}
    #
    def create_zone(params={})
      params[:active] = (params[:active] ? 'Y' : 'N') unless params[:active].nil?
      # POST /zones.xml
      req = generate_request(Net::HTTP::Post, build_path(:zones))
      req[:request].body = build_xml(:zone, params)
      request_info(req, ZonesParser.new(:logger => @logger)).first
    end

    # Update a zone.
    #
    #  sl.update_zone(45486, :acive => false, :ttl => 333) #=> true
    #
    def update_zone(sls_id, params={})
      params[:active] = (params[:active] ? 'Y' : 'N') unless params[:active].nil?
      # PUT /zones/id.xml
      req = generate_request(Net::HTTP::Put, build_path(:zones, sls_id))
      req[:request].body = build_xml(:zone, params)
      request_info(req, RightHttp2xxParser.new(:logger => @logger))
    end
    
    # Delete a zone.
    #
    #  sl.delete_zone(45486) #=> true
    #
    def delete_zone(sls_id)
      # DELETE /zones/id.xml
      req = generate_request(Net::HTTP::Delete, build_path(:zones, sls_id))
      request_info(req, RightHttp2xxParser.new(:logger => @logger))
    end

    #------------------------------------------------------------
    # Records
    #------------------------------------------------------------

    # List DNS Records
    #
    #  sl.list_records #=>
    #    [ { :sls_id=>"348257",
    #        :zone_id=>45687,
    #        :data=>"woo-hoo.my-domain.com",
    #        :aux=>"0",
    #        :name=>"wooooohooooo",
    #        :ttl=>86400,
    #        :active=>true,
    #        :record_type=>"CNAME"}, ... ]
    #
    def list_records(sls_id=nil)
      # GET /records.xml
      # GET /records/id.xml
      req    = generate_request(Net::HTTP::Get, build_path(:records, sls_id))
      result = request_cache_or_info(:list_records, req, RecordsParser, sls_id.nil?)
      sls_id ? result.first : result
    rescue
      on_exception
    end

    # Create a new record.
    #
    #  sl.create_record(:zone_id => 45687, :data=>"woo-hoo.my-domain.com", :name=>"wooooohooooo", :data=>"woo-hoo.my-domain.com") #=>
    #    [ { :sls_id=>348257,
    #        :zone_id=>45687,
    #        :data=>"woo-hoo.my-domain.com",
    #        :aux=>"0",
    #        :name=>"wooooohooooo",
    #        :ttl=>86400,
    #        :active=>true,
    #        :record_type=>"CNAME"}, ... ]
    #
    def create_record(params={})
      params[:active] = (params[:active] ? 'Y' : 'N') unless params[:active].nil?
      # POST /records.xml
      req = generate_request(Net::HTTP::Post, build_path(:records))
      req[:request].body = build_xml(:record, params)
      request_info(req, RecordsParser.new(:logger => @logger)).first
    end

    # Update a record.
    #
    #  sl.update_record(348257, :ttl => 777, :data=>"oops.my-domain.com") #=> true
    #
    def update_record(sls_id, params={})
      params[:active] = (params[:active] ? 'Y' : 'N') unless params[:active].nil?
      # PUT /zones/id.xml
      req = generate_request(Net::HTTP::Put, build_path(:records, sls_id))
      req[:request].body = build_xml(:record, params)
      request_info(req, RightHttp2xxParser.new(:logger => @logger))
    end

    # Delete a record.
    #
    #  sl.delete_record(348257) #=> true
    #
    def delete_record(sls_id)
      # DELETE /records/id.xml
      req = generate_request(Net::HTTP::Delete, build_path(:records, sls_id))
      request_info(req, RightHttp2xxParser.new(:logger => @logger))
    end

    #------------------------------------------------------------
    # Parsers
    #------------------------------------------------------------

    #------------------------------------------------------------
    # Images
    #------------------------------------------------------------

    class ImagesParser < RightSlicehostParser #:nodoc:
      def tagstart(name, attributes)
        @item = {} if name == 'image'
      end
      def tagend(name)
        case name
        when 'id'    then @item[:sls_id] = @text.to_i
        when 'name'  then @item[:name]   = @text
        when 'image' then @result       << @item
        end
      end
      def reset
        @result = []
      end
    end

  #------------------------------------------------------------
  # Flavors
  #------------------------------------------------------------

    class FlavorsParser < RightSlicehostParser #:nodoc:
      def tagstart(name, attributes)
        @item = {} if name == 'flavor'
      end
      def tagend(name)
        case name
        when 'id'     then @item[:sls_id] = @text.to_i
        when 'name'   then @item[:name]   = @text
        when 'price'  then @item[:price]  = @text.to_i
        when 'ram'    then @item[:ram]    = @text.to_i
        when 'flavor' then @result        << @item
        end
      end
      def reset
        @result = []
      end
    end

  #------------------------------------------------------------
  # Backups
  #------------------------------------------------------------

    class BackupsParser < RightSlicehostParser #:nodoc:
      def tagstart(name, attributes)
        @item = {} if name == 'backup'
      end
      def tagend(name)
        case name
        when 'id'       then @item[:sls_id]       = @text
        when 'name'     then @item[:name]         = @text
        when 'slice_id' then @item[:slice_sls_id] = @text.to_i
        when 'date'     then @item[:date]         = Time.parse(@text)
        when 'backup'   then @result             << @item
        end
      end
      def reset
        @result = []
      end
    end

  #------------------------------------------------------------
  # Slices
  #------------------------------------------------------------

    class SlicesParser < RightSlicehostParser #:nodoc:
      def tagstart(name, attributes)
        @item = {}      if name == 'slice'
        @addresses = [] if name == 'addresses'
      end
      def tagend(name)
        case name
        when 'id'            then @item[:sls_id]        = @text.to_i
        when 'name'          then @item[:name]          = @text
        when 'image-id'      then @item[:image_sls_id]  = @text.to_i
        when 'flavor-id'     then @item[:flavor_sls_id] = @text.to_i
        when 'slice-id'      then @item[:slice_sls_id]  = @text.to_i
        when 'backup-id'     then @item[:backup_sls_id] = @text.to_i
        when 'status'        then @item[:status]        = @text
        when 'progress'      then @item[:progress]      = @text.to_i
        when 'bw-in'         then @item[:bw_in]         = @text.to_f
        when 'bw-out'        then @item[:bw_out]        = @text.to_f
        when 'ip-address'    then @item[:ip_address]    = @text
        when 'root-password' then @item[:root_password] = @text
        when 'address'       then @addresses           << @text
        when 'addresses'     then @item[:addresses]     = @addresses
        when 'slice'         then @result              << @item
        end
      end
      def reset
        @result = []
      end
    end

    #------------------------------------------------------------
    # Zones
    #------------------------------------------------------------

    class ZonesParser < RightSlicehostParser #:nodoc:
      def tagstart(name, attributes)
        @item = {} if name == 'zone'
      end
      def tagend(name)
        case name
        when 'id'     then @item[:sls_id] = @text.to_i
        when 'origin' then @item[:origin] = @text
        when 'ttl'    then @item[:ttl]    = @text.to_i
        when 'active' then @item[:active] = @text == 'Y'
        when 'zone'   then @result       << @item
        end
      end
      def reset
        @result = []
      end
    end

    #------------------------------------------------------------
    # Records
    #------------------------------------------------------------

    class RecordsParser < RightSlicehostParser #:nodoc:
      def tagstart(name, attributes)
        @item = {} if name == 'record'
      end
      def tagend(name)
        case name
        when 'id'          then @item[:sls_id]      = @text.to_i
        when 'record-type' then @item[:record_type] = @text
        when 'zone-id'     then @item[:zone_id]     = @text.to_i
        when 'name'        then @item[:name]        = @text
        when 'data'        then @item[:data]        = @text
        when 'ttl'         then @item[:ttl]         = @text.to_i
        when 'active'      then @item[:active]      = @text == 'Y'
        when 'aux'         then @item[:aux]         = @text
        when 'record'      then @result            << @item
        end
      end
      def reset
        @result = []
      end
    end

    #------------------------------------------------------------
    # HTTP 2xx
    #------------------------------------------------------------

    class RightHttp2xxParser < RightSlicehostParser # :nodoc:
      def parse(response)
        @result = response.is_a?(Net::HTTPSuccess)
      end
    end

  end
end
