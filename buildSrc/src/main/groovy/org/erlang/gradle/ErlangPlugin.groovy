package org.erlang.gradle

import org.gradle.api.Plugin
import org.gradle.api.Project

class ErlangPlugin implements Plugin<Project> {
  static final String ERLANG = 'erlang'

  void apply(Project project) {
    project.apply(plugin: 'base')

    ErlangExtension extension = project.extensions.create(
      ERLANG,
      ErlangExtension,
      project)

    project.afterEvaluate {
      if(!project.extensions.erlang.erl) {
        project.extensions.erlang.erl = "erl"
      }
      if(!project.extensions.erlang.erlc) {
        project.extensions.erlang.erlc = "erlc"
      }
    }

    project.logger.info("[Erlang] ${extension.version}")
    project.logger.info("[Erlang] groovy-dsl: ${extension.groovyDslVersion}")
  }
}
