module PodStatic

	XCCONFIG_FILE_PATH = 'Pods/Target Support Files/'
	XCCONFIG_FILE_EXTENSION = 'xcconfig'
	LIBRARY_SEARCH_PATH_KEY = 'LIBRARY_SEARCH_PATHS'
	STATIC_LIBRARY_DIR = 'Static'
	PODS_ROOT = '${PODS_ROOT}'
	DEFAULT_LIBRARY_DIR = '\$PODS_CONFIGURATION_BUILD_DIR'
	PODS_ROOT_DIR = 'Pods'

	def PodStatic.updateConfig(path, libs)
		config = Xcodeproj::Config.new(path)
		libSearchPath = config.attributes[LIBRARY_SEARCH_PATH_KEY]
		libRegex = libs.join('|')
		newLibSearchPath = libSearchPath.gsub(/#{DEFAULT_LIBRARY_DIR}\/(#{libRegex})/) {
			|str| str.gsub(/#{DEFAULT_LIBRARY_DIR}/, PODS_ROOT + File::SEPARATOR + STATIC_LIBRARY_DIR)
		}
		config.attributes[LIBRARY_SEARCH_PATH_KEY] = newLibSearchPath
		config.save_as(Pathname.new(path))
	end

	def PodStatic.updateXCConfig(target, libs)
		targetName = target.name
		Pod::UI.message "- PodStatic: Updating #{targetName} xcconfig files"
		target.build_configurations.each do |config|
			configPath = XCCONFIG_FILE_PATH + targetName + File::SEPARATOR + targetName + '.' + config.name.downcase + '.' + XCCONFIG_FILE_EXTENSION
			updateConfig(configPath, libs)
		end
	end

	def PodStatic.updatePodProject(project, libs)
		if libs.length >0
			Pod::UI.message "- PodStatic: Deleting dependencies on #{libs.join(', ')}"
			podTarget = nil
			project.targets.each do |target|
				if (target.name.start_with?('Pods-'))
				    podTarget = target
				    target.dependencies.delete_if { |dependency| libs.include?(dependency.name) }
					break
				end
		    end
		    updateXCConfig(podTarget, libs)
		end
	end

	def PodStatic.buildLibs(libs)
		if libs.length > 0
			Pod::HooksManager.register('cocoapods-stats', :post_install) do |context, _|
				Dir.chdir(PODS_ROOT_DIR){
					libs.each do |lib|
						Pod::UI.message "- PodStatic: building #{lib}"
						build_dir = STATIC_LIBRARY_DIR + File::SEPARATOR + lib
						`xcodebuild clean -scheme #{lib}`
						`xcodebuild -scheme #{lib} -configuration release build CONFIGURATION_BUILD_DIR=#{build_dir}`
						`rm -rf #{build_dir + File::SEPARATOR + '*.h'}`
					end
				}
				Pod::UI.message "- PodStatic: removing derived files"
				`rm -rf build`
			end
		end
	end

	def PodStatic.libsNeedBuild(installer, libs)
		changedLibs = libs
		if !ENV['FORCE_BUILD']
			unchangedLibs = installer.analysis_result.podfile_state.unchanged
			if unchangedLibs.size > 0
				changedLibs = libs.select { |lib| !unchangedLibs.include?(lib) }
			end
		end
		changedLibs
	end

	def PodStatic.deleteLibs(installer)
		toDeleted = installer.analysis_result.podfile_state.deleted
		if toDeleted.size > 0
			Dir.chdir(PODS_ROOT_DIR){
				toDeleted.each do |lib|
					Pod::UI.message "- PodStatic: deleting #{lib}"
					`rm -rf #{STATIC_LIBRARY_DIR + File::SEPARATOR + lib}`
				end
			}
		end
	end

	def PodStatic.run(installer, libs)
		if ENV['ENABLE_STATIC_LIB']
			deleteLibs(installer)
			buildLibs(libsNeedBuild(installer, libs))
			updatePodProject(installer.pods_project, libs)
		end
	end
end
