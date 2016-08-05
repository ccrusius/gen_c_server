package org.erlang.gradle

import org.gradle.api.GradleException
import org.gradle.api.Project

class ErlangExtension {
  String version = "1.0"

  String groovyDslVersion = "1.0.0.preview2"

  final Project project

  String erl = "erl"

  String erlc = "erlc"

  ErlangExtension(Project project) {
    this.project = project
  }

  String eval(String command) {
    def cmdline = [
      this.erl, '-noshell', '-s', 'init', 'stop', '-eval', command
    ]
    project.logger.debug(cmdline.join(' '))
    def process = new ProcessBuilder(cmdline).start()
    process.waitFor()
    if(process.exitValue() != 0) {
      throw new GradleException('erl failed.')
    }
    return process.text.toString().trim()
  }
}
