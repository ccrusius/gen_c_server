package org.erlang.gradle

import org.gradle.api.GradleException
import org.gradle.api.Project

class ErlangExtension {
  String version = "1.0"

  String groovyDslVersion = "1.0.0.preview2"

  final Project project

  String erl = "erl"

  String erlc = "erlc"

  String escript = "escript"

  ErlangExtension(Project project) {
    this.project = project
  }

  String eval(String command) {
    def cmdline = [
      this.erl, '-noshell', '-s', 'init', 'stop', '-eval', command
    ]
    //
    // I could not make the standard 'erl -noshell' command work on
    // Windows. The most reliable "solution" so far has been to use
    // 'escript' on a temporary file.
    //
    def isWindows = org.gradle.internal.os.OperatingSystem.current().isWindows()
    if(isWindows) {
      File script = File.createTempFile("temp",".erl")
      script.with {
        deleteOnExit()
        write("%% -*- erlang -*-\nmain(_) ->\n" + command)
      }
      cmdline = [ this.escript, script.absolutePath ]
    }
    //
    // Back to semi-normalcy
    //
    project.logger.debug(cmdline.join(' '))
    def process = new ProcessBuilder(cmdline).start()
    process.waitFor()
    if(process.exitValue() != 0) {
      throw new GradleException('erl failed.')
    }
    def result = process.text.toString().trim()
    project.logger.debug("ErlangExtension::eval(" + command + ")=" + result)
    return result
  }
}
