allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // 与 settings.gradle.kts 的宿主 Kotlin 工具链一致，避免插件另载一套编译器。
    buildscript.configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (project.name == "file_selector_android" &&
                requested.group == "org.jetbrains.kotlin" &&
                requested.name.startsWith("kotlin-gradle-plugin")) {
                useVersion("2.4.0")
            }
        }
    }
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
