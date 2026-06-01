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
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// integration_test uses androidx.test:runner:1.2+ which hits Maven metadata on every
// release build. Pin versions so release builds work reliably (and offline if cached).
subprojects {
    configurations.configureEach {
        resolutionStrategy {
            force(
                "androidx.test:runner:1.5.2",
                "androidx.test:rules:1.5.0",
                "androidx.test.espresso:espresso-core:3.5.1",
            )
            eachDependency {
                when ("${requested.group}:${requested.name}") {
                    "androidx.test:runner" -> useVersion("1.5.2")
                    "androidx.test:rules" -> useVersion("1.5.0")
                    "androidx.test.espresso:espresso-core" -> useVersion("3.5.1")
                }
            }
        }
    }
}

// Configure Java 17 / Kotlin JVM 17 for all Android modules (app + Flutter plugins).
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (namespace.isNullOrEmpty()) {
                val manifestFile = project.file("src/main/AndroidManifest.xml")
                val fromManifest =
                    if (manifestFile.exists()) {
                        Regex("""package="([^"]+)"""")
                            .find(manifestFile.readText())
                            ?.groupValues
                            ?.get(1)
                    } else {
                        null
                    }
                val grp = project.group.toString()
                namespace =
                    fromManifest?.takeIf { it.isNotEmpty() }
                        ?: grp.takeIf { it.isNotEmpty() && it != "unspecified" }
            }
            compileSdk = 36
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }

    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
