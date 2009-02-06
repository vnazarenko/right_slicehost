class TestSlicehostCredentials

  @@password = nil

  def self.password
    @@password
  end
  def self.password=(newval)
    @@password = newval
  end

# Make sure you have environment vars set:
#
# export SLICEHOST_PASSWORD='your_slicehost_password'
#
# or you have a file: ~/.rightscale/test_slicehost_credentials.rb with text:
#
#  TestSlicehostCredentials.password = 'your_slicehost_password'
#
  def self.get_credentials
    begin
      require '~/.rightscale/test_slicehost_credentials'
    rescue Exception => e
      puts e.message
    end
  end
end
