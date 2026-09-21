import com.android.build.gradle.LibraryExtension
import org.gradle.kotlin.dsl.configure

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// on_audio_query_android 1.1.0 predates AGP's mandatory namespace property.
// Supply the package already declared by its AndroidManifest only for that
// dependency, leaving the application module configuration untouched.
subprojects {
    if (project.path == ":on_audio_query_android") {
        plugins.withId("com.android.library") {
            extensions.configure<LibraryExtension> {
                namespace = "com.lucasjosino.on_audio_query"
            }
        }
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
