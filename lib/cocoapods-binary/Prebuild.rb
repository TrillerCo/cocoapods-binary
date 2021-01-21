require_relative 'rome/build_framework'
require_relative 'helper/passer'
require_relative 'helper/target_checker'
require_relative 'tool/tool'


# patch prebuild ability
module Pod
    class Installer

        
        private

        def local_manifest 
            if not @local_manifest_inited
                @local_manifest_inited = true
                raise "This method should be call before generate project" unless self.analysis_result == nil
                @local_manifest = self.sandbox.manifest
            end
            @local_manifest
        end

        # @return [Analyzer::SpecsState]
        def prebuild_pods_changes
            return nil if local_manifest.nil?
            if @prebuild_pods_changes.nil?
                changes = local_manifest.detect_changes_with_podfile(podfile)
                @prebuild_pods_changes = Analyzer::SpecsState.new(changes)
                # save the chagnes info for later stage
                Pod::Prebuild::Passer.prebuild_pods_changes = @prebuild_pods_changes 
            end
            @prebuild_pods_changes
        end

        
        public 

        # check if need to prebuild
        def have_exact_prebuild_cache?
            # check if need build frameworks
            return false if local_manifest == nil
            
            changes = prebuild_pods_changes
            added = changes.added
            changed = changes.changed 
            unchanged = changes.unchanged
            deleted = changes.deleted 
            
            exsited_framework_pod_names = sandbox.exsited_framework_pod_names
            missing = unchanged.select do |pod_name|
                not exsited_framework_pod_names.include?(pod_name)
            end
            
            UI.puts "".magenta
            UI.puts "Frameworks summary:".magenta
            UI.puts "".magenta
            UI.puts "Added: #{added}".cyan
            UI.puts "Changed: #{changed}".cyan
            UI.puts "Unchanged: #{unchanged}".cyan
            UI.puts "Deleted: #{deleted}".cyan
            UI.puts "Missing: #{missing}".cyan
            UI.puts "".magenta
            
            needed = (added + changed + deleted + missing)
            return needed.empty?
        end
        
        
        # The install method when have completed cache
        def install_when_cache_hit!
            # just print log
            self.sandbox.exsited_framework_target_names.each do |name|
                UI.puts "Using #{name}".magenta
            end
        end
    

        # Build the needed framework files
        def prebuild_frameworks! 

            # build options
            sandbox_path = sandbox.root
            existed_framework_folder = sandbox.generate_framework_path
            bitcode_enabled = Pod::Podfile::DSL.bitcode_enabled
            targets = []
            
            if local_manifest != nil

                changes = prebuild_pods_changes
                added = changes.added
                changed = changes.changed 
                unchanged = changes.unchanged
                deleted = changes.deleted
                
                existed_framework_folder.mkdir unless existed_framework_folder.exist?
                exsited_framework_pod_names = sandbox.exsited_framework_pod_names
    
                # additions
                missing = unchanged.select do |pod_name|
                    not exsited_framework_pod_names.include?(pod_name)
                end
                
                root_names_to_update = (added + changed + missing)

                # transform names to targets
                cache = []
                targets = root_names_to_update.map do |pod_name|
                    tars = Pod.fast_get_targets_for_pod_name(pod_name, self.pod_targets, cache)
                    if tars.nil? || tars.empty?
                        raise "There's no target named (#{pod_name}) in Pod.xcodeproj.\n #{self.pod_targets.map(&:name)}" if t.nil?
                    end
                    tars
                end.flatten

                # add the dendencies
                dependency_targets = targets.map {|t| t.recursive_dependent_targets }.flatten.uniq || []
                targets = (targets + dependency_targets).uniq
            else
                targets = self.pod_targets
            end

            targets = targets.reject {|pod_target| sandbox.local?(pod_target.pod_name) }

            
            # build!
            Pod::UI.puts "Prebuild frameworks (total #{targets.count})".yellow
            Pod::Prebuild.remove_build_dir(sandbox_path)
            targets.each do |target|
                if !target.should_build?
                    UI.puts "Skipping #{target.label}. Nothing to build.".green
                    next
                end
                
                dependency_targets = targets.map {|t| t.recursive_dependent_targets }.flatten.uniq || []
                

                output_path = sandbox.framework_folder_path_for_target_name(target.name)
                output_path.mkpath unless output_path.exist?
                Pod::Prebuild.build(sandbox_path, target, output_path, bitcode_enabled,  Podfile::DSL.custom_build_options,  Podfile::DSL.custom_build_options_simulator)

                # save the resource paths for later installing
                if target.static_framework? and !target.resource_paths.empty?
                    framework_path = output_path + target.framework_name
                    standard_sandbox_path = sandbox.standard_sanbox_path

                    resources = begin
                        if Pod::VERSION.start_with? "1.5"
                            target.resource_paths
                        else
                            # resource_paths is Hash{String=>Array<String>} on 1.6 and above
                            # (use AFNetworking to generate a demo data)
                            # https://github.com/leavez/cocoapods-binary/issues/50
                            target.resource_paths.values.flatten
                        end
                    end
                    raise "Wrong type: #{resources}" unless resources.kind_of? Array

                    path_objects = resources.map do |path|
                        object = Prebuild::Passer::ResourcePath.new
                        object.real_file_path = framework_path + File.basename(path)
                        object.target_file_path = path.gsub('${PODS_ROOT}', standard_sandbox_path.to_s) if path.start_with? '${PODS_ROOT}'
                        object.target_file_path = path.gsub("${PODS_CONFIGURATION_BUILD_DIR}", standard_sandbox_path.to_s) if path.start_with? "${PODS_CONFIGURATION_BUILD_DIR}"
                        
                        if !object.real_file_path.exist? && object.real_file_path.extname == '.xib'
                            object.real_file_path = object.real_file_path.sub_ext('.nib')
                            object.target_file_path = Pathname(object.target_file_path).sub_ext('.nib').to_path
                        elsif !object.real_file_path.exist? && object.real_file_path.extname == '.storyboard'
                            object.real_file_path = object.real_file_path.sub_ext('.storyboardc')
                            object.target_file_path = Pathname(object.target_file_path).sub_ext('.storyboardc').to_path
                        elsif !object.real_file_path.exist? && object.real_file_path.extname == '.ttf'
                            object.real_file_path = object.target_file_path.gsub("Pods/", "Pods/_Prebuild/")
                        elsif !object.real_file_path.exist? && object.real_file_path.extname == '.aiff'
                            object.real_file_path = object.target_file_path.gsub("Pods/", "Pods/_Prebuild/")
                        elsif !object.real_file_path.exist? && object.real_file_path.extname == '.sh'
                            object.real_file_path = object.target_file_path.gsub("Pods/", "Pods/_Prebuild/")
                        elsif !object.real_file_path.exist? && object.real_file_path.extname == '.plist'
                            object.real_file_path = object.target_file_path.gsub("Pods/", "Pods/_Prebuild/")
                        elsif !object.real_file_path.exist? && object.real_file_path.extname == '.png'
                            object.real_file_path = object.target_file_path.gsub("Pods/", "Pods/_Prebuild/")
                        elsif !object.real_file_path.exist? && object.real_file_path.extname == '.bundle' && Pathname.new(object.target_file_path.gsub("Pods/", "Pods/build/Release-iphonesimulator/")).exist?
                            object.real_file_path = object.target_file_path.gsub("Pods/", "Pods/build/Release-iphonesimulator/")
                        elsif !object.real_file_path.exist? && object.real_file_path.extname == '.bundle' && Pathname.new(object.target_file_path.gsub("Pods/", "Pods/_Prebuild/")).exist?
                            object.real_file_path = object.target_file_path.gsub("Pods/", "Pods/_Prebuild/")
                        end
                        object
                    end
                    Prebuild::Passer.resources_to_copy_for_static_framework[target.name] = path_objects
                end
            end            
            #Pod::Prebuild.remove_build_dir(sandbox_path)


            # copy vendored libraries and frameworks
            targets.each do |target|
                root_path = self.sandbox.pod_dir(target.name)
                target_folder = sandbox.framework_folder_path_for_target_name(target.name)
                UI.puts "Copying framework #{target.label} to #{target_folder} directory #{target_folder.to_s}".yellow
                
                if target_folder.exist?
                   next
                end
                
                # If target shouldn't build, we copy all the original files
                # This is for target with only .a and .h files
                if not target.should_build?
                    Prebuild::Passer.target_names_to_skip_integration_framework << target.name
                    FileUtils.cp_r(root_path, target_folder, :remove_destination => true)
                    next
                end

                target.spec_consumers.each do |consumer|
                    file_accessor = Sandbox::FileAccessor.new(root_path, consumer)
                    lib_paths = file_accessor.vendored_frameworks || []
                    lib_paths += file_accessor.vendored_libraries
                    
                    # @TODO dSYM files
                    lib_paths.each do |lib_path|
                        relative = lib_path.relative_path_from(root_path)
                        destination = target_folder + relative
                        destination.dirname.mkpath unless destination.dirname.exist?
                        FileUtils.cp_r(lib_path, destination, :remove_destination => true)
                    end
                end
            end

            # save the pod_name for prebuild framwork in sandbox 
            targets.each do |target|
                sandbox.save_pod_name_for_target target
            end
            
            # Remove useless files
            # remove useless pods
            all_needed_names = self.pod_targets.map(&:name).uniq
            useless_target_names = sandbox.exsited_framework_target_names.reject do |name|
                all_needed_names.include? name
            end
            useless_target_names.each do |name|
                path = sandbox.framework_folder_path_for_target_name(name)
                path.rmtree if path.exist?
            end
            
            # Issue for pods that are used as development pods
            all_needed_names.each do |name|
                output_path = sandbox.framework_folder_path_for_target_name(name)
                output_path.mkpath unless output_path.exist?
            end
            
            if not Podfile::DSL.dont_remove_source_code 
                # only keep manifest.lock and framework folder in _Prebuild
                to_remain_files = ["Manifest.lock", File.basename(existed_framework_folder)]
                to_delete_files = sandbox_path.children.select do |file|
                    filename = File.basename(file)
                    not to_remain_files.include?(filename)
                end
                to_delete_files.each do |path|
                    path.rmtree if path.exist?
                end
            else 
                # just remove the tmp files
                path = sandbox.root + 'Manifest.lock.tmp'
                path.rmtree if path.exist?
            end
            


        end
        
        
        # patch the post install hook
        old_method2 = instance_method(:run_plugins_post_install_hooks)
        define_method(:run_plugins_post_install_hooks) do 
            old_method2.bind(self).()
            if Pod::is_prebuild_stage
                self.prebuild_frameworks!
            end
        end


    end
end
