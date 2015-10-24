# -*- encoding: utf-8 -*-
# stub: pry 0.10.1 ruby lib

Gem::Specification.new do |s|
  s.name = "pry"
  s.version = "0.10.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["John Mair (banisterfiend)", "Conrad Irwin", "Ryan Fitzgerald"]
  s.date = "2015-10-24"
  s.description = "An IRB alternative and runtime developer console"
  s.email = ["jrmair@gmail.com", "conrad.irwin@gmail.com", "rwfitzge@gmail.com"]
  s.executables = ["pry"]
  s.files = ["CHANGELOG.md", "LICENSE", "README.md", "bin/pry", "lib/pry.rb", "lib/pry/basic_object.rb", "lib/pry/cli.rb", "lib/pry/code.rb", "lib/pry/code/code_file.rb", "lib/pry/code/code_range.rb", "lib/pry/code/loc.rb", "lib/pry/code_object.rb", "lib/pry/color_printer.rb", "lib/pry/command.rb", "lib/pry/command_set.rb", "lib/pry/commands.rb", "lib/pry/commands/amend_line.rb", "lib/pry/commands/bang.rb", "lib/pry/commands/bang_pry.rb", "lib/pry/commands/cat.rb", "lib/pry/commands/cat/abstract_formatter.rb", "lib/pry/commands/cat/exception_formatter.rb", "lib/pry/commands/cat/file_formatter.rb", "lib/pry/commands/cat/input_expression_formatter.rb", "lib/pry/commands/cd.rb", "lib/pry/commands/change_inspector.rb", "lib/pry/commands/change_prompt.rb", "lib/pry/commands/code_collector.rb", "lib/pry/commands/disable_pry.rb", "lib/pry/commands/disabled_commands.rb", "lib/pry/commands/easter_eggs.rb", "lib/pry/commands/edit.rb", "lib/pry/commands/edit/exception_patcher.rb", "lib/pry/commands/edit/file_and_line_locator.rb", "lib/pry/commands/exit.rb", "lib/pry/commands/exit_all.rb", "lib/pry/commands/exit_program.rb", "lib/pry/commands/find_method.rb", "lib/pry/commands/fix_indent.rb", "lib/pry/commands/gem_cd.rb", "lib/pry/commands/gem_install.rb", "lib/pry/commands/gem_list.rb", "lib/pry/commands/gem_open.rb", "lib/pry/commands/gem_readme.rb", "lib/pry/commands/gem_search.rb", "lib/pry/commands/gist.rb", "lib/pry/commands/help.rb", "lib/pry/commands/hist.rb", "lib/pry/commands/import_set.rb", "lib/pry/commands/install_command.rb", "lib/pry/commands/jump_to.rb", "lib/pry/commands/list_inspectors.rb", "lib/pry/commands/list_prompts.rb", "lib/pry/commands/ls.rb", "lib/pry/commands/ls/constants.rb", "lib/pry/commands/ls/formatter.rb", "lib/pry/commands/ls/globals.rb", "lib/pry/commands/ls/grep.rb", "lib/pry/commands/ls/instance_vars.rb", "lib/pry/commands/ls/interrogatable.rb", "lib/pry/commands/ls/jruby_hacks.rb", "lib/pry/commands/ls/local_names.rb", "lib/pry/commands/ls/local_vars.rb", "lib/pry/commands/ls/ls_entity.rb", "lib/pry/commands/ls/methods.rb", "lib/pry/commands/ls/methods_helper.rb", "lib/pry/commands/ls/self_methods.rb", "lib/pry/commands/nesting.rb", "lib/pry/commands/play.rb", "lib/pry/commands/pry_backtrace.rb", "lib/pry/commands/pry_version.rb", "lib/pry/commands/raise_up.rb", "lib/pry/commands/reload_code.rb", "lib/pry/commands/reset.rb", "lib/pry/commands/ri.rb", "lib/pry/commands/save_file.rb", "lib/pry/commands/shell_command.rb", "lib/pry/commands/shell_mode.rb", "lib/pry/commands/show_doc.rb", "lib/pry/commands/show_info.rb", "lib/pry/commands/show_input.rb", "lib/pry/commands/show_source.rb", "lib/pry/commands/simple_prompt.rb", "lib/pry/commands/stat.rb", "lib/pry/commands/switch_to.rb", "lib/pry/commands/toggle_color.rb", "lib/pry/commands/watch_expression.rb", "lib/pry/commands/watch_expression/expression.rb", "lib/pry/commands/whereami.rb", "lib/pry/commands/wtf.rb", "lib/pry/config.rb", "lib/pry/config/behavior.rb", "lib/pry/config/convenience.rb", "lib/pry/config/default.rb", "lib/pry/core_extensions.rb", "lib/pry/editor.rb", "lib/pry/exceptions.rb", "lib/pry/helpers.rb", "lib/pry/helpers/base_helpers.rb", "lib/pry/helpers/command_helpers.rb", "lib/pry/helpers/documentation_helpers.rb", "lib/pry/helpers/options_helpers.rb", "lib/pry/helpers/table.rb", "lib/pry/helpers/text.rb", "lib/pry/history.rb", "lib/pry/history_array.rb", "lib/pry/hooks.rb", "lib/pry/indent.rb", "lib/pry/input_completer.rb", "lib/pry/input_lock.rb", "lib/pry/inspector.rb", "lib/pry/last_exception.rb", "lib/pry/method.rb", "lib/pry/method/disowned.rb", "lib/pry/method/patcher.rb", "lib/pry/method/weird_method_locator.rb", "lib/pry/object_path.rb", "lib/pry/output.rb", "lib/pry/pager.rb", "lib/pry/plugins.rb", "lib/pry/prompt.rb", "lib/pry/pry_class.rb", "lib/pry/pry_instance.rb", "lib/pry/rbx_path.rb", "lib/pry/repl.rb", "lib/pry/repl_file_loader.rb", "lib/pry/rubygem.rb", "lib/pry/terminal.rb", "lib/pry/test/helper.rb", "lib/pry/version.rb", "lib/pry/wrapped_module.rb", "lib/pry/wrapped_module/candidate.rb"]
  s.homepage = "http://pryrepl.org"
  s.licenses = ["MIT"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.3")
  s.rubygems_version = "2.2.2"
  s.summary = "An IRB alternative and runtime developer console"

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<coderay>, ["~> 1.1.0"])
      s.add_runtime_dependency(%q<slop>, ["~> 3.4"])
      s.add_runtime_dependency(%q<method_source>, ["~> 0.8.1"])
      s.add_development_dependency(%q<bundler>, ["~> 1.0"])
    else
      s.add_dependency(%q<coderay>, ["~> 1.1.0"])
      s.add_dependency(%q<slop>, ["~> 3.4"])
      s.add_dependency(%q<method_source>, ["~> 0.8.1"])
      s.add_dependency(%q<bundler>, ["~> 1.0"])
    end
  else
    s.add_dependency(%q<coderay>, ["~> 1.1.0"])
    s.add_dependency(%q<slop>, ["~> 3.4"])
    s.add_dependency(%q<method_source>, ["~> 0.8.1"])
    s.add_dependency(%q<bundler>, ["~> 1.0"])
  end
end
