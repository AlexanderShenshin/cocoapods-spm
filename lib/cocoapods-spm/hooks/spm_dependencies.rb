require "cocoapods-spm/hooks/base"

module Pod
  module SPM
    class SpmDependenciesHook < Hook
      def run
        specs_with_spm_dependencies = all_specs.select(&:spm_dependencies)
        return unless specs_with_spm_dependencies

        specs_with_spm_dependencies.each do |spec|
          target = pods_project.targets.find { |t| t.name == spec.name }
          add_spm_dependencies(target, spec.spm_dependencies)
        end
        update_import_paths
        pods_project.save
      end

      private

      def podfile
        Pod::Config.instance.podfile
      end

      def add_spm_dependencies(target, dependencies)
        dependencies.each do |name, products|
          pkg = pkg_for(name)
          products.each do |product|
            ref = pods_project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
            ref.package = pkg
            ref.product_name = product
            target.package_product_dependencies << ref
          end
          pods_project.root_object.package_references << pkg
        end
      end

      def update_import_paths
        # Workaround: Currently, update the swift import paths of the base/Pods project
        # to make it effective across all pod targets
        pods_project.build_configurations.each do |config|
          to_add = '${SYMROOT}/${CONFIGURATION}${EFFECTIVE_PLATFORM_NAME}'
          import_paths = config.build_settings['SWIFT_INCLUDE_PATHS'] || ['$(inherited)']
          import_paths << to_add unless import_paths.include?(to_add)
          config.build_settings['SWIFT_INCLUDE_PATHS'] = import_paths
        end
      end

      def requirement_from(options)
        if options[:requirement]
          options[:requirement]
        elsif (version = options.delete(:version))
          { :kind => "exactVersion", :version => version }
        elsif (branch = options.delete(:branch))
          { :kind => "branch", :branch => branch }
        elsif (revision = options.delete(:commit))
          { :kind => "revision", :revision => revision }
        end
      end

      def pkg_for(name)
        options = podfile.spm_pkgs[name]
        if options.nil?
          raise "SPM package `#{name}` was not declared in Podfile. " \
                "Use method `spm_pakage` to declare such a package"
        end

        if (requirement = requirement_from(options))
          pkg = pods_project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
          pkg.repositoryURL = options[:url]
          pkg.requirement = requirement
        elsif options[:relative_path]
          pkg = pods_project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
          pkg.relative_path = options[:relative_path]
        else
          raise "No requirement was declared for package `#{name}`"
        end
        pkg
      end
    end
  end
end
