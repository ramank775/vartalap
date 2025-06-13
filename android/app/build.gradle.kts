import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.firebase-perf")
    id("com.google.firebase.crashlytics")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.one9x.vartalap"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // flutter.ndkVersion


    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility =JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId="com.one9x.vartalap"
        minSdk = 23 // flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

    }

    signingConfigs {
       create("release") {
           keyAlias = keystoreProperties["keyAlias"] as String
           keyPassword = keystoreProperties["keyPassword"] as String
           storeFile = if (keystoreProperties["storeFile"] != null) file(keystoreProperties["storeFile"] as String) else null
           storePassword = keystoreProperties["storePassword"] as String
       }
   }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        
        debug {
            signingConfig = signingConfigs.getByName("release")
        }
    }
    
    flavorDimensions += "app"

    productFlavors {
        
        create("dev") {
            dimension = "app"
            resValue("string", "app_name", "Vartalap Dev")
            versionNameSuffix = "-dev"
            applicationId = "com.one9x.vartalap.dev"
        }

        create("prod") {
            dimension =  "app"
            resValue("string", "app_name", "Vartalap")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.browser:browser:1.4.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
