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

// Several plugins (stripe_android among them, as of the versions pinned in
// pubspec.yaml) set Java sourceCompatibility=17 for their own module but
// leave Kotlin's target unset, so Kotlin silently follows whichever JDK
// runs the Gradle daemon — "Inconsistent JVM Target Compatibility" the
// moment that JDK isn't also 17. Forcing every KotlinCompile task's target
// directly (not via jvmToolchain(), which depends on JavaPluginExtension
// being registered in an order some plugin modules don't guarantee) fixes
// it without touching a plugin's own build.gradle, which lives in the pub
// cache and wouldn't survive a `flutter pub get` if edited there instead.
subprojects {
    // afterEvaluate, not plugins.withId's immediate callback: at least one
    // plugin module (sentry_flutter, as of the version pinned in
    // pubspec.yaml) sets its OWN compileOptions to 1.8 inside its build
    // script, which would silently overwrite an immediate override set
    // before that script finishes running. Configuring here instead —
    // after every subproject's own build.gradle has already executed —
    // guarantees this is the value that sticks. :app is excluded: the
    // evaluationDependsOn(":app") above means it's already fully evaluated
    // by the time this runs, and afterEvaluate on an evaluated project
    // throws — it doesn't need this fix anyway (its own build.gradle.kts
    // already sets both targets to 17 directly).
    if (name == "app") return@subprojects
    afterEvaluate {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
        // BaseExtension covers both com.android.library and
        // com.android.application; harmless no-op for any subproject
        // that isn't an Android module at all.
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
