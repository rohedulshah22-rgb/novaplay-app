import com.android.build.gradle.LibraryExtension
import org.gradle.kotlin.dsl.configure
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompilationTask

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
                compileSdk = 37
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
            tasks.withType<KotlinCompilationTask<*>>().configureEach {
                compilerOptions {
                    jvmTarget.set(JvmTarget.JVM_17)
                }
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
