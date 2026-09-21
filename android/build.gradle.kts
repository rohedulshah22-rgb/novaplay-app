import groovy.lang.GroovyObjectSupport

private class FlutterPluginCompatibilityExtension : GroovyObjectSupport() {
    var compileSdkVersion: Int = 34
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// android_file_picker 2.0.0 reads Flutter's legacy `flutter` extension from
// its plugin module. Modern Flutter no longer injects that extension there,
// so provide the minimal value it needs without affecting other plugins.
subprojects {
    if (project.name == "android_file_picker" &&
        extensions.findByName("flutter") == null
    ) {
        extensions.add(
            "flutter",
            FlutterPluginCompatibilityExtension(),
        )
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
