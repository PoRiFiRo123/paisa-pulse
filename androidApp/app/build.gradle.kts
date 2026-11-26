plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.android")
  id("org.jetbrains.kotlin.plugin.compose")
  id("org.jetbrains.kotlin.plugin.serialization")
}

android {
  namespace = "com.paisapulse.app"
  compileSdk = 36
  defaultConfig {
    applicationId = "com.paisapulse.app"
    minSdk = 26
    targetSdk = 36
    versionCode = (System.getenv("PAISA_BUILD_NUMBER") ?: "1").toInt()
    versionName = "1.0"
    buildConfigField("String", "SUPABASE_URL", "\"${System.getenv("PAISA_SUPABASE_URL") ?: ""}\"")
    buildConfigField("String", "SUPABASE_KEY", "\"${System.getenv("PAISA_SUPABASE_KEY") ?: ""}\"")
    buildConfigField("String", "RELEASE_REPO", "\"${System.getenv("PAISA_RELEASE_REPO") ?: "PoRiFiRo123/paisa-pulse"}\"")
  }
  signingConfigs {
    // CI drops the release key here (same key every build so updates install over each other).
    create("release") {
      storeFile = file(System.getenv("PAISA_KEYSTORE") ?: "debug.keystore")
      storePassword = "android"; keyAlias = "androiddebugkey"; keyPassword = "android"
    }
  }
  buildTypes {
    release {
      isMinifyEnabled = false
      signingConfig = if (file(System.getenv("PAISA_KEYSTORE") ?: "none").exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
    }
  }
  // github: the APK on GitHub Releases (self-update, SMS capture). play: Google Play (Play updates it; no SMS permission).
  flavorDimensions += "store"
  productFlavors {
    create("github") { dimension = "store"; buildConfigField("boolean", "STORE_BUILD", "false") }
    create("play") { dimension = "store"; buildConfigField("boolean", "STORE_BUILD", "true") }
  }
  buildFeatures { compose = true; buildConfig = true }
  compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
  kotlinOptions { jvmTarget = "17" }
  testOptions { unitTests.isReturnDefaultValues = true }
}

dependencies {
  val bom = platform("androidx.compose:compose-bom:2025.06.01")
  implementation(bom)
  implementation("androidx.core:core-ktx:1.16.0")
  implementation("androidx.activity:activity-compose:1.10.1")
  implementation("androidx.fragment:fragment-ktx:1.8.8")
  implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.1")
  implementation("androidx.compose.ui:ui")
  implementation("androidx.compose.foundation:foundation")
  implementation("androidx.compose.material3:material3")
  implementation("androidx.compose.material:material-icons-extended:1.7.8")
  implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
  implementation("dev.chrisbanes.haze:haze:1.6.4")
  implementation("androidx.glance:glance-appwidget:1.1.1")
  implementation("androidx.work:work-runtime-ktx:2.10.2")
  implementation("androidx.biometric:biometric:1.1.0")
  implementation("com.google.zxing:core:3.5.3")
  implementation("com.google.mlkit:text-recognition:16.0.1")
  implementation("io.coil-kt:coil-compose:2.7.0")
  debugImplementation("androidx.compose.ui:ui-tooling")
  testImplementation("junit:junit:4.13.2")
}
