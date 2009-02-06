require "#{File.dirname(__FILE__)}/_test_helper"

class TestSlicehost < Test::Unit::TestCase

  def setup
    @sls= Rightscale::Slicehost.new(TestSlicehostCredentials.password)
  end

  def do_test_api_call(api_call)
    # test an API call without params (should return mass of items)
    items = nil
    assert_nothing_raised(Rightscale::SlicehostError) do
      items = @sls.__send__(api_call)
    end
    assert items.is_a?(Array)
    # test an API call with item id (should return a single item)
    if items.size > 0
      item = nil
      assert_nothing_raised(Rightscale::SlicehostError) do
        item = @sls.__send__(api_call, items.first[:sls_id])
      end
      assert item.is_a?(Hash)
      assert_equal items.first, item
    end
  end

  def do_test_caching(api_call)
    # first call - nothing should be raised
    assert_nothing_raised(Rightscale::SlicehostError) do
      @sls.__send__(api_call)
    end
    # second call - must hit a cache
    assert_raise(Rightscale::SlicehostNoChange) do
      @sls.__send__(api_call)
    end
  end

  def test_01_lists
    do_test_api_call(:list_images)
    do_test_api_call(:list_flavors)
    do_test_api_call(:list_backups)
    do_test_api_call(:list_slices)
    do_test_api_call(:list_zones)
    do_test_api_call(:list_records)
  end

  def test_02_caching
    @sls.params[:cache] = true
    do_test_caching(:list_images)
    do_test_caching(:list_flavors)
    do_test_caching(:list_backups)
    do_test_caching(:list_slices)
    do_test_caching(:list_zones)
    do_test_caching(:list_records)
  end
  
end