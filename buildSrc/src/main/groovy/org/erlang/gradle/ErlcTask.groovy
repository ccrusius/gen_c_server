package org.erlang.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.TaskAction

/**
 * @author Cesar Crusius
 */
class ErlcTask extends DefaultTask {

  @InputFile
  File getSourceFile() {
    project.file(this.source)
  }

  void setSourceFile(Object source) {
    this.source = source
  }

  void sourceFile(Object source) {
    this.source = source
  }

  private Object source

  String getSourceExtension() {
    def name = getSourceFile().getName()
    def idx = name.lastIndexOf('.')
    if(idx > 0) {
      return name.substring(idx)
    }
    null
  }

  String getSourceBaseName() {
    def name = getSourceFile().getName()
    def idx = name.lastIndexOf('.')
    if(idx > 0) {
      return name.substring(0,idx)
    }
    name
  }

  String getOutputExtension() {
    def inp = getSourceExtension()
    if(inp == ".erl" || inp == ".S" || inp == ".core") {
      return ".beam"
    }
    if(inp == ".yrl") { return ".erl" }
    if(inp == ".mib") { return ".bin" }
    if(inp == ".bin") { return ".hrl" }
    throw new GradleException('Erlang source file has unsupported extension.')
  }

  File getOutputDir() {
    if(this.outDir == null) { return getSourceFile().getParentFile() }
    project.file(this.outDir)
  }

  void setOutputDir(Object dir) {
    this.outDir = dir
  }

  void outputDir(Object dir) {
    this.outDir = dir
  }

  private Object outDir

  @OutputFile
  File getOutputFile() {
    if(this.outFile == null) {
      project.file(
        getOutputDir().toString()
        + "/" + getSourceBaseName()
        + getOutputExtension())
    }
    else {
      project.file(this.outFile)
    }
  }

  private Object outFile

  String getCompiler() {
    if(this.compiler == null) {
      return project.extensions.erlang.erlc
    }
    compiler
  }

  void setCompiler(Object compiler) {
    this.compiler = compiler
  }

  void compiler(Object compiler) {
    this.compiler = compiler
  }

  private String compiler

  @TaskAction
  void compile() {
    logger.info('Compiling ' + getSourceFile().getName())
    getOutputDir().mkdirs()
    def command = [
      getCompiler(),
      "-o", getOutputDir().toString() + "/",
      getSourceFile().toString()
    ]
    logger.debug(command.join(' '))
    def process = new ProcessBuilder(command).start()
    process.inputStream.eachLine { println it }
    process.waitFor()
    if(process.exitValue() != 0) {
      throw new GradleException('erlc failed.')
    }
  }
}
