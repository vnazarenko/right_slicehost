require "test/unit"
require 'pp'

# Unit test for SliceHost library
# Specify your slicehost account credentials as described in test_credentials.rb
# Will use the last ip returned by 'list_ips' to create test servers

$:.unshift File.dirname(__FILE__)
require "#{File.dirname(__FILE__)}/../lib/right_slicehost"
require 'test_credentials'

require 'rubygems'
require 'uuid'
class TestRightSliceHost < Test::Unit::TestCase

  def setup
    TestCredentials.get_credentials
    @slicehost = RightScale::SliceHost::API.new(TestCredentials.api_password)
  end

  def test_images
    images = @slicehost.images.get
    assert images.is_a?(Array)
  end

  def test_flavors
    flavors = @slicehost.flavors.get
    assert flavors.is_a?(Array)
  end

  def test_slices_get
    slices = @slicehost.slices.get
    assert slices.is_a?(Array)
  end

  def test_slices
    image_id = @slicehost.images.get.first["id"]
    flavor_id = @slicehost.flavors.get.first["id"]
    name = "RightSliceHost-#{UUID.generate}"

    # Create a slice
    post_params = {:image_id => image_id, :flavor_id => flavor_id, 
        :name => name }
    slice = @slicehost.slices.post(post_params)
    assert_equal("build", slice["status"])
    assert_not_nil(slice["id"])
    assert_not_nil(slice["root_password"])
  
    # Reboot the slice
    # ... todo ...
    
    # Delete the slice
    @slicehost.slices[slice["id"]].delete
    #assert @slicehost.slices.get.collect { |s| s["id"] == slice["id"]}.empty?
  end


end

