import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use(::load)
}
val playKey = localProperties.getProperty("REVENUECAT_PLAY_KEY", "")
val testKey = localProperties.getProperty("REVENUECAT_TEST_KEY", "")
val supabaseUrl = localProperties.getProperty("SUPABASE_URL", "")
val supabaseAnonKey = localProperties.getProperty("SUPABASE_ANON_KEY", "")
val reviewCodeDigest = localProperties.getProperty("PLAY_REVIEW_CODE_SHA256", "")
val uploadKeyStore = localProperties.getProperty("PLAY_UPLOAD_KEYSTORE", "")
val uploadKeyAlias = localProperties.getProperty("PLAY_UPLOAD_KEY_ALIAS", "")
val uploadStorePassword = localProperties.getProperty("PLAY_UPLOAD_STORE_PASSWORD", "")
val uploadKeyPassword = localProperties.getProperty("PLAY_UPLOAD_KEY_PASSWORD", uploadStorePassword)

val validateReleaseConfiguration = tasks.register("validateReleaseConfiguration") {
    doLast {
        check(playKey.startsWith("goog_")) { "Set REVENUECAT_PLAY_KEY in ignored android/local.properties before release." }
        check(supabaseUrl.startsWith("https://") && supabaseAnonKey.isNotBlank()) {
            "Set SUPABASE_URL and SUPABASE_ANON_KEY in ignored android/local.properties before release."
        }
        check(reviewCodeDigest.matches(Regex("[a-f0-9]{64}"))) {
            "Set PLAY_REVIEW_CODE_SHA256 in ignored android/local.properties before release."
        }
        check(uploadKeyStore.isNotBlank() && rootProject.file(uploadKeyStore).isFile) {
            "Set PLAY_UPLOAD_KEYSTORE to the external upload keystore before release."
        }
        check(uploadKeyAlias.isNotBlank() && uploadStorePassword.isNotBlank() && uploadKeyPassword.isNotBlank()) {
            "Set the external upload key alias and passwords in ignored android/local.properties."
        }
    }
}

android {
    namespace = "com.jackwallner.hockey"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.jackwallner.hockey"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
        // Store captures run on demand with `am instrument -e class ...StoreScreenshotTest`, never in the connected suite.
        testInstrumentationRunnerArguments["notClass"] = "com.jackwallner.hockey.StoreScreenshotTest"
        buildConfigField("String", "REVENUECAT_API_KEY", "\"$testKey\"")
        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKey\"")
        buildConfigField("String", "PLAY_REVIEW_CODE_SHA256", "\"$reviewCodeDigest\"")
    }
    buildFeatures {
        buildConfig = true
        compose = true
    }
    if (uploadKeyStore.isNotBlank()) {
        signingConfigs {
            create("playUpload") {
                storeFile = rootProject.file(uploadKeyStore)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }
    buildTypes {
        debug { isDebuggable = true }
        release {
            isMinifyEnabled = true
            // Play's release dashboard flags an unshrunk bundle as a memory cost.
            isShrinkResources = true
            if (uploadKeyStore.isNotBlank()) signingConfig = signingConfigs.getByName("playUpload")
            buildConfigField("String", "REVENUECAT_API_KEY", "\"$playKey\"")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        create("qa") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            buildConfigField("String", "REVENUECAT_API_KEY", "\"\"")
            matchingFallbacks += "release"
        }
    }
    sourceSets { getByName("qa").kotlin.directories.add("src/release/java") }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    // The bundled history is gzip JSON named .bin: the asset packager silently
    // inflates and renames any .gz asset, and storing it compressed again would
    // cost a second inflate on every past-season load.
    androidResources { noCompress += "bin" }
    testOptions {
        animationsDisabled = true
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
    }
}

tasks.configureEach {
    if (name.contains("Release") && name != "validateReleaseConfiguration") dependsOn(validateReleaseConfiguration)
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.activity:activity-compose:1.12.0")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("com.revenuecat.purchases:purchases:10.23.2")
    implementation("androidx.browser:browser:1.10.0")
    implementation("com.google.android.play:review-ktx:2.0.2")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    androidTestImplementation(platform("androidx.compose:compose-bom:2026.06.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:core-ktx:1.7.0")
    // Compose test pulls an older Espresso that calls InputManager.getInstance, gone on API 36.
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.4.0")
    androidTestUtil("androidx.test:orchestrator:1.6.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    constraints {
        // review-ktx 2.0.2 pulls fragment 1.1.0, which Play reports as outdated.
        implementation("androidx.fragment:fragment:1.8.9") { because("Play flags fragment 1.1.0 as an outdated SDK") }
    }
}
