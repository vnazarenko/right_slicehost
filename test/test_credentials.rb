class TestCredentials

  @@api_password = nil 

  def self.api_password
    @@api_password
  end
  def self.api_password=(newval)
    @@api_password = newval
  end

# Make sure you have environment vars set:
# 
# export SLICEHOST_API_PASSWORD ='your_gogrid_key'
#
# or you have a file: ~/.rightscale/test_slicehost_credentials.rb with text:
# 
#  TestCredentials.api_password = 'your_api_oassword'

  def self.get_credentials
    if ENV["SLICEHOST_API_PASSWORD"] 
      self.api_password = ENV["SLICEHOST_API_PASSWORD"]
    else
      Dir.chdir do
        begin
          Dir.chdir('./.rightscale') do 
            require 'test_slicehost_credentials'
          end
        rescue Exception => e
          puts "Couldn't chdir to ~/.rightscale: #{e.message}"
        end
      end
    end
  end

end
