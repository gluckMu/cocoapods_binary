module PodStatic

	TARGET_SUPPORT_FILE_PATH = 'Pods/Target Support Files/'
	XCCONFIG_FILE_EXTENSION = 'xcconfig'
	LIBRARY_SEARCH_PATH_KEY = 'LIBRARY_SEARCH_PATHS'
	FRAMEWORK_SEARCH_PATH_KEY = 'FRAMEWORK_SEARCH_PATHS'
	OTHER_CFLAGS_KEY = 'OTHER_CFLAGS'
	STATIC_LIBRARY_DIR = 'Static'
	PODS_ROOT = '${PODS_ROOT}'
	DEFAULT_LIBRARY_DIR = '\$PODS_CONFIGURATION_BUILD_DIR'
	PODS_ROOT_DIR = 'Pods'
	PRODUCT_TYPE_FRAMEWORK = 'com.apple.product-type.framework'

	def PodStatic.updateConfig(path, libs)
		config = Xcodeproj::Config.new(path)
		lib_search_path = config.attributes[LIBRARY_SEARCH_PATH_KEY]
		libRegex = libs.join('|')
		new_lib_search_path = lib_search_path.gsub(/#{DEFAULT_LIBRARY_DIR}\/(#{libRegex})/) {
			|str| str.gsub(/#{DEFAULT_LIBRARY_DIR}/, PODS_ROOT + File::SEPARATOR + STATIC_LIBRARY_DIR)
		}
		config.attributes[LIBRARY_SEARCH_PATH_KEY] = new_lib_search_path
		config.save_as(Pathname.new(path))
	end

	def PodStatic.updateFrameConfig(path, libs)
		config = Xcodeproj::Config.new(path)
		framework_search_path = config.attributes[FRAMEWORK_SEARCH_PATH_KEY]
		libRegex = libs.join('|')
		new_framework_search_path = framework_search_path.gsub(/#{DEFAULT_LIBRARY_DIR}\/(#{libRegex})/) {
			|str| str.gsub(/#{DEFAULT_LIBRARY_DIR}/, PODS_ROOT + File::SEPARATOR + STATIC_LIBRARY_DIR)
		}
		config.attributes[FRAMEWORK_SEARCH_PATH_KEY] = new_framework_search_path

		other_cflags = config.attributes[OTHER_CFLAGS_KEY]
		new_other_cflags = other_cflags.gsub(/#{DEFAULT_LIBRARY_DIR}\/(#{libRegex})/) {
			|str| str.gsub(/#{DEFAULT_LIBRARY_DIR}/, PODS_ROOT + File::SEPARATOR + STATIC_LIBRARY_DIR)
		}
		config.attributes[OTHER_CFLAGS_KEY] = new_other_cflags
		config.save_as(Pathname.new(path))
	end

	def PodStatic.updateEmbedFrameworkScript(path, libs)
		embed_framework_script = ""
		libRegex = libs.join('|')
		File.open(path, 'r').each_line do |line|
			embed_framework_script += line.gsub(/install_framework \"\${BUILT_PRODUCTS_DIR}\/(#{libRegex})/) {
				|str| str.gsub(/\${BUILT_PRODUCTS_DIR}/, PODS_ROOT + File::SEPARATOR + STATIC_LIBRARY_DIR)
			}
		end
		File.open(path, "w") { |io| io.write(embed_framework_script) }
	end

	def PodStatic.updateXCConfig(target, libs)
		targetName = target.name
		Pod::UI.message "- PodStatic: Updating #{targetName} xcconfig files"
		target.build_configurations.each do |config|
			configPath = TARGET_SUPPORT_FILE_PATH + targetName + File::SEPARATOR + targetName + '.' + config.name.downcase + '.' + XCCONFIG_FILE_EXTENSION
			if target.product_type == PRODUCT_TYPE_FRAMEWORK
				updateFrameConfig(configPath, libs)
			else
				updateConfig(configPath, libs)
			end
		end

		if target.product_type == PRODUCT_TYPE_FRAMEWORK
			embed_framework_script_path = TARGET_SUPPORT_FILE_PATH + targetName + File::SEPARATOR + targetName + '-frameworks.sh'
			Pod::UI.message "- PodStatic: Updating embed framework script"
			updateEmbedFrameworkScript(embed_framework_script_path, libs)
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
						`xcodebuild -scheme #{lib} -configuration Debug build CONFIGURATION_BUILD_DIR=#{build_dir}`
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
		targetMap = Hash.new
		installer.pods_project.targets.each do |target|
			targetMap[target.name] = target
		end
		if !ENV['FORCE_BUILD']
			unchangedLibs = installer.analysis_result.sandbox_state.unchanged
			if unchangedLibs.size > 0
				changedLibs = libs.select { |lib|
					libName = targetMap[lib].product_type == PRODUCT_TYPE_FRAMEWORK ? lib + '.framework' : 'lib' + lib + '.a'
					!unchangedLibs.include?(lib) || !File.exist?(PODS_ROOT_DIR + File::SEPARATOR + STATIC_LIBRARY_DIR + File::SEPARATOR + lib + File::SEPARATOR + libName)
				}
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
