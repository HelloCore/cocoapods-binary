require 'digest'
require_relative '../tool/tool'
require "google/cloud/storage"
require 'zip'

module Pod
    class Prebuild
        class SharedCache
            extend Config::Mixin

            # `true` if there is cache for the target
            # `false` otherwise
            #
            # @return [Boolean]
            def self.has?(target, options)
                if Podfile::DSL.shared_cache_enabled
                    path = framework_cache_path_for(target, options)
                    if path.exist?
                        Pod::UI.puts "Local cache for #{target.name} found"
                        true
                    else
                        Pod::UI.puts "Local cache for #{target.name} not found"
                        if Podfile::DSL.shared_gcp_cache_enabled
                            cloud_path = cloud_framework_path_for(target, options)
                            storage = Google::Cloud::Storage.new
                            bucket = storage.bucket(Podfile::DSL.gcp_options[:bucket])
                            file = bucket.file "#{cloud_path}"
                            if not file.nil? 
                                Pod::UI.puts "GCP cache for #{target.name} found, downloading..."
                                Dir.mktmpdir {|dir|
                                    file.download "#{dir}/framework.zip"
                                    unzip("#{dir}/framework.zip", path)
                                }
                                true
                            else
                                Pod::UI.puts "GCP cache for #{target.name} not found"
                                false
                            end
                        else
                            false
                        end
                    end
                else
                    false
                end
            end

            # Copies input_path to target's cache
            def self.cache(target, input_path, options)
                if not Podfile::DSL.shared_cache_enabled
                    return
                end
                cache_path = framework_cache_path_for(target, options)
                cache_path.mkpath unless cache_path.exist?
                FileUtils.cp_r "#{input_path}/.", cache_path

                if Podfile::DSL.shared_gcp_cache_enabled
                    cloud_path = cloud_framework_path_for(target, options)
                    storage = Google::Cloud::Storage.new
                    bucket = storage.bucket(Podfile::DSL.gcp_options[:bucket])

                    Pod::UI.puts "Save to remote cache"
                    Dir.mktmpdir {|dir|
                        zip(cache_path, "#{dir}/framework.zip")
                        bucket.create_file "#{dir}/framework.zip",
                                            "#{cloud_path}"     
                    }
                end
            end

            # Path of the target's cache
            #
            # @return [Pathname]
            def self.framework_cache_path_for(target, options)
                framework_cache_path = cache_root + xcode_version
                framework_cache_path = framework_cache_path + target.name
                framework_cache_path = framework_cache_path + target.version
                options_with_platform = options + [target.platform.name]
                framework_cache_path = framework_cache_path + Digest::MD5.hexdigest(options_with_platform.to_s).to_s
            end

            def self.cloud_framework_path_for(target, options) 
                cloud_cache_path = Pathname.new('').to_s + xcode_version
                cloud_cache_path = cloud_cache_path + target.name
                cloud_cache_path = cloud_cache_path + target.version
                options_with_platform = options + [target.platform.name]
                cloud_cache_path = cloud_cache_path + Digest::MD5.hexdigest(options_with_platform.to_s).to_s
            end

            def self.zip(dir, zip_dir)
                Zip::File.open(zip_dir, Zip::File::CREATE)do |zipfile|
                    Find.find(dir) do |path|
                        Find.prune if File.basename(path)[0] == ?.
                        dest = /#{dir}\/(\w.*)/.match(path)
                        # Skip files if they exists
                        begin
                            zipfile.add(dest[1],path) if dest
                        rescue Zip::ZipEntryExistsError
                        end
                    end
                end
            end

            def self.unzip(zip, unzip_dir, remove_after = false)
                Zip::File.open(zip) do |zip_file|
                    zip_file.each do |f|
                        f_path=File.join(unzip_dir, f.name)
                        FileUtils.mkdir_p(File.dirname(f_path))
                        zip_file.extract(f, f_path) unless File.exist?(f_path)
                    end
                end
                FileUtils.rm(zip) if remove_after
            end

            # Current xcode version.
            #
            # @return [String]
            private
            class_attr_accessor :xcode_version
            # Converts from "Xcode 10.2.1\nBuild version 10E1001\n" to "10.2.1".
            self.xcode_version = `xcodebuild -version`.split("\n").first.split().last || "Unkwown"

            # Path of the cache folder
            # Reusing cache_root from cocoapods's config
            # `~Library/Caches/CocoaPods` is default value
            #
            # @return [Pathname]
            private
            class_attr_accessor :cache_root
            self.cache_root = config.cache_root + 'Prebuilt'
        end
    end
end