import com.android.build.gradle.BaseExtension
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// vosk_flutter(git) 仍钉 vosk-android 0.3.46 + JNA 5.15；强制升到 16 KB 对齐版本
subprojects {
    configurations.configureEach {
        resolutionStrategy {
            eachDependency {
                if (requested.group == "com.alphacephei" &&
                    requested.name == "vosk-android"
                ) {
                    useVersion("0.3.75")
                    because("16 KB page size (Android 15+)")
                }
                if (requested.group == "net.java.dev.jna" &&
                    requested.name == "jna"
                ) {
                    useVersion("5.18.1")
                    because("libjnidispatch 16 KB alignment")
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

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 统一各插件模块：compileSdk + NDK + Java/Kotlin JVM 17
subprojects {
    afterEvaluate {
        extensions.findByType(BaseExtension::class.java)?.apply {
            compileSdkVersion(37)
            // whisper_ggml 等插件声明 NDK 29；本机已装 28，避免拉 29 触发未接受许可
            ndkVersion = "28.2.13676358"
            compileOptions.sourceCompatibility = JavaVersion.VERSION_17
            compileOptions.targetCompatibility = JavaVersion.VERSION_17
        }
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
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
