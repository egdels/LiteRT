plugins {
    `maven-publish`
    signing
    id("io.github.gradle-nexus.publish-plugin") version "2.0.0"
}

group = "de.schliweb"
version = System.getenv("AAR_VERSION") ?: "1.4.1-fdroid"

val aarFile = file("../output/tensorflow-lite.aar")
val javaSourceDir = file("../tflite/java/src/main/java")

val sourcesJar by tasks.registering(Jar::class) {
    archiveClassifier.set("sources")
    from(javaSourceDir)
}

val javadocJar by tasks.registering(Jar::class) {
    archiveClassifier.set("javadoc")
    from(javaSourceDir) {
        include("**/package-info.java")
    }
}

publishing {
    publications {
        create<MavenPublication>("release") {
            groupId = "de.schliweb"
            artifactId = "tensorflow-lite-fdroid"
            version = project.version.toString()

            artifact(aarFile) {
                extension = "aar"
            }
            artifact(sourcesJar)
            artifact(javadocJar)

            pom {
                name.set("TensorFlow Lite (F-Droid compatible build)")
                description.set(
                    "A patched build of TensorFlow Lite (LiteRT) compiled entirely from source " +
                    "without proprietary dependencies (Google Play Services, ai-delivery). " +
                    "Intended for F-Droid and other libre Android distributions. " +
                    "This is NOT an official Google release."
                )
                url.set("https://github.com/egdels/LiteRT")
                inceptionYear.set("2026")
                packaging = "aar"

                licenses {
                    license {
                        name.set("Apache License, Version 2.0")
                        url.set("https://www.apache.org/licenses/LICENSE-2.0.txt")
                        distribution.set("repo")
                    }
                }

                developers {
                    developer {
                        id.set("egdels")
                        name.set("Christian Kierdorf")
                        url.set("https://github.com/egdels")
                    }
                }

                scm {
                    url.set("https://github.com/egdels/LiteRT")
                    connection.set("scm:git:git://github.com/egdels/LiteRT.git")
                    developerConnection.set("scm:git:ssh://git@github.com/egdels/LiteRT.git")
                    tag.set("v${project.version}")
                }

                issueManagement {
                    system.set("GitHub Issues")
                    url.set("https://github.com/egdels/LiteRT/issues")
                }
            }
        }
    }
}

nexusPublishing {
    repositories {
        sonatype {
            nexusUrl.set(uri("https://ossrh-staging-api.central.sonatype.com/service/local/"))
            snapshotRepositoryUrl.set(uri("https://central.sonatype.com/repository/maven-snapshots/"))
            username.set(findProperty("sonatypeUsername") as String? ?: System.getenv("SONATYPE_USERNAME"))
            password.set(findProperty("sonatypePassword") as String? ?: System.getenv("SONATYPE_PASSWORD"))
        }
    }
}

signing {
    val signingKeyId = findProperty("signing.keyId") as String? ?: System.getenv("GPG_KEY_ID")
    val signingKey = findProperty("signing.key") as String? ?: System.getenv("GPG_PRIVATE_KEY")
    val signingPassword = findProperty("signing.password") as String? ?: System.getenv("GPG_PASSPHRASE")

    if (signingKey != null) {
        useInMemoryPgpKeys(signingKeyId, signingKey, signingPassword)
    } else {
        useGpgCmd()
    }

    sign(publishing.publications["release"])
}

tasks.withType<Sign>().configureEach {
    onlyIf {
        gradle.taskGraph.hasTask(":publish") ||
        gradle.taskGraph.hasTask(":publishToSonatype") ||
        gradle.taskGraph.hasTask(":publishToMavenLocal") ||
        gradle.taskGraph.hasTask(":publishReleasePublicationToMavenLocal")
    }
}
