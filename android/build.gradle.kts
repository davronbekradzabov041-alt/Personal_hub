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
    // Fix for isar_flutter_libs: set namespace and compileSdk for AGP 8+ compatibility
    if (project.name == "isar_flutter_libs") {
        project.afterEvaluate {
            val android = project.extensions.findByName("android")
            if (android != null) {
                android.javaClass.getMethod("setNamespace", String::class.java).invoke(android, "dev.isar.isar_flutter_libs")
                // Try setting compileSdkVersion (older API) or compileSdk
                try {
                    android.javaClass.getMethod("setCompileSdkVersion", Int::class.java).invoke(android, 34)
                } catch (e: Exception) {
                    try {
                        android.javaClass.getMethod("setCompileSdk", Int::class.java).invoke(android, 34)
                    } catch (e2: Exception) {
                        // Try property access
                        val field = android.javaClass.getDeclaredField("compileSdk")
                        field.isAccessible = true
                        field.set(android, 34)
                    }
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}