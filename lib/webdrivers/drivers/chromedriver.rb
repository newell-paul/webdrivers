# frozen_string_literal: true

require 'shellwords'

module Webdrivers
  class Chromedriver < Common
    class << self
      def current_version
        Webdrivers.logger.debug 'Checking current version'
        return nil unless downloaded?

        version = binary_version
        return nil if version.nil?

        # Matches 2.46, 2.46.628411 and 73.0.3683.75
        normalize_version version[/\d+\.\d+(\.\d+)?(\.\d+)?/]
      end

      def latest_version
        return @latest_version if @latest_version

        # Versions before 70 do not have a LATEST_RELEASE file
        return normalize_version('2.41') if release_version < normalize_version('70')

        latest_applicable = if System.valid_cache?(file_name)
                              System.cached_version(file_name)
                            else
                              Webdrivers.logger.warn 'Driver caching is turned off in this version, but will '\
                              'be enabled by default in 4.x. Set the value now with `Webdrivers#cache_time=` in seconds'
                              version = latest_point_release(release_version)
                              System.cache_version(file_name, version)
                              version
                            end

        Webdrivers.logger.debug "Latest version available: #{latest_applicable}"
        @latest_version = normalize_version(latest_applicable)
      end

      # Returns currently installed Chrome version
      def chrome_version
        ver = send("chrome_on_#{System.platform}").chomp

        raise VersionError, 'Failed to find Chrome binary or its version.' if ver.nil? || ver.empty?

        Webdrivers.logger.debug "Browser version: #{ver}"
        normalize_version ver[/\d+\.\d+\.\d+\.\d+/] # Google Chrome 73.0.3683.75 -> 73.0.3683.75
      end

      private

      def latest_point_release(version)
        release_file = "LATEST_RELEASE_#{version}"
        begin
          normalize_version(Network.get(URI.join(base_url, release_file)))
        rescue StandardError
          latest_release = normalize_version(Network.get(URI.join(base_url, 'LATEST_RELEASE')))
          Webdrivers.logger.debug "Unable to find a driver for: #{version}"

          msg = version > latest_release ? 'you appear to be using a non-production version of Chrome; ' : ''
          msg = "#{msg}please set `Webdrivers::Chromedriver.required_version = <desired driver version>` to an known "\
'chromedriver version: https://chromedriver.storage.googleapis.com/index.html'
          raise VersionError, msg
        end
      end

      def file_name
        System.platform == 'win' ? 'chromedriver.exe' : 'chromedriver'
      end

      def base_url
        'https://chromedriver.storage.googleapis.com'
      end

      def download_url
        return @download_url if @download_url

        version = if required_version.version.empty?
                    latest_version
                  else
                    normalize_version(required_version)
                  end

        file_name = System.platform == 'win' ? 'windows32' : "#{System.platform}64"
        url = "#{base_url}/#{version}/chromedriver_#{file_name}.zip"
        Webdrivers.logger.debug "chromedriver URL: #{url}"
        @download_url = url
      end

      # Returns release version from the currently installed Chrome version
      #
      # @example
      #   73.0.3683.75 -> 73.0.3683
      def release_version
        chrome = normalize_version(chrome_version)
        normalize_version(chrome.segments[0..2].join('.'))
      end

      def chrome_on_win
        if browser_binary
          Webdrivers.logger.debug "Browser executable: '#{browser_binary}'"
          return System.call("powershell (Get-ItemProperty '#{browser_binary}').VersionInfo.ProductVersion").strip
        end

        # Workaround for Google Chrome when using Jruby on Windows.
        # @see https://github.com/titusfortner/webdrivers/issues/41
        if RUBY_PLATFORM == 'java'
          ver = 'powershell (Get-Item -Path ((Get-ItemProperty "HKLM:\\Software\\Microsoft' \
          "\\Windows\\CurrentVersion\\App` Paths\\chrome.exe\").\\'(default)\\'))" \
          '.VersionInfo.ProductVersion'
          return System.call(ver).strip
        end

        # Default to Google Chrome
        reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
        executable = System.call("powershell (Get-ItemProperty '#{reg}' -Name '(default)').'(default)'").strip
        Webdrivers.logger.debug "Browser executable: '#{executable}'"
        ps = "(Get-Item (Get-ItemProperty '#{reg}').'(default)').VersionInfo.ProductVersion"
        System.call("powershell #{ps}").strip
      end

      def chrome_on_linux
        if browser_binary
          Webdrivers.logger.debug "Browser executable: '#{browser_binary}'"
          return System.call("#{Shellwords.escape browser_binary} --product-version").strip
        end

        # Default to Google Chrome
        executable = System.call('which google-chrome').strip
        Webdrivers.logger.debug "Browser executable: '#{executable}'"
        System.call("#{executable} --product-version").strip
      end

      def chrome_on_mac
        if browser_binary
          Webdrivers.logger.debug "Browser executable: '#{browser_binary}'"
          return System.call("#{Shellwords.escape browser_binary} --version").strip
        end

        # Default to Google Chrome
        executable = Shellwords.escape '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
        Webdrivers.logger.debug "Browser executable: #{executable}"
        System.call("#{executable} --version").strip
      end

      #
      # Returns user defined browser executable path from Selenium::WebDrivers::Chrome#path.
      #
      def browser_binary
        # For Chromium, Brave, or whatever else
        Selenium::WebDriver::Chrome.path
      end

      def sufficient_binary?
        super && current_version && (current_version < normalize_version('70.0.3538') ||
            current_version.segments.first == release_version.segments.first)
      end
    end
  end
end